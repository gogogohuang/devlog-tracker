'use strict';
const fs = require('fs');
const path = require('path');
const { MARKER } = require('./merge-hooks');

const HOOK_FILES = [
  path.join('.claude', 'settings.local.json'),
  path.join('.claude', 'settings.json'),
  path.join('.codex', 'hooks.json'),
  path.join('.cursor', 'hooks.json'),
];

// 從 hook command 抽出 vendored 腳本路徑（`bash "<abs>/.devlog-tracker/…/x.sh"`）。
function vendoredScript(command) {
  if (typeof command !== 'string') return null;
  const m = command.match(/"([^"]*\.devlog-tracker\/[^"]+)"/);
  return m ? m[1] : null;
}

function isStale(entry) {
  const found = [];
  JSON.stringify(entry, (k, v) => {
    if (k === 'command') {
      const script = vendoredScript(v);
      if (script) found.push(script);
    }
    return v;
  });
  return found.some((script) => !fs.existsSync(script));
}

function readJson(file) {
  try {
    const parsed = JSON.parse(fs.readFileSync(file, 'utf8'));
    return parsed && typeof parsed === 'object' && parsed.hooks && typeof parsed.hooks === 'object' ? parsed : null;
  } catch {
    return null;
  }
}

// 回傳 [{ file, event, count }]：settings 裡指向已不存在的 vendored 腳本的 hook 項目。
function findStaleHooks(targetDir) {
  const out = [];
  for (const rel of HOOK_FILES) {
    const parsed = readJson(path.join(targetDir, rel));
    if (!parsed) continue;
    for (const [event, entries] of Object.entries(parsed.hooks)) {
      if (!Array.isArray(entries)) continue;
      const count = entries.filter((e) => JSON.stringify(e).includes(MARKER) && isStale(e)).length;
      if (count > 0) out.push({ file: rel, event, count });
    }
  }
  return out;
}

// 只移除孤兒 hook，不重新 vendor；回傳移除的項目數。
function pruneStaleHooks(targetDir) {
  let removed = 0;
  for (const rel of HOOK_FILES) {
    const file = path.join(targetDir, rel);
    const parsed = readJson(file);
    if (!parsed) continue;
    let changed = false;
    for (const [event, entries] of Object.entries(parsed.hooks)) {
      if (!Array.isArray(entries)) continue;
      const kept = entries.filter((e) => !(JSON.stringify(e).includes(MARKER) && isStale(e)));
      if (kept.length === entries.length) continue;
      removed += entries.length - kept.length;
      changed = true;
      if (kept.length > 0) parsed.hooks[event] = kept;
      else delete parsed.hooks[event];
    }
    if (changed) fs.writeFileSync(file, `${JSON.stringify(parsed, null, 2)}\n`);
  }
  return removed;
}

module.exports = { findStaleHooks, pruneStaleHooks };
