'use strict';
const test = require('node:test');
const assert = require('node:assert/strict');
const path = require('path');
const { spawnSync } = require('child_process');
const { render, renderMarkdown, safeHref, escapeHtml } = require('./timeline-render');

function round(extra) {
  return { branch: 'main', file: 'devlog.md', line: 1, n: 1, at: '2026-09-01T10:00:00+0800',
    status: 'DONE', summary: 's', reply: '', handoff: '', segments: [], ...extra };
}

test('escapeHtml escapes the five HTML metacharacters', () => {
  assert.equal(escapeHtml(`<a href="x">'&'</a>`), '&lt;a href=&quot;x&quot;&gt;&#39;&amp;&#39;&lt;/a&gt;');
});

test('safeHref allows http(s) and relative, rejects other schemes', () => {
  assert.equal(safeHref('https://example.com'), 'https://example.com');
  assert.equal(safeHref('docs/design/x.md'), 'docs/design/x.md');
  assert.equal(safeHref('javascript:alert(1)'), null);
  assert.equal(safeHref('JaVaScRiPt:alert(1)'), null);
  assert.equal(safeHref('data:text/html,x'), null);
  assert.equal(safeHref('//evil.example'), null);
});

test('renderMarkdown never emits raw HTML from content', () => {
  const html = renderMarkdown('<script>alert(1)</script>\n<img src=x onerror=alert(1)>');
  assert.ok(!html.includes('<script>'));
  assert.ok(!html.includes('<img'));
  assert.ok(html.includes('&lt;script&gt;'));
});

test('renderMarkdown neutralises javascript: links', () => {
  const html = renderMarkdown('[x](javascript:alert(1)) [ok](https://a.example)');
  assert.ok(!/href="javascript/i.test(html));
  assert.ok(html.includes('<a href="https://a.example">ok</a>'));
});

test('renderMarkdown subset: headings, lists, fences, inline code, bold, tables', () => {
  const html = renderMarkdown('#### 現況\n- a\n  - b\n1. one\n\n```\n<b>\n```\nuse `x<y` and **bold**\n\n| h | i |\n|---|---|\n| 1 | 2 |');
  assert.ok(html.includes('<h6>現況</h6>'));
  assert.ok(html.includes('<ul><li>a</li><li class="nested">b</li></ul>'));
  assert.ok(html.includes('<ol><li>one</li></ol>'));
  assert.ok(html.includes('<pre><code>&lt;b&gt;</code></pre>'));
  assert.ok(html.includes('<code>x&lt;y</code>'));
  assert.ok(html.includes('<strong>bold</strong>'));
  assert.ok(html.includes('<th>h</th>') && html.includes('<td>2</td>'));
});

test('a pipe line that is not a table does not hang', () => {
  assert.equal(renderMarkdown('| not a table'), '<p>| not a table</p>');
});

test('render: status badges, CJK, checkpoint after its preceding round', () => {
  const html = render({
    started: true, branch: 'main', rounds_total: 2, status_done: 1, status_blocked: 1,
    first_round_at: '2026-09-01T10:00:00+0800', last_round_at: '2026-09-02T10:00:00+0800',
    rounds: [
      round({ n: 2, line: 20, at: '2026-09-02T10:00:00+0800', status: 'BLOCKED', summary: '卡住了' }),
      round({ n: 1, line: 1, summary: '中文摘要', segments: ['段落 探索\nseg body'] }),
    ],
    checkpoint_blocks: [{ branch: 'main', file: 'devlog.md', line: 10, heading: 'Checkpoint（Round 1-1）', body: '### 決策\n- d' }],
  });
  assert.ok(html.startsWith('<!doctype html>'));
  assert.ok(html.includes('中文摘要') && html.includes('卡住了'));
  assert.ok(html.includes('data-status="BLOCKED"') && html.includes('b-DONE'));
  const r1 = html.indexOf('Round 1</strong>');
  const cp = html.indexOf('Checkpoint（Round 1-1）');
  const r2 = html.indexOf('Round 2</strong>');
  assert.ok(r1 < cp && cp < r2, 'order should be Round 1, Checkpoint, Round 2');
  assert.ok(html.includes('<h6>段落 探索</h6>'));
  assert.ok(!/<(script|link)[^>]+(src|href)=/i.test(html), 'no external resources');
});

test('render: unknown status renders as NONE; no input section by default', () => {
  const html = render({ rounds: [round({ status: '' })], checkpoint_blocks: [] });
  assert.ok(html.includes('data-status="NONE"'));
  assert.ok(!html.includes('User Input'));
  const withInput = render({ rounds: [round({ input: '<secret>' })], checkpoint_blocks: [] });
  assert.ok(withInput.includes('User Input') && withInput.includes('&lt;secret&gt;'));
});

test('render: empty data shows an empty-state message', () => {
  assert.ok(render({ started: true, rounds: [], checkpoint_blocks: [] }).includes('沒有 Round 可顯示'));
});

test('CLI: stdin JSON -> stdout HTML; invalid JSON -> exit 1', () => {
  const script = path.join(__dirname, 'timeline-render.js');
  const ok = spawnSync(process.execPath, [script], { input: JSON.stringify({ rounds: [round({})] }), encoding: 'utf8' });
  assert.equal(ok.status, 0);
  assert.ok(ok.stdout.includes('Round 1'));
  const bad = spawnSync(process.execPath, [script], { input: 'not json', encoding: 'utf8' });
  assert.equal(bad.status, 1);
  assert.equal(bad.stderr, 'INVALID_JSON\n');
});
