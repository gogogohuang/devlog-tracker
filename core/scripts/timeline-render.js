#!/usr/bin/env node
'use strict';
// report-devlog.sh --json --rounds 的輸出 → 一份自足的 HTML 時間軸
// （docs/design/read-side-and-promote.md C）。零相依；所有 devlog 文字先跳脫
// 再轉 Markdown 子集，不輸出任何來自 devlog 的原始 HTML。

const STATUSES = ['DONE', 'IN_PROGRESS', 'BLOCKED', 'INTERRUPTED'];

function escapeHtml(s) {
  return String(s)
    .replace(/&/g, '&amp;')
    .replace(/</g, '&lt;')
    .replace(/>/g, '&gt;')
    .replace(/"/g, '&quot;')
    .replace(/'/g, '&#39;');
}

// http(s) 與相對路徑可以當連結；其他 scheme（javascript:、data: …）與
// protocol-relative（//host）一律不給連結。
function safeHref(url) {
  const u = String(url).trim();
  // A leading/embedded C0 control char (e.g. \u0001) hides the real scheme
  // from the tests below, but browsers strip it and still run it — reject.
  if (/[\u0000-\u001F\u007F]/.test(u)) return null;
  if (/^https?:\/\//i.test(u)) return u;
  if (u.startsWith('//')) return null;
  if (/^[a-z][a-z0-9+.-]*:/i.test(u)) return null;
  return u;
}

function emphasis(raw) {
  return escapeHtml(raw).replace(/\*\*([^*]+)\*\*/g, '<strong>$1</strong>');
}

function inline(text) {
  return String(text)
    .split(/(`[^`]+`)/)
    .map((part) => {
      if (/^`[^`]+`$/.test(part)) return `<code>${escapeHtml(part.slice(1, -1))}</code>`;
      const re = /\[([^\]]+)\]\(([^)\s]+)\)/g;
      let out = '';
      let last = 0;
      let m;
      while ((m = re.exec(part))) {
        out += emphasis(part.slice(last, m.index));
        const href = safeHref(m[2]);
        out += href === null ? emphasis(m[0]) : `<a href="${escapeHtml(href)}">${emphasis(m[1])}</a>`;
        last = re.lastIndex;
      }
      return out + emphasis(part.slice(last));
    })
    .join('');
}

const FENCE = /^\s*```/;
const HEADING = /^(#{1,4})\s+(.*)$/;
const LIST_ITEM = /^(\s*)([-*]|\d+\.)\s+(.*)$/;
const TABLE_ROW = /^\s*\|/;
const TABLE_SEP = /^\s*\|?\s*:?-{3,}/;

function tableCells(line) {
  return line.trim().replace(/^\|/, '').replace(/\|$/, '').split('|').map((c) => c.trim());
}

function renderMarkdown(md) {
  const lines = String(md || '').split('\n');
  const out = [];
  let i = 0;
  while (i < lines.length) {
    const line = lines[i];
    if (FENCE.test(line)) {
      const buf = [];
      i++;
      while (i < lines.length && !FENCE.test(lines[i])) buf.push(lines[i++]);
      i++;
      out.push(`<pre><code>${escapeHtml(buf.join('\n'))}</code></pre>`);
      continue;
    }
    const h = HEADING.exec(line);
    if (h) {
      const level = Math.min(h[1].length + 2, 6);
      out.push(`<h${level}>${inline(h[2])}</h${level}>`);
      i++;
      continue;
    }
    if (TABLE_ROW.test(line) && i + 1 < lines.length && TABLE_SEP.test(lines[i + 1])) {
      const head = tableCells(line);
      i += 2;
      const rows = [];
      while (i < lines.length && TABLE_ROW.test(lines[i])) rows.push(tableCells(lines[i++]));
      const th = head.map((c) => `<th>${inline(c)}</th>`).join('');
      const tb = rows.map((r) => `<tr>${r.map((c) => `<td>${inline(c)}</td>`).join('')}</tr>`).join('');
      out.push(`<table><thead><tr>${th}</tr></thead><tbody>${tb}</tbody></table>`);
      continue;
    }
    if (LIST_ITEM.test(line)) {
      const m = LIST_ITEM.exec(line);
      const ordered = /\d/.test(m[2]);
      const items = [];
      while (i < lines.length) {
        const m = LIST_ITEM.exec(lines[i]);
        if (m) {
          const isOrdered = /\d/.test(m[2]);
          if (isOrdered !== ordered) break; // Different list type, stop here
          items.push({ nested: m[1].length >= 2, text: m[3] });
          i++;
        } else if (items.length && /^\s{2,}\S/.test(lines[i])) {
          items[items.length - 1].text += ' ' + lines[i].trim();
          i++;
        } else break;
      }
      const tag = ordered ? 'ol' : 'ul';
      const lis = items.map((it) => `<li${it.nested ? ' class="nested"' : ''}>${inline(it.text)}</li>`).join('');
      out.push(`<${tag}>${lis}</${tag}>`);
      continue;
    }
    if (/^\s*$/.test(line)) {
      i++;
      continue;
    }
    // 至少吃掉目前這一行，避免「像表格但不是表格」的行卡住迴圈。
    const para = [line];
    i++;
    while (
      i < lines.length &&
      !/^\s*$/.test(lines[i]) &&
      !FENCE.test(lines[i]) &&
      !HEADING.test(lines[i]) &&
      !LIST_ITEM.test(lines[i]) &&
      !TABLE_ROW.test(lines[i])
    ) {
      para.push(lines[i++]);
    }
    out.push(`<p>${para.map(inline).join('<br>')}</p>`);
  }
  return out.join('\n');
}

function statusOf(s) {
  return STATUSES.includes(s) ? s : 'NONE';
}

function roundCard(r) {
  const st = statusOf(r.status);
  const parts = [];
  if (r.input) parts.push(`<h4>User Input</h4><pre><code>${escapeHtml(r.input)}</code></pre>`);
  if (r.reply) parts.push(`<h4>Reply</h4>${renderMarkdown(r.reply)}`);
  if (r.handoff) parts.push(`<h4>Handoff</h4>${renderMarkdown(r.handoff)}`);
  for (const seg of r.segments || []) parts.push(`<div class="seg">${renderMarkdown('#### ' + seg)}</div>`);
  const details = parts.length ? `<details><summary>詳細</summary>${parts.join('\n')}</details>` : '';
  return `<article class="card round" data-status="${st}" data-branch="${escapeHtml(r.branch)}">
<header><span class="badge b-${st}">${st === 'NONE' ? '—' : st}</span><strong>Round ${Number(r.n)}</strong><time>${escapeHtml(r.at || '')}</time><span class="branch">${escapeHtml(r.branch)}</span></header>
<div class="summary">${renderMarkdown(r.summary)}</div>
${details}
</article>`;
}

function checkpointCard(c) {
  return `<article class="card checkpoint" data-status="CHECKPOINT" data-branch="${escapeHtml(c.branch)}">
<header><span class="badge b-CHECKPOINT">CHECKPOINT</span><strong>${escapeHtml(c.heading)}</strong><span class="branch">${escapeHtml(c.branch)}</span></header>
<details open><summary>內容</summary>${renderMarkdown(c.body)}</details>
</article>`;
}

// Round 依時間排序；Checkpoint 沒有時間，排在同一檔案中位於它之前的最後一個
// Round 後面。
function timelineItems(data) {
  const rounds = data.rounds || [];
  const items = rounds.map((r, idx) => ({ key: r.at || '', order: 0, idx, html: roundCard(r) }));
  (data.checkpoint_blocks || []).forEach((c, idx) => {
    let prev = null;
    for (const r of rounds) {
      if (r.file === c.file && r.line < c.line && (!prev || r.line > prev.line)) prev = r;
    }
    items.push({ key: prev ? prev.at || '' : '', order: 1, idx, html: checkpointCard(c) });
  });
  items.sort((a, b) => (a.key < b.key ? -1 : a.key > b.key ? 1 : a.order - b.order || a.idx - b.idx));
  return items.map((it) => it.html);
}

const CSS = `:root{--bg:#f7f7f5;--fg:#1f2328;--muted:#656d76;--card:#fff;--line:#d0d7de;--code:#eff1f3;
--done:#1a7f37;--progress:#0969da;--blocked:#cf222e;--interrupted:#9a6700;--checkpoint:#8250df;--none:#6e7781}
@media (prefers-color-scheme:dark){:root{--bg:#0d1117;--fg:#e6edf3;--muted:#8d96a0;--card:#161b22;--line:#30363d;--code:#1f242c;
--done:#3fb950;--progress:#4493f8;--blocked:#f85149;--interrupted:#d29922;--checkpoint:#ab7df8;--none:#8d96a0}}
*{box-sizing:border-box}body{margin:0;background:var(--bg);color:var(--fg);font:15px/1.6 system-ui,-apple-system,"Segoe UI","Noto Sans TC",sans-serif}
main{max-width:920px;margin:0 auto;padding:24px 16px 64px}h1{font-size:22px;margin:0 0 4px}.meta{color:var(--muted);font-size:13px;margin-bottom:16px}
.stats{display:flex;flex-wrap:wrap;gap:8px;margin-bottom:16px}.stat{background:var(--card);border:1px solid var(--line);border-radius:8px;padding:6px 12px;font-size:13px}
.stat b{font-size:17px;margin-right:4px}.filters{display:flex;flex-wrap:wrap;gap:8px;margin-bottom:20px}
.filters input,.filters select{font:inherit;padding:6px 10px;border:1px solid var(--line);border-radius:6px;background:var(--card);color:var(--fg)}
.filters input{flex:1;min-width:160px}.card{background:var(--card);border:1px solid var(--line);border-left:4px solid var(--none);border-radius:8px;padding:12px 16px;margin-bottom:12px;overflow-wrap:anywhere}
.card[data-status=DONE]{border-left-color:var(--done)}.card[data-status=IN_PROGRESS]{border-left-color:var(--progress)}
.card[data-status=BLOCKED]{border-left-color:var(--blocked)}.card[data-status=INTERRUPTED]{border-left-color:var(--interrupted)}
.card[data-status=CHECKPOINT]{border-left-color:var(--checkpoint);background:color-mix(in srgb,var(--checkpoint) 6%,var(--card))}
.card header{display:flex;flex-wrap:wrap;align-items:center;gap:8px;font-size:14px}.card time,.card .branch{color:var(--muted);font-size:12px}
.badge{font-size:11px;font-weight:600;padding:1px 8px;border-radius:999px;color:#fff;background:var(--none)}
.b-DONE{background:var(--done)}.b-IN_PROGRESS{background:var(--progress)}.b-BLOCKED{background:var(--blocked)}.b-INTERRUPTED{background:var(--interrupted)}.b-CHECKPOINT{background:var(--checkpoint)}
details summary{cursor:pointer;color:var(--muted);font-size:13px;margin-top:6px}code{background:var(--code);padding:1px 4px;border-radius:4px;font-size:.9em}
pre{background:var(--code);padding:10px;border-radius:6px;overflow-x:auto}pre code{padding:0;background:none}
table{border-collapse:collapse;display:block;overflow-x:auto}th,td{border:1px solid var(--line);padding:4px 8px;text-align:left}
li.nested{margin-left:1.5em}h3,h4,h5,h6{margin:12px 0 4px}.seg{border-top:1px dashed var(--line);margin-top:8px}.empty{color:var(--muted)}`;

const SCRIPT = `(function(){var q=document.getElementById('q'),s=document.getElementById('fs'),b=document.getElementById('fb');
function f(){var t=q.value.toLowerCase(),sv=s.value,bv=b.value;document.querySelectorAll('.card').forEach(function(c){
c.hidden=!((!sv||c.dataset.status===sv)&&(!bv||c.dataset.branch===bv)&&(!t||c.textContent.toLowerCase().indexOf(t)>=0));});}
[q,s,b].forEach(function(e){e.addEventListener('input',f);});})();`;

function render(data) {
  const d = data || {};
  const branches = [...new Set([...(d.rounds || []), ...(d.checkpoint_blocks || [])].map((x) => x.branch))].sort();
  const stat = (label, n) => `<span class="stat"><b>${Number(n) || 0}</b>${label}</span>`;
  const range = d.first_round_at ? `${escapeHtml(d.first_round_at)} → ${escapeHtml(d.last_round_at || '')}` : '沒有 Round';
  const items = timelineItems(d);
  const opt = (v, label) => `<option value="${escapeHtml(v)}">${escapeHtml(label)}</option>`;
  return `<!doctype html>
<html lang="zh-Hant"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1">
<title>Devlog Timeline</title><style>${CSS}</style></head><body><main>
<h1>Devlog Timeline</h1>
<div class="meta">branch ${escapeHtml(d.branch || '')} · ${range}</div>
<div class="stats">${stat('Rounds', d.rounds_total)}${stat('DONE', d.status_done)}${stat('IN_PROGRESS', d.status_in_progress)}${stat('BLOCKED', d.status_blocked)}${stat('INTERRUPTED', d.status_interrupted)}${stat('Checkpoints', d.checkpoints)}</div>
<div class="filters"><input id="q" type="search" placeholder="關鍵字篩選">
<select id="fs">${opt('', '全部 Status')}${[...STATUSES, 'CHECKPOINT'].map((s) => opt(s, s)).join('')}</select>
<select id="fb">${opt('', '全部 branch')}${branches.map((b) => opt(b, b)).join('')}</select></div>
${items.length ? items.join('\n') : '<p class="empty">沒有 Round 可顯示。</p>'}
</main><script>${SCRIPT}</script></body></html>
`;
}

if (require.main === module) {
  let input = '';
  process.stdin.setEncoding('utf8');
  process.stdin.on('data', (chunk) => {
    input += chunk;
  });
  process.stdin.on('end', () => {
    let data;
    try {
      data = JSON.parse(input);
    } catch (e) {
      process.stderr.write('INVALID_JSON\n');
      process.exitCode = 1;
      return;
    }
    process.stdout.write(render(data));
  });
}

module.exports = { render, renderMarkdown, inline, escapeHtml, safeHref, timelineItems };
