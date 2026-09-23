# HTML 時間軸 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 新增 `timeline-devlog.sh` + `timeline-render.js`，把 devlog 渲染成一份離線可開、自足的 `.devlog/timeline.html`；外加 `/devlog-tracker:timeline` 與 `npx devlog-tracker timeline`。

**Architecture:** `timeline-devlog.sh` 呼叫 `report-devlog.sh --json --rounds`（`report-plan.md` 已完成），把 JSON pipe 給零相依的 Node renderer `timeline-render.js`。renderer 放在 `core/scripts/`，因為 `init` 只 vendoring `core/scripts/`，plugin 與 vendored 使用者都叫得到。

**Tech Stack:** bash（macOS 3.2 相容）、Node ≥18（無 npm 相依）、`node:test`。

**Spec:** [`read-side-and-promote.md`](read-side-and-promote.md) §C

**前置：** `report-plan.md` 全部完成（依賴 `report-devlog.sh --json --rounds`、`cli/core-script.js`、`bin` 的 `CORE_COMMANDS`、`test-round-start.sh` 的 `19b` 區塊）。

## Global Constraints

- 一般 PR 不改版號。
- 零 runtime 相依：renderer 只用 Node 內建，HTML 不引用任何外部資源（CDN、字型、圖片）。
- 安全：所有來自 devlog 的文字先 HTML 跳脫再做 Markdown 轉換；連結只允許 `http:`／`https:`／相對路徑；不輸出任何來自 devlog 的原始 HTML。
- 預設不含 `User Input`（renderer 只在 JSON 有 `input` 欄位時顯示；`timeline-devlog.sh` 不傳 `--with-input`）。
- 深色模式：`:root` token + `prefers-color-scheme: dark`；窄螢幕可讀（16px 側邊留白、表格與 code 區塊自己橫向捲動）。
- 驗證三步：shellcheck（同 AGENTS.md）、`bash core/scripts/run-tests.sh`、`npm test`。
- Commit 訊息結尾加 `Co-Authored-By: Claude Opus 5.5 (1M context) <noreply@anthropic.com>`。

## File Structure

| 檔案 | 動作 | 責任 |
|---|---|---|
| `core/scripts/timeline-render.js` | Create | JSON → HTML（Markdown 子集、卡片、篩選） |
| `core/scripts/timeline-render.test.js` | Create | renderer 單元測試 |
| `package.json` | Modify | `test` glob 加 `core/scripts/*.test.js` |
| `core/scripts/timeline-devlog.sh` | Create | 檢查 node、串 report → render、寫檔 |
| `core/scripts/tests/test-timeline.sh` | Create | 端對端、`NO_NODE`、`NOT_STARTED` |
| `bin/devlog-tracker.js` | Modify | `CORE_COMMANDS` 加 `timeline` |
| `cli/core-script.test.js` | Modify | bin timeline 測試 |
| `commands/timeline.md` | Create | 指令文件 |
| `core/scripts/round-start.sh`、`core/scripts/tests/test-round-start.sh` | Modify | admin 清單 |
| `cli/agents-md.js`、`cli/platforms/claude.js`、`skills/devlog-tracker/SKILL.md`、`README.md`、`README.zh-TW.md` | Modify | 文件與對照表 |

---

### Task 1: `timeline-render.js`

**Files:**
- Create: `core/scripts/timeline-render.js`
- Create: `core/scripts/timeline-render.test.js`
- Modify: `package.json`（`scripts.test`）

**Interfaces:**
- Consumes: `report-devlog.sh --json --rounds` 的 JSON（`report-plan.md`「記錄格式」）。
- Produces: `module.exports = { render, renderMarkdown, inline, escapeHtml, safeHref, timelineItems }`；直接執行時 stdin JSON → stdout HTML，JSON 無效時 stderr `INVALID_JSON`、exit 1。

- [ ] **Step 1: 寫失敗測試**

Create `core/scripts/timeline-render.test.js`：

```js
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
```

`package.json` 的 `"test"` 改成：

```json
    "test": "node --test cli/*.test.js cli/platforms/*.test.js scripts/*.test.js core/scripts/*.test.js",
```

（原本是 `node --test cli/*.test.js scripts/*.test.js`，不會遞迴，所以 `cli/platforms/claude.test.js` 目前沒被 CI 跑到；它現在 6 個測試全過，順手加進 glob，commit 訊息註明。）

- [ ] **Step 2: 跑測試確認失敗**

Run: `node --test core/scripts/timeline-render.test.js`
Expected: FAIL（`Cannot find module './timeline-render'`）

- [ ] **Step 3: 實作 `core/scripts/timeline-render.js`**

```js
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
      const ordered = /\d/.test(LIST_ITEM.exec(line)[2]);
      const items = [];
      while (i < lines.length) {
        const m = LIST_ITEM.exec(lines[i]);
        if (m) {
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
```

`chmod +x core/scripts/timeline-render.js`

- [ ] **Step 4: 跑測試確認通過**

Run: `node --test core/scripts/timeline-render.test.js && npm test`
Expected: 全部 pass

- [ ] **Step 5: Commit**

```bash
git add core/scripts/timeline-render.js core/scripts/timeline-render.test.js package.json
git commit -m "feat: add zero-dependency devlog timeline HTML renderer

Co-Authored-By: Claude Opus 5.5 (1M context) <noreply@anthropic.com>"
```

---

### Task 2: `timeline-devlog.sh`

**Files:**
- Create: `core/scripts/timeline-devlog.sh`
- Test: `core/scripts/tests/test-timeline.sh`

**Interfaces:**
- Consumes: `report-devlog.sh --json --rounds [--all-branches]`、`timeline-render.js`。
- Produces: stdout 一行 `NO_NODE`／`NOT_STARTED`／`OUT=<絕對路徑>`；exit 0（未知參數 exit 2，report 或 render 失敗 exit 1）。

- [ ] **Step 1: 寫失敗測試**

Create `core/scripts/tests/test-timeline.sh`：

```bash
#!/usr/bin/env bash
# Self-check for timeline-devlog.sh (docs/design/read-side-and-promote.md C).
set -uo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TMP_ROOT="$(mktemp -d)"
trap 'rm -rf "$TMP_ROOT"' EXIT
export CLAUDE_PROJECT_DIR="$TMP_ROOT"
DEVLOG_DIR="$TMP_ROOT/.devlog"
FAIL=0
pass() { echo "PASS: $1"; }
fail() { echo "FAIL: $1"; FAIL=1; }

# --- NO_NODE: node missing from PATH (checked before anything else) ----------
EMPTY_BIN="$TMP_ROOT/empty-bin"
mkdir -p "$EMPTY_BIN"
BASH_BIN="$(command -v bash)"
OUT="$(PATH="$EMPTY_BIN" "$BASH_BIN" "$SCRIPT_DIR/timeline-devlog.sh" 2>&1)"
[ "$OUT" = "NO_NODE" ] && pass "no node -> NO_NODE" || fail "no node -> NO_NODE (got $OUT)"

if ! command -v node >/dev/null 2>&1; then
  echo "SKIP: remaining timeline checks need node"
  if [ "$FAIL" -eq 0 ]; then echo "All checks passed."; exit 0; else echo "Some checks FAILED."; exit 1; fi
fi

# --- NOT_STARTED --------------------------------------------------------------
OUT="$(bash "$SCRIPT_DIR/timeline-devlog.sh")"
[ "$OUT" = "NOT_STARTED" ] && pass "no .devlog -> NOT_STARTED" || fail "NOT_STARTED (got $OUT)"
[ ! -e "$DEVLOG_DIR" ] && pass "NOT_STARTED creates nothing" || fail "NOT_STARTED created .devlog"

# --- End to end -----------------------------------------------------------------
mkdir -p "$DEVLOG_DIR"
cat > "$DEVLOG_DIR/devlog.md" <<'EOF2'
## Round 1 — 2026-09-01T10:00:00+0800

### User Input
secret-input-text

### Summary
<script>alert(1)</script> 中文摘要

### Status
DONE
EOF2
OUT="$(bash "$SCRIPT_DIR/timeline-devlog.sh")"
case "$OUT" in
  "OUT=$(cd "$DEVLOG_DIR" && pwd)/timeline.html") pass "default OUT path is absolute .devlog/timeline.html" ;;
  *) fail "default OUT (got $OUT)" ;;
esac
HTML="$DEVLOG_DIR/timeline.html"
grep -q '中文摘要' "$HTML" && pass "summary rendered" || fail "summary missing"
grep -q '<script>alert' "$HTML" && fail "raw script tag leaked" || pass "script tag escaped"
grep -q 'secret-input-text' "$HTML" && fail "User Input leaked" || pass "User Input not included"
[ ! -e "$HTML.tmp" ] && pass "no leftover tmp file" || fail "leftover $HTML.tmp"

# --- --out ------------------------------------------------------------------------
OUT="$(bash "$SCRIPT_DIR/timeline-devlog.sh" --out "$TMP_ROOT/custom.html")"
[ -s "$TMP_ROOT/custom.html" ] && pass "--out writes the given path" || fail "--out ($OUT)"

# --- unknown arg ------------------------------------------------------------------
bash "$SCRIPT_DIR/timeline-devlog.sh" --bogus >/dev/null 2>&1
RC=$?
[ "$RC" -eq 2 ] && pass "unknown arg exits 2" || fail "unknown arg exit $RC"

if [ "$FAIL" -eq 0 ]; then echo "All checks passed."; exit 0
else echo "Some checks FAILED."; exit 1; fi
```

- [ ] **Step 2: 跑測試確認失敗**

Run: `bash core/scripts/tests/test-timeline.sh`
Expected: `FAIL: no node -> NO_NODE`（腳本不存在）等

- [ ] **Step 3: 實作 `core/scripts/timeline-devlog.sh`**

```bash
#!/usr/bin/env bash
# /devlog-tracker:timeline and `npx devlog-tracker timeline`
# (docs/design/read-side-and-promote.md C): report-devlog.sh --json --rounds
# piped into timeline-render.js, written to .devlog/timeline.html (gitignored).
set -uo pipefail

_src="${BASH_SOURCE[0]}"
SCRIPT_DIR="$(cd "${_src%/*}" && pwd)"

# Checked before sourcing anything: Claude plugin users may not have Node.
command -v node >/dev/null 2>&1 || { echo "NO_NODE"; exit 0; }

# shellcheck source=devlog-path.sh
. "$SCRIPT_DIR/devlog-path.sh"

ALL=0
OUT=""
while [ $# -gt 0 ]; do
  case "$1" in
    --all-branches) ALL=1 ;;
    --out) shift; OUT="${1:-}" ;;
    *) echo "UNKNOWN_ARG=$1" >&2; exit 2 ;;
  esac
  shift
done

devlog_resolve_paths "${DEVLOG_PROJECT_DIR:-${CLAUDE_PROJECT_DIR:-.}}"
[ -d "$DEVLOG_DIR" ] || { echo "NOT_STARTED"; exit 0; }
[ -n "$OUT" ] || OUT="$DEVLOG_DIR/timeline.html"

ARGS=(--json --rounds)
[ "$ALL" -eq 1 ] && ARGS+=(--all-branches)

JSON_TMP="$(mktemp "${TMPDIR:-/tmp}/devlog-timeline.XXXXXX")" || exit 1
trap 'rm -f "$JSON_TMP" "$OUT.tmp"' EXIT
bash "$SCRIPT_DIR/report-devlog.sh" "${ARGS[@]}" > "$JSON_TMP" || exit 1
node "$SCRIPT_DIR/timeline-render.js" < "$JSON_TMP" > "$OUT.tmp" || exit 1
mv "$OUT.tmp" "$OUT" || exit 1

OUT_DIR="$(cd "$(dirname "$OUT")" && pwd)"
echo "OUT=$OUT_DIR/$(basename "$OUT")"
```

`chmod +x core/scripts/timeline-devlog.sh`

- [ ] **Step 4: 跑測試確認通過**

Run: `bash core/scripts/tests/test-timeline.sh && shellcheck --external-sources --source-path=SCRIPTDIR -S warning core/scripts/timeline-devlog.sh core/scripts/tests/test-timeline.sh`
Expected: `All checks passed.`，shellcheck 無輸出

- [ ] **Step 5: Commit**

```bash
git add core/scripts/timeline-devlog.sh core/scripts/tests/test-timeline.sh
git commit -m "feat: add timeline-devlog.sh writing .devlog/timeline.html

Co-Authored-By: Claude Opus 5.5 (1M context) <noreply@anthropic.com>"
```

---

### Task 3: `npx devlog-tracker timeline`

**Files:**
- Modify: `bin/devlog-tracker.js`（`CORE_COMMANDS` 與 usage）
- Test: `cli/core-script.test.js`

**Interfaces:**
- Consumes: `CORE_COMMANDS`、`runCoreScript`（`report-plan.md` Task 5）。

- [ ] **Step 1: 寫失敗測試**

在 `cli/core-script.test.js` 檔尾加：

```js
test('bin timeline runs the real packaged timeline-devlog.sh', () => {
  const cwd = tmp();
  const bin = path.join(__dirname, '..', 'bin', 'devlog-tracker.js');
  const r = spawnSync(process.execPath, [bin, 'timeline'], { cwd, encoding: 'utf8' });
  assert.equal(r.status, 0);
  assert.equal(r.stdout, 'NOT_STARTED\n');
});
```

Run: `node --test cli/core-script.test.js`
Expected: 新測試 FAIL（`Unknown command: timeline`，exit 1）

- [ ] **Step 2: 實作**

`bin/devlog-tracker.js`：

```js
  const CORE_COMMANDS = { report: 'report-devlog.sh', timeline: 'timeline-devlog.sh' };
```

usage 改成：

```js
    console.log('Usage: devlog-tracker <init|status|report|timeline> [--codex] [--cursor] [--json] [--all-branches] [--out <path>]');
```

- [ ] **Step 3: 跑測試確認通過**

Run: `npm test`
Expected: 全部 pass

- [ ] **Step 4: Commit**

```bash
git add bin/devlog-tracker.js cli/core-script.test.js
git commit -m "feat: npx devlog-tracker timeline

Co-Authored-By: Claude Opus 5.5 (1M context) <noreply@anthropic.com>"
```

---

### Task 4: `/devlog-tracker:timeline` 指令與文件

**Files:**
- Create: `commands/timeline.md`
- Modify: `core/scripts/round-start.sh`、`core/scripts/tests/test-round-start.sh`
- Modify: `cli/agents-md.js`、`cli/platforms/claude.js`、`skills/devlog-tracker/SKILL.md`、`README.md`、`README.zh-TW.md`

- [ ] **Step 1: 寫失敗測試**

`core/scripts/tests/test-round-start.sh` 的 `19b` 區塊，把 `for ADMIN_CMD in report; do` 改成：

```bash
for ADMIN_CMD in report timeline; do
```

Run: `bash core/scripts/tests/test-round-start.sh 2>&1 | grep 'admin timeline'`
Expected: `FAIL`

- [ ] **Step 2: 建立 `commands/timeline.md`**

````markdown
---
description: 把 devlog 產生成一份離線可開的 HTML 時間軸（.devlog/timeline.html），可依 Status／branch／關鍵字篩選。
---

先決定 plugin 根目錄（有 `DEVLOG_TRACKER_ROOT` 用它；否則用 `CLAUDE_PLUGIN_ROOT`；兩者都空就用含 `.claude-plugin/plugin.json` 的本 plugin 根目錄），再跑：

```bash
PLUGIN_ROOT="${DEVLOG_TRACKER_ROOT:-${CLAUDE_PLUGIN_ROOT:-}}"
DEVLOG_PROJECT_DIR="$(pwd)" bash "${PLUGIN_ROOT}/core/scripts/timeline-devlog.sh"
```

使用者要看所有 branch 時加 `--all-branches`；要寫到別的位置時加 `--out <路徑>`。

- `NO_NODE`：告知這個功能需要 Node.js（≥18），裝好後再跑；結束。
- `NOT_STARTED`：告知還沒 `/devlog-tracker:start`，結束。
- `OUT=<路徑>`：告知檔案位置，並提示可以直接用瀏覽器開（macOS：`open <路徑>`）。不要自己打開瀏覽器，也不要把 HTML 內容貼進對話。

時間軸不含 User Input 原文。`.devlog/timeline.html` 在 `.devlog/` 底下，每次重跑會覆寫，不需要 commit。
````

- [ ] **Step 3: admin 清單與文件**

`core/scripts/round-start.sh` admin `case` 行，在 `devlog-tracker:status` 之後加 `|devlog-tracker:timeline`：

```bash
  …|devlog-tracker:start|devlog-tracker:status|devlog-tracker:timeline)
```

`skills/devlog-tracker/SKILL.md` admin 清單在 `` `status` `` 之後加 `` 、`timeline` ``。

`cli/agents-md.js` 的 `codexBlock()` 與 `cli/platforms/claude.js` 的 `claudeBlock()`：把 Task 6（report-plan）加的那列改成：

```
| 統計 / report、HTML 時間軸 / timeline | \`commands/report.md\`、\`commands/timeline.md\` |
```

`README.md` 指令表在 `/devlog-tracker:report` 那列之後加：

```
| `/devlog-tracker:timeline` | Renders the devlog into a self-contained, offline HTML timeline at `.devlog/timeline.html` (round cards coloured by Status, Checkpoints interleaved, Status/branch/keyword filters, dark mode). No User Input text. Needs Node ≥18; `--all-branches` includes every branch file. Also `npx devlog-tracker timeline`. |
```

`README.zh-TW.md` 同位置：

```
| `/devlog-tracker:timeline` | 把 devlog 產生成離線可開的自足 HTML 時間軸 `.devlog/timeline.html`（Round 卡片依 Status 上色、穿插 Checkpoint、可依 Status／branch／關鍵字篩選、支援深色模式）。不含 User Input 原文。需要 Node ≥18；`--all-branches` 納入所有 branch 檔。也可用 `npx devlog-tracker timeline`。 |
```

- [ ] **Step 4: 全部驗證**

Run:
```bash
shellcheck --external-sources --source-path=SCRIPTDIR -S warning \
  core/scripts/*.sh core/scripts/tests/*.sh cursor/hooks/*.sh codex/hooks/*.sh
bash core/scripts/run-tests.sh
npm test
```
Expected: 全過

- [ ] **Step 5: 手動看一眼**

Run: `DEVLOG_PROJECT_DIR="$(pwd)" bash core/scripts/timeline-devlog.sh && open .devlog/timeline.html`
Expected: 瀏覽器顯示本 repo 的 devlog 時間軸；切換系統深色模式顏色會變；篩選可用。（`.devlog/` 是 gitignored，不 commit。）

- [ ] **Step 6: Commit**

```bash
git add commands/timeline.md core/scripts/round-start.sh core/scripts/tests/test-round-start.sh \
  cli/agents-md.js cli/platforms/claude.js skills/devlog-tracker/SKILL.md README.md README.zh-TW.md
git commit -m "feat: /devlog-tracker:timeline command

Co-Authored-By: Claude Opus 5.5 (1M context) <noreply@anthropic.com>"
```
