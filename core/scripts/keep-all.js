'use strict';
// /devlog-tracker:keep-all (docs/design/keep-all.md): scan every devlog file
// in .devlog/ and, after the user confirms a plan, move Rounds from any of
// them into topic files in one all-or-nothing run. keep-all.sh resolves
// paths, holds the devlog lock and calls this; the functions are exported
// for keep-all.test.js.
const fs = require('fs');
const path = require('path');
const crypto = require('crypto');
const { spawnSync } = require('child_process');

const FENCE = /^[ \t]*```/;
const ORIGIN = /^<!-- devlog-origin: (branch|detached)=(.*) -->$/;
const KEPT_HEAD = '# Kept log';

// Splits a devlog file into `## ` blocks, ignoring headings inside ```
// fences (same rule as devlog-md.sh). Lines before the first block are the
// prefix (project summary, origin marker, kept provenance header).
function parseBlocks(text) {
  const lines = text.replace(/\n$/, '').split('\n');
  if (text === '') lines.length = 0;
  const starts = [];
  let fence = false;
  lines.forEach((line, i) => {
    if (FENCE.test(line)) { fence = !fence; return; }
    if (!fence && line.startsWith('## ')) starts.push(i);
  });
  const blocks = starts.map((start, k) => {
    const end = k + 1 < starts.length ? starts[k + 1] - 1 : lines.length - 1;
    const heading = lines[start];
    const m = heading.match(/^## Round (\d+)/);
    const block = { start, end, heading, round: m ? Number(m[1]) : null, ts: '', status: '' };
    if (m) {
      const t = heading.match(/ — (.*)$/);
      block.ts = t ? t[1].trim() : '';
      block.status = roundStatus(lines.slice(start, end + 1));
    }
    return block;
  });
  return { lines, blocks, firstBlock: starts.length ? starts[0] : lines.length };
}

function roundStatus(lines) {
  let fence = false, inStatus = false, value = '';
  for (const line of lines) {
    if (FENCE.test(line)) { fence = !fence; continue; }
    if (fence) continue;
    if (/^### Status\s*$/.test(line)) { inStatus = true; value = ''; continue; }
    if (/^### /.test(line)) { inStatus = false; continue; }
    if (inStatus && line.trim() !== '') value = line.trim();
  }
  return value;
}

function tsKey(ts) {
  const iso = ts.replace(/([+-]\d\d)(\d\d)$/, '$1:$2');
  const t = Date.parse(iso);
  return Number.isNaN(t) ? Infinity : t;
}

function git(projectDir, args) {
  const r = spawnSync('git', ['-C', projectDir, ...args], { encoding: 'utf8' });
  return r.status === 0 ? r.stdout.trim() : null;
}

function branchState(projectDir, name) {
  if (git(projectDir, ['show-ref', '--verify', '--quiet', `refs/heads/${name}`]) === null) {
    return git(projectDir, ['rev-parse', '--git-dir']) === null ? 'unknown' : 'gone';
  }
  const base = (git(projectDir, ['for-each-ref', '--format=%(refname:short)', 'refs/heads/']) || '')
    .split('\n').find(b => /^(main|master)$/i.test(b));
  if (!base || base === name) return 'active';
  return git(projectDir, ['merge-base', '--is-ancestor', name, base]) === null ? 'active' : 'merged';
}

function classify(file, text, c) {
  if (/^devlog\.lessons\..*\.md$/.test(file)) return null;
  if (file === c.current) return 'current';
  if (file === 'devlog.archive.md') return 'archive';
  if (text.split('\n', 1)[0] === KEPT_HEAD) return 'kept';
  return 'branch';
}

function describeOrigin(src, text, c) {
  if (src.kind !== 'current' && src.kind !== 'branch') return;
  const m = text.split('\n', 1)[0].match(ORIGIN);
  if (m) {
    src.origin = m[2]; src.originFrom = 'marker';
    src.state = m[1] === 'branch' ? branchState(c.projectDir, m[2]) : 'n/a';
  } else if (src.file === 'devlog.md') {
    src.origin = 'main'; src.originFrom = 'default'; src.state = 'n/a';
  } else if (src.kind === 'current' && c.origin) {
    const [kind, name] = [c.origin.slice(0, c.origin.indexOf('=')), c.origin.slice(c.origin.indexOf('=') + 1)];
    src.origin = name; src.originFrom = 'env';
    src.state = kind === 'branch' ? branchState(c.projectDir, name) : 'n/a';
  } else {
    src.origin = src.file.replace(/^devlog\./, '').replace(/\.md$/, '');
    src.originFrom = 'filename';
    const st = branchState(c.projectDir, src.origin);
    src.state = st === 'gone' ? 'unknown' : st;
  }
}

function sha(s) {
  return crypto.createHash('sha1').update(s).digest('hex');
}

function scan(c) {
  const files = fs.existsSync(c.devlogDir)
    ? fs.readdirSync(c.devlogDir).filter(f => /^devlog.*\.md$/.test(f)).sort()
    : [];
  const sources = [];
  const rounds = [];
  files.forEach((file, order) => {
    const text = fs.readFileSync(path.join(c.devlogDir, file), 'utf8');
    const kind = classify(file, text, c);
    if (!kind) return;
    const parsed = parseBlocks(text);
    const src = { file, kind, text, parsed };
    describeOrigin(src, text, c);
    sources.push(src);
    const rb = parsed.blocks.filter(b => b.round !== null);
    let lastDone = -1;
    rb.forEach((b, i) => { if (b.status === 'DONE') lastDone = i; });
    rb.forEach((b, i) => {
      let movable = true;
      if (kind === 'current' && String(b.round) === String(c.open)) movable = false;
      if (kind === 'branch' && i > lastDone) movable = false;
      rounds.push({
        file, kind, order, block: b, round: b.round, ts: b.ts, status: b.status, movable,
        line: b.start + 1, text: parsed.lines.slice(b.start, b.end + 1).join('\n'),
      });
    });
  });
  rounds.sort((a, b) => tsKey(a.ts) - tsKey(b.ts) || a.order - b.order || a.line - b.line);
  rounds.forEach((r, i) => { r.id = i + 1; });
  return { sources, rounds, fingerprint: fingerprint(sources, rounds, rounds.length) };
}

// Covers the scanned Rounds and every non-current source, not whole files:
// between scan and apply, Stop merges the proposal turn's Round into the
// current file (and may create it), which must not invalidate the plan.
function fingerprint(sources, rounds, count) {
  const parts = sources.filter(s => s.kind !== 'current').map(s => `S ${s.file} ${s.kind}`);
  for (const r of rounds.slice(0, count)) parts.push(`R ${r.file} ${r.block.heading} ${r.movable} ${sha(r.text)}`);
  return sha(parts.join('\n')).slice(0, 16);
}

function formatScan(s) {
  if (!s.rounds.some(r => r.movable)) return 'NOTHING\n';
  const out = [`FINGERPRINT=${s.fingerprint} COUNT=${s.rounds.length}`];
  for (const src of s.sources) {
    let line = `SOURCE file=${src.file} kind=${src.kind}`;
    if (src.origin !== undefined) line += ` origin=${src.origin} origin_from=${src.originFrom} state=${src.state}`;
    out.push(line);
  }
  for (const r of s.rounds) {
    out.push(`ROUND id=${r.id} file=${r.file} round=${r.round} line=${r.line} ts=${r.ts || '-'} status=${r.status || '-'} movable=${r.movable ? 1 : 0}`);
  }
  return out.join('\n') + '\n';
}

function normalizeName(raw) {
  if (raw === 'devlog.md') return null;
  let n = raw.trim();
  if (n.startsWith('devlog.')) n = n.slice(7);
  if (n.endsWith('.md')) n = n.slice(0, -3);
  n = n.replace(/\s/g, '-').replace(/-+/g, '-').replace(/^-|-$/g, '');
  if (!n || n === 'archive' || /^lessons\./.test(n) || /[/\\]|\.\./.test(n) || n.length > 64) return null;
  return n;
}

function parsePlan(planText) {
  const segs = [];
  for (const line of planText.split('\n')) {
    if (line.trim() === '') continue;
    const [name = '', desc = '', ids = ''] = line.split('\t');
    const list = [];
    for (const part of ids.split(',').map(p => p.trim()).filter(Boolean)) {
      const m = part.match(/^(\d+)(?:-(\d+))?$/);
      if (!m) throw new Error(`id 清單格式錯誤：${part}`);
      const a = Number(m[1]), b = m[2] ? Number(m[2]) : a;
      if (a > b) throw new Error(`id 範圍起點大於終點：${part}`);
      for (let i = a; i <= b; i++) list.push(i);
    }
    segs.push({ rawName: name.trim(), desc: desc.replace(/[\r\n]+/g, ' ').trim(), ids: list });
  }
  if (!segs.length) throw new Error('計畫是空的');
  return segs;
}

function trimBlank(lines) {
  let a = 0, b = lines.length;
  while (a < b && lines[a].trim() === '') a++;
  while (b > a && lines[b - 1].trim() === '') b--;
  return lines.slice(a, b);
}

function joinPieces(pieces) {
  const kept = pieces.map(trimBlank).filter(p => p.length);
  return kept.map(p => p.join('\n')).join('\n\n') + (kept.length ? '\n' : '');
}

function ranges(nums) {
  const s = [...nums].sort((a, b) => a - b);
  const out = [];
  for (let i = 0; i < s.length; i++) {
    let j = i;
    while (j + 1 < s.length && s[j + 1] === s[j] + 1) j++;
    out.push(i === j ? `${s[i]}` : `${s[i]}-${s[j]}`);
    i = j;
  }
  return out.join(', ');
}

function nowIso() {
  const d = new Date();
  const pad = n => String(Math.abs(n)).padStart(2, '0');
  const off = -d.getTimezoneOffset();
  return `${d.getFullYear()}-${pad(d.getMonth() + 1)}-${pad(d.getDate())}T${pad(d.getHours())}:` +
    `${pad(d.getMinutes())}:${pad(d.getSeconds())}${off >= 0 ? '+' : '-'}${pad(Math.trunc(off / 60))}:${pad(off % 60)}`;
}

// Kept files begin with "# Kept log", then blank / "- key: value" lines.
function keptHeaderEnd(lines, firstBlock) {
  let i = 1;
  while (i < firstBlock && (lines[i].trim() === '' || lines[i].startsWith('- '))) i++;
  return i;
}

function apply(c, planText, expected, count) {
  const s = scan(c);
  if (s.rounds.length < count || fingerprint(s.sources, s.rounds, count) !== expected) {
    throw new Error('fingerprint 不符：scan 之後 devlog 檔已被改動，請重新執行 keep-all');
  }
  const segs = parsePlan(planText);
  const byId = new Map(s.rounds.slice(0, count).map(r => [r.id, r]));
  const owner = new Map();
  const errors = [];
  const consumed = new Set(s.sources.filter(x => x.kind === 'kept' && x.parsed.blocks.some(b => b.round !== null)).map(x => x.file));

  segs.forEach((seg, i) => {
    seg.name = normalizeName(seg.rawName);
    if (!seg.name) { errors.push(`第 ${i + 1} 段檔名無效：${seg.rawName}`); return; }
    seg.file = `devlog.${seg.name}.md`;
    if (segs.findIndex(o => o.file === seg.file) !== i) errors.push(`第 ${i + 1} 段檔名與其他段重複：${seg.file}`);
    if (fs.existsSync(path.join(c.devlogDir, seg.file)) && !consumed.has(seg.file)) {
      errors.push(`第 ${i + 1} 段目標檔已存在：${seg.file}`);
    }
    if (!seg.ids.length) errors.push(`第 ${i + 1} 段沒有任何 Round`);
    for (const id of seg.ids) {
      const r = byId.get(id);
      if (!r) errors.push(`#${id} 不存在`);
      else if (!r.movable) errors.push(`#${id}（${r.file} Round ${r.round}）不可搬`);
      else if (owner.has(id)) errors.push(`#${id} 重複出現在兩段`);
      else owner.set(id, seg);
    }
  });
  for (const r of byId.values()) {
    if (r.kind === 'kept' && !owner.has(r.id)) errors.push(`#${r.id}（${r.file} Round ${r.round}）是既有 kept 檔的 Round，必須分進某一段`);
  }
  if (errors.length) throw new Error(errors.join('\n'));

  // Assign every block of every source: moved Rounds to their segment,
  // Checkpoints (any block, for kept files) along with the Round before them.
  const pieces = new Map(segs.map(seg => [seg, []])); // seg -> [{id, sub, lines}]
  const prefixes = new Map(segs.map(seg => [seg, []]));
  const rewritten = new Map(); // file -> new text | null (delete)
  const movedFromCurrent = new Set();
  const touchedFiles = new Set();

  for (const src of s.sources) {
    const { lines, blocks, firstBlock } = src.parsed;
    const roundOf = new Map(s.rounds.filter(r => r.file === src.file).map(r => [r.block, r]));
    const stay = [];
    let prev = null; // last Round block's {seg, id}
    let pendingKept = []; // kept-file blocks before the first Round
    let touched = false;
    blocks.forEach((b, k) => {
      const blines = lines.slice(b.start, b.end + 1);
      const r = roundOf.get(b);
      if (r) {
        const seg = owner.get(r.id);
        prev = seg ? { seg, id: r.id, sub: 0 } : null;
        if (seg) {
          touched = true;
          pieces.get(seg).push({ id: r.id, sub: 0, lines: blines });
          if (src.kind === 'current') movedFromCurrent.add(r.round);
          for (const p of pendingKept) pieces.get(seg).push({ id: r.id, sub: -1 + p.k / 1e6, lines: p.lines });
          pendingKept = [];
        } else stay.push(blines);
        return;
      }
      const follows = src.kind === 'kept' || b.heading.startsWith('## Checkpoint');
      if (follows && prev) {
        prev.sub += 1;
        pieces.get(prev.seg).push({ id: prev.id, sub: prev.sub, lines: blines });
        touched = true;
      } else if (src.kind === 'kept' && !prev) {
        pendingKept.push({ k, lines: blines });
      } else {
        stay.push(blines);
      }
    });

    if (src.kind === 'kept' && consumed.has(src.file)) {
      const first = s.rounds.find(r => r.file === src.file);
      const hEnd = keptHeaderEnd(lines, firstBlock);
      prefixes.get(owner.get(first.id)).push({ id: first.id, lines: lines.slice(hEnd, firstBlock) });
      rewritten.set(src.file, null);
      continue;
    }
    if (!touched) continue;
    touchedFiles.add(src.file);
    const text = joinPieces([lines.slice(0, firstBlock), ...stay]);
    const left = stay.length && parseBlocks(text).blocks.some(b => b.round !== null);
    rewritten.set(src.file, src.kind === 'archive' && !left && trimBlank(lines.slice(0, firstBlock)).length === 0 ? null : text);
  }

  // Kept index: drop lines pointing at deleted kept files everywhere, add
  // the new files to the current file's index.
  const deletedKept = [...consumed].filter(f => !segs.some(seg => seg.file === f));
  const reused = [...consumed].filter(f => segs.some(seg => seg.file === f));
  const staleIndex = new Set([...deletedKept, ...reused]);
  const keptAt = nowIso();
  const newIndex = segs.map(seg => {
    const n = pieces.get(seg).filter(p => p.sub === 0).length;
    return `- \`${seg.file}\`：keep-all，${n} 輪，kept_at ${keptAt}${seg.desc ? `，${seg.desc}` : ''}`;
  });
  for (const src of s.sources) {
    if (rewritten.get(src.file) === null) continue;
    const base = rewritten.has(src.file) ? rewritten.get(src.file) : src.text;
    const updated = rewriteIndex(base, staleIndex, src.kind === 'current' ? newIndex : []);
    if (updated !== base) rewritten.set(src.file, updated);
  }
  // A branch file keep-all emptied (only its origin marker left) is
  // deleted, unless the branch is still active: checking it out again
  // would migrate main's unfinished tail into a fresh file.
  for (const src of s.sources) {
    const t = rewritten.get(src.file);
    if (src.kind !== 'branch' || src.file === 'devlog.md' || src.state === 'active' || typeof t !== 'string') continue;
    if (!touchedFiles.has(src.file)) continue;
    if (t.split('\n').every(l => l.trim() === '' || ORIGIN.test(l))) rewritten.set(src.file, null);
  }
  if (!s.sources.some(x => x.kind === 'current')) {
    const head = c.origin ? `<!-- devlog-origin: ${c.origin} -->\n` : '';
    rewritten.set(c.current, rewriteIndex(head, staleIndex, newIndex));
  }

  // Build targets.
  const targets = new Map();
  for (const seg of segs) {
    const ps = pieces.get(seg).sort((a, b) => a.id - b.id || a.sub - b.sub);
    const perFile = new Map();
    for (const id of seg.ids) {
      const r = byId.get(id);
      if (!perFile.has(r.file)) perFile.set(r.file, []);
      perFile.get(r.file).push(r.round);
    }
    const header = ['# Kept log', '', '- source: keep-all',
      ...[...perFile].map(([f, ns]) => `- rounds: ${f} ${ranges(ns)}`), `- kept_at: ${keptAt}`];
    const pre = prefixes.get(seg).sort((a, b) => a.id - b.id).map(p => p.lines);
    targets.set(seg.file, joinPieces([header, ...pre, ...ps.map(p => p.lines)]));
  }

  // Verify: every moved Round lands exactly once, none stays behind.
  const movedCount = owner.size;
  let inTargets = 0;
  for (const text of targets.values()) inTargets += parseBlocks(text).blocks.filter(b => b.round !== null).length;
  let before = 0, after = 0;
  for (const src of s.sources) {
    if (!rewritten.has(src.file)) continue;
    before += src.parsed.blocks.filter(b => b.round !== null).length;
    const t = rewritten.get(src.file);
    if (t !== null) after += parseBlocks(t).blocks.filter(b => b.round !== null).length;
  }
  if (inTargets !== movedCount || before - after !== movedCount) {
    throw new Error(`搬移驗證失敗：預期 ${movedCount} 輪，目標檔 ${inTargets} 輪，來源減少 ${before - after} 輪；未寫入任何檔`);
  }

  // Backup, then commit: targets first, then rewritten sources, then deletions.
  const stamp = keptAt.slice(0, 19).replace(/[-:]/g, '').replace('T', '-');
  const backup = path.join(c.devlogDir, '.keep-all-backup', stamp);
  fs.mkdirSync(backup, { recursive: true });
  for (const file of rewritten.keys()) {
    const p = path.join(c.devlogDir, file);
    if (fs.existsSync(p)) fs.copyFileSync(p, path.join(backup, file));
  }
  const out = [];
  try {
    const writeAtomic = (file, text) => {
      const p = path.join(c.devlogDir, file);
      fs.writeFileSync(`${p}.keep-all.tmp`, text);
      fs.renameSync(`${p}.keep-all.tmp`, p);
    };
    for (const [file, text] of targets) {
      writeAtomic(file, text);
      out.push(`KEPT=${path.join(c.devlogDir, file)} ROUNDS=${pieces.get(segs.find(x => x.file === file)).filter(p => p.sub === 0).length}`);
    }
    for (const [file, text] of rewritten) {
      if (text === null) {
        if (targets.has(file)) continue; // reused name: already replaced
        fs.rmSync(path.join(c.devlogDir, file), { force: true });
        out.push(`DELETED=${path.join(c.devlogDir, file)}`);
      } else writeAtomic(file, text);
    }
  } catch (e) {
    throw new Error(`寫入途中失敗：${e.message}\n原始檔備份在 ${backup}`);
  }

  const span = path.join(c.devlogDir, '.span-open');
  if (fs.existsSync(span)) {
    const m = fs.readFileSync(span, 'utf8').match(/"round"\s*:\s*(\d+)/);
    if (m && movedFromCurrent.has(Number(m[1]))) fs.rmSync(span, { force: true });
  }
  out.push(`BACKUP=${backup}`);
  return out.join('\n') + '\n';
}

// Removes index lines naming a file in `stale`, appends `add` to the
// `## Kept 索引` block (created at the end if missing). A block left
// with no lines is dropped.
function rewriteIndex(text, stale, add) {
  const { lines, blocks, firstBlock } = parseBlocks(text);
  const idx = blocks.find(b => b.heading.startsWith('## Kept 索引'));
  const named = l => stale.has((l.match(/`(devlog\.[^`]+\.md)`/) || [])[1]);
  if (!idx) return add.length ? joinPieces([lines, ['## Kept 索引', ...add]]) : text;
  const body = lines.slice(idx.start + 1, idx.end + 1);
  if (!add.length && !body.some(named)) return text;
  const kept = [...trimBlank(body.filter(l => !named(l))), ...add];
  const pieces = [lines.slice(0, firstBlock)];
  for (const b of blocks) {
    if (b !== idx) pieces.push(lines.slice(b.start, b.end + 1));
    else if (kept.length) pieces.push(['## Kept 索引', ...kept]);
  }
  return joinPieces(pieces);
}

function main(argv) {
  const opts = {};
  for (let i = 0; i < argv.length; i++) {
    const k = argv[i];
    if (k === '--scan') opts.scan = true;
    else if (['--dir', '--project', '--current', '--open', '--origin', '--apply', '--fingerprint', '--count'].includes(k)) opts[k.slice(2)] = argv[++i] ?? '';
    else { process.stderr.write(`未知參數：${k}\n`); return 2; }
  }
  const c = { devlogDir: opts.dir, projectDir: opts.project, current: opts.current, open: opts.open || '', origin: opts.origin || '' };
  try {
    if (opts.scan) { process.stdout.write(formatScan(scan(c))); return 0; }
    if (opts.apply) {
      const plan = fs.readFileSync(opts.apply, 'utf8');
      process.stdout.write(apply(c, plan, opts.fingerprint || '', Number(opts.count || 0)));
      return 0;
    }
    process.stderr.write('需要 --scan 或 --apply\n');
    return 2;
  } catch (e) {
    process.stderr.write(`${e.message}\n`);
    return 1;
  }
}

module.exports = { parseBlocks, scan, apply, formatScan, normalizeName, parsePlan };

if (require.main === module) process.exitCode = main(process.argv.slice(2));
