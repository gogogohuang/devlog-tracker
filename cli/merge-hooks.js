'use strict';
const fs = require('fs');
const path = require('path');

const MARKER = '.devlog-tracker/';

function isPlainObject(v) {
  return v !== null && typeof v === 'object' && !Array.isArray(v);
}

function readExisting(targetPath) {
  if (!fs.existsSync(targetPath)) return {};
  const text = fs.readFileSync(targetPath, 'utf8');
  if (text.trim() === '') return {};
  let parsed;
  try {
    parsed = JSON.parse(text);
  } catch (err) {
    throw new Error(
      `Cannot parse existing ${targetPath}: ${err.message}. Fix or move the file, then re-run \`devlog-tracker init\` (safe to re-run).`
    );
  }
  if (parsed === null) return {};
  if (!isPlainObject(parsed)) {
    throw new Error(`Existing ${targetPath} must contain a JSON object at the top level; fix or move the file, then re-run \`devlog-tracker init\` (safe to re-run).`);
  }
  if ('hooks' in parsed && parsed.hooks !== null && !isPlainObject(parsed.hooks)) {
    throw new Error(`Existing ${targetPath}: "hooks" must be a JSON object; fix or move the file, then re-run \`devlog-tracker init\` (safe to re-run).`);
  }
  return parsed;
}

function mergeHooksTemplate({ templatePath, targetPath, vendorRoot, placeholders = ['${DEVLOG_TRACKER_ROOT}'] }) {
  const escapedRoot = JSON.stringify(vendorRoot).slice(1, -1);
  let rawTemplate = fs.readFileSync(templatePath, 'utf8');
  for (const placeholder of placeholders) {
    rawTemplate = rawTemplate.split(placeholder).join(escapedRoot);
  }
  const template = JSON.parse(rawTemplate);

  const existing = readExisting(targetPath);
  if (!existing.hooks) existing.hooks = {};

  for (const key of Object.keys(template)) {
    if (key === 'hooks') continue;
    if (!(key in existing)) existing[key] = template[key];
  }

  for (const event of Object.keys(template.hooks)) {
    const templateEntries = template.hooks[event];
    const currentEntries = existing.hooks[event] === undefined || existing.hooks[event] === null ? [] : existing.hooks[event];
    if (!Array.isArray(currentEntries)) {
      throw new Error(`Existing ${targetPath}: hooks.${event} must be an array; fix or move the file, then re-run \`devlog-tracker init\` (safe to re-run).`);
    }
    const kept = currentEntries.filter((entry) => !JSON.stringify(entry).includes(MARKER));
    existing.hooks[event] = kept.concat(templateEntries);
  }

  fs.mkdirSync(path.dirname(targetPath), { recursive: true });
  fs.writeFileSync(targetPath, `${JSON.stringify(existing, null, 2)}\n`);
}

module.exports = { mergeHooksTemplate, MARKER };
