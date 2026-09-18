'use strict';
const fs = require('fs');
const path = require('path');

const MARKER = '.devlog-tracker/';

function mergeHooksTemplate({ templatePath, targetPath, vendorRoot }) {
  const rawTemplate = fs.readFileSync(templatePath, 'utf8').split('${DEVLOG_TRACKER_ROOT}').join(vendorRoot);
  const template = JSON.parse(rawTemplate);

  let existing = { hooks: {} };
  if (fs.existsSync(targetPath)) {
    existing = JSON.parse(fs.readFileSync(targetPath, 'utf8'));
  }
  if (!existing.hooks) existing.hooks = {};

  for (const key of Object.keys(template)) {
    if (key === 'hooks') continue;
    if (!(key in existing)) existing[key] = template[key];
  }

  for (const event of Object.keys(template.hooks)) {
    const templateEntries = template.hooks[event];
    const currentEntries = existing.hooks[event] || [];
    const kept = currentEntries.filter((entry) => !JSON.stringify(entry).includes(MARKER));
    existing.hooks[event] = kept.concat(templateEntries);
  }

  fs.mkdirSync(path.dirname(targetPath), { recursive: true });
  fs.writeFileSync(targetPath, `${JSON.stringify(existing, null, 2)}\n`);
}

module.exports = { mergeHooksTemplate, MARKER };
