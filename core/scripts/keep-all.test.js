'use strict';
const test = require('node:test');
const assert = require('node:assert/strict');
const fs = require('fs');
const os = require('os');
const path = require('path');
const { parseBlocks, scan, apply, formatScan } = require('./keep-all');

function round(n, ts, status, body = `round ${n} body`) {
  return `## Round ${n} — ${ts}\n\n### Summary\n${body}\n\n### Status\n${status}\n`;
}

function setup(files) {
  const dir = fs.mkdtempSync(path.join(os.tmpdir(), 'keep-all-'));
  const devlogDir = path.join(dir, '.devlog');
  fs.mkdirSync(devlogDir);
  for (const [name, text] of Object.entries(files)) fs.writeFileSync(path.join(devlogDir, name), text);
  return devlogDir;
}

function ctx(devlogDir, extra = {}) {
  return { devlogDir, projectDir: path.dirname(devlogDir), current: 'devlog.md', open: '', origin: '', ...extra };
}

const read = (d, f) => fs.readFileSync(path.join(d, f), 'utf8');
const exists = (d, f) => fs.existsSync(path.join(d, f));

function idsOf(result, file, rounds) {
  return result.rounds.filter(r => r.file === file && rounds.includes(r.round)).map(r => r.id);
}

test('parseBlocks is fence-aware and reads round number, timestamp and status', () => {
  const text = '# head\n\n' + round(1, '2026-09-01T10:00:00+0800', 'DONE',
    '```\n## Round 99 — fake\n```') + '\n## Checkpoint — x\n\ncp\n';
  const { blocks, firstBlock } = parseBlocks(text);
  assert.equal(firstBlock, 2);
  assert.equal(blocks.length, 2);
  assert.equal(blocks[0].round, 1);
  assert.equal(blocks[0].status, 'DONE');
  assert.equal(blocks[0].ts, '2026-09-01T10:00:00+0800');
  assert.equal(blocks[1].round, null);
});

test('scan classifies sources and marks what is movable', () => {
  const d = setup({
    'devlog.md': '# proj\n\n' + round(1, '2026-09-01T10:00:00+0800', 'DONE') + '\n' +
      round(2, '2026-09-01T11:00:00+0800', 'DONE') + '\n' + round(3, '2026-09-05T10:00:00+0800', 'IN_PROGRESS'),
    'devlog.feat-x.md': '<!-- devlog-origin: branch=feat/x -->\n\n' +
      round(1, '2026-09-02T10:00:00+0800', 'DONE') + '\n' + round(2, '2026-09-02T11:00:00+0800', 'IN_PROGRESS'),
    'devlog.legacy.md': round(1, '2026-09-03T10:00:00+0800', 'DONE'),
    'devlog.archive.md': round(1, '2026-08-01T10:00:00+0800', 'DONE'),
    'devlog.topic.md': '# Kept log\n\n- source: `.devlog/devlog.md`\n- rounds: 5-5\n- kept_at: x\n\n' +
      round(5, '2026-08-15T10:00:00+0800', 'DONE'),
    'devlog.lessons.git.md': '# lessons\n',
  });
  const r = scan(ctx(d, { open: '3' }));
  const kind = Object.fromEntries(r.sources.map(s => [s.file, s.kind]));
  assert.deepEqual(kind, {
    'devlog.archive.md': 'archive', 'devlog.feat-x.md': 'branch', 'devlog.legacy.md': 'branch',
    'devlog.md': 'current', 'devlog.topic.md': 'kept',
  });
  const fx = r.sources.find(s => s.file === 'devlog.feat-x.md');
  assert.equal(fx.origin, 'feat/x');
  assert.equal(fx.originFrom, 'marker');
  assert.equal(r.sources.find(s => s.file === 'devlog.legacy.md').originFrom, 'filename');
  // global ids ordered by timestamp
  assert.deepEqual(r.rounds.map(x => `${x.file}:${x.round}`), [
    'devlog.archive.md:1', 'devlog.topic.md:5', 'devlog.md:1', 'devlog.md:2',
    'devlog.feat-x.md:1', 'devlog.feat-x.md:2', 'devlog.legacy.md:1', 'devlog.md:3',
  ]);
  const mov = x => r.rounds.find(y => `${y.file}:${y.round}` === x).movable;
  assert.equal(mov('devlog.md:3'), false, 'open round');
  assert.equal(mov('devlog.feat-x.md:2'), false, 'branch unfinished tail');
  assert.equal(mov('devlog.feat-x.md:1'), true);
  assert.match(formatScan(r), /^FINGERPRINT=\S+ COUNT=8\n/);
});

test('scan reports NOTHING when no round is movable', () => {
  const d = setup({ 'devlog.md': round(1, '2026-09-01T10:00:00+0800', 'IN_PROGRESS') });
  const r = scan(ctx(d, { open: '1' }));
  assert.equal(formatScan(r), 'NOTHING\n');
});

function world() {
  return setup({
    'devlog.md': '# proj\n\n' + round(1, '2026-09-01T10:00:00+0800', 'DONE') +
      '\n## Checkpoint — Round 1-1\n\ncp one\n\n' + round(2, '2026-09-01T11:00:00+0800', 'DONE') +
      '\n## Kept 索引\n- `devlog.topic.md`：Round 5-5，kept_at x\n- `devlog.other.md`：Round 9-9，kept_at x\n',
    'devlog.feat-x.md': '<!-- devlog-origin: branch=feat/x -->\n\n' +
      round(1, '2026-09-02T10:00:00+0800', 'DONE') + '\n' + round(2, '2026-09-02T11:00:00+0800', 'IN_PROGRESS'),
    'devlog.archive.md': round(1, '2026-08-01T10:00:00+0800', 'DONE'),
    'devlog.topic.md': '# Kept log\n\n- source: `.devlog/devlog.md`\n- rounds: 5-5\n- kept_at: x\n\nold summary\n\n' +
      round(5, '2026-08-15T10:00:00+0800', 'DONE'),
    'devlog.other.md': '# Kept log\n\n- rounds: 9-9\n\n' + round(9, '2026-08-20T10:00:00+0800', 'DONE'),
  });
}

test('apply moves a cross-file topic into one file in time order and consumes kept files', () => {
  const d = world();
  const c = ctx(d);
  const s = scan(c);
  const a = [...idsOf(s, 'devlog.archive.md', [1]), ...idsOf(s, 'devlog.topic.md', [5]), ...idsOf(s, 'devlog.feat-x.md', [1])];
  const b = [...idsOf(s, 'devlog.other.md', [9]), ...idsOf(s, 'devlog.md', [1])];
  const plan = `alpha\tfirst topic\t${a.join(',')}\nbeta\t\t${b.join(',')}\n`;
  const out = apply(c, plan, s.fingerprint, s.rounds.length);

  const alpha = read(d, 'devlog.alpha.md');
  assert.match(alpha, /^# Kept log\n\n- source: keep-all\n/);
  assert.match(alpha, /- rounds: devlog\.archive\.md 1\n/);
  assert.match(alpha, /old summary/, 'kept file summary travels with its first round');
  const order = [...alpha.matchAll(/^## Round (\d+) — (\S+)/gm)].map(m => m[2]);
  assert.deepEqual(order, ['2026-08-01T10:00:00+0800', '2026-08-15T10:00:00+0800', '2026-09-02T10:00:00+0800']);

  const beta = read(d, 'devlog.beta.md');
  assert.match(beta, /## Round 1 — 2026-09-01T10:00:00\+0800[\s\S]*## Checkpoint — Round 1-1/, 'checkpoint follows its round');

  assert.ok(!exists(d, 'devlog.topic.md') && !exists(d, 'devlog.other.md'), 'kept sources deleted');
  assert.ok(!exists(d, 'devlog.archive.md'), 'empty archive deleted');
  const main = read(d, 'devlog.md');
  assert.match(main, /^# proj\n/);
  assert.ok(!/Round 1 —/.test(main) && /Round 2 —/.test(main));
  assert.ok(!/Checkpoint/.test(main));
  assert.ok(!/devlog\.topic\.md|devlog\.other\.md/.test(main), 'ghost index lines removed');
  assert.match(main, /- `devlog\.alpha\.md`：keep-all，3 輪，kept_at \S+，first topic\n/);
  assert.match(main, /- `devlog\.beta\.md`：keep-all，2 輪，kept_at \S+\n/);

  const fx = read(d, 'devlog.feat-x.md');
  assert.match(fx, /^<!-- devlog-origin: branch=feat\/x -->\n/);
  assert.ok(!/Round 1 —/.test(fx) && /Round 2 —/.test(fx));

  assert.match(out, /^KEPT=.*devlog\.alpha\.md ROUNDS=3$/m);
  assert.match(out, /^DELETED=.*devlog\.topic\.md$/m);
  const backup = out.match(/^BACKUP=(.*)$/m)[1];
  assert.ok(fs.existsSync(path.join(backup, 'devlog.topic.md')));
  assert.ok(fs.existsSync(path.join(backup, 'devlog.md')));
});

test('apply deletes a branch file it emptied, but not an active branch or devlog.md', () => {
  const d = setup({
    'devlog.feat-main.md': '<!-- devlog-origin: branch=feat/main -->\n\n' + round(1, '2026-09-05T10:00:00+0800', 'IN_PROGRESS'),
    'devlog.md': '# proj\n\n' + round(1, '2026-09-01T10:00:00+0800', 'DONE'),
    'devlog.old.md': '<!-- devlog-origin: branch=old -->\n\n' + round(1, '2026-09-02T10:00:00+0800', 'DONE'),
    'devlog.keep-me.md': '<!-- devlog-origin: branch=keep-me -->\n\n' + round(1, '2026-09-03T10:00:00+0800', 'DONE') +
      '\n' + round(2, '2026-09-03T11:00:00+0800', 'DONE'),
  });
  const c = ctx(d, { current: 'devlog.feat-main.md', open: '1' });
  const s = scan(c);
  const ids = [...idsOf(s, 'devlog.md', [1]), ...idsOf(s, 'devlog.old.md', [1]), ...idsOf(s, 'devlog.keep-me.md', [1])];
  const out = apply(c, `alpha\t\t${ids.join(',')}\n`, s.fingerprint, s.rounds.length);
  assert.ok(!exists(d, 'devlog.old.md'), 'emptied branch file deleted');
  assert.match(out, /^DELETED=.*devlog\.old\.md$/m);
  assert.ok(exists(d, 'devlog.keep-me.md'), 'branch file with rounds left stays');
  assert.ok(exists(d, 'devlog.md'), 'devlog.md is never deleted');
  const backup = out.match(/^BACKUP=(.*)$/m)[1];
  assert.ok(fs.existsSync(path.join(backup, 'devlog.old.md')), 'deleted branch file is backed up');
});

test('apply may reuse the name of a kept file it consumes', () => {
  const d = world();
  const c = ctx(d);
  const s = scan(c);
  const all = [...idsOf(s, 'devlog.topic.md', [5]), ...idsOf(s, 'devlog.other.md', [9])];
  apply(c, `topic\t\t${all.join(',')}\n`, s.fingerprint, s.rounds.length);
  assert.match(read(d, 'devlog.topic.md'), /- source: keep-all/);
  assert.match(read(d, 'devlog.md'), /- `devlog\.topic\.md`：keep-all，2 輪/);
});

function snapshot(d) {
  return Object.fromEntries(fs.readdirSync(d).map(f => [f, fs.readFileSync(path.join(d, f), 'utf8')]));
}

for (const [label, planFor, pattern] of [
  ['uncovered kept round', s => `a\t\t${idsOf(s, 'devlog.topic.md', [5])}\n`, /devlog\.other\.md/],
  ['id in two segments', s => {
    const k = [...idsOf(s, 'devlog.topic.md', [5]), ...idsOf(s, 'devlog.other.md', [9])].join(',');
    return `a\t\t${k}\nb\t\t${idsOf(s, 'devlog.topic.md', [5])}\n`;
  }, /重複/],
  ['unmovable round', s => {
    const k = [...idsOf(s, 'devlog.topic.md', [5]), ...idsOf(s, 'devlog.other.md', [9])].join(',');
    return `a\t\t${k},${idsOf(s, 'devlog.feat-x.md', [2])}\n`;
  }, /不可搬/],
  ['collision with an existing branch file', s => {
    const k = [...idsOf(s, 'devlog.topic.md', [5]), ...idsOf(s, 'devlog.other.md', [9])].join(',');
    return `feat-x\t\t${k}\n`;
  }, /已存在/],
  ['reserved name', s => {
    const k = [...idsOf(s, 'devlog.topic.md', [5]), ...idsOf(s, 'devlog.other.md', [9])].join(',');
    return `archive\t\t${k}\n`;
  }, /檔名無效/],
]) {
  test(`apply rejects ${label} and writes nothing`, () => {
    const d = world();
    const c = ctx(d);
    const s = scan(c);
    const before = snapshot(d);
    assert.throws(() => apply(c, planFor(s), s.fingerprint, s.rounds.length), pattern);
    assert.deepEqual(snapshot(d), before);
  });
}

test('apply refuses when a scanned round changed, but tolerates a newly appended round', () => {
  const d = world();
  const c = ctx(d);
  const s = scan(c);
  const k = [...idsOf(s, 'devlog.topic.md', [5]), ...idsOf(s, 'devlog.other.md', [9])].join(',');
  fs.appendFileSync(path.join(d, 'devlog.md'), '\n' + round(3, '2026-09-10T10:00:00+0800', 'DONE'));
  const d2 = world();
  const c2 = ctx(d2);
  const s2 = scan(c2);
  fs.writeFileSync(path.join(d2, 'devlog.archive.md'), round(1, '2026-08-01T10:00:00+0800', 'DONE', 'edited'));
  const before = snapshot(d2);
  assert.throws(() => apply(c2, `a\t\t${k}\n`, s2.fingerprint, s2.rounds.length), /fingerprint/);
  assert.deepEqual(snapshot(d2), before);
  apply(c, `a\t\t${k}\n`, s.fingerprint, s.rounds.length);
  assert.match(read(d, 'devlog.md'), /Round 3 —/);
});

test('apply clears .span-open only when its round moved out of current', () => {
  const d = world();
  fs.writeFileSync(path.join(d, '.span-open'), '{"round": 1, "ticks": 0}\n');
  const c = ctx(d);
  const s = scan(c);
  const k = [...idsOf(s, 'devlog.topic.md', [5]), ...idsOf(s, 'devlog.other.md', [9]), ...idsOf(s, 'devlog.md', [2])].join(',');
  apply(c, `a\t\t${k}\n`, s.fingerprint, s.rounds.length);
  assert.ok(exists(d, '.span-open'));
  const s2 = scan(c);
  const k2 = [...s2.rounds.filter(r => r.file === 'devlog.a.md').map(r => r.id), ...idsOf(s2, 'devlog.md', [1])];
  apply(c, `b\t\t${k2.join(',')}\n`, s2.fingerprint, s2.rounds.length);
  assert.ok(!exists(d, '.span-open'));
});
