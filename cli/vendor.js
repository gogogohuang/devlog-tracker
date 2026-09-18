'use strict';
const fs = require('fs');
const path = require('path');

const VENDOR_ENTRIES = ['hooks/scripts', 'codex/hooks', 'cursor/hooks', 'skills', 'commands'];

function copyRecursive(src, dest) {
  const stat = fs.statSync(src);
  if (stat.isDirectory()) {
    fs.mkdirSync(dest, { recursive: true });
    for (const entry of fs.readdirSync(src)) {
      copyRecursive(path.join(src, entry), path.join(dest, entry));
    }
    return;
  }
  fs.mkdirSync(path.dirname(dest), { recursive: true });
  fs.copyFileSync(src, dest);
}

function envShContent(vendorRoot) {
  const escaped = vendorRoot.replace(/[\\"$`]/g, '\\$&');
  return `export DEVLOG_TRACKER_ROOT="${escaped}"\n`;
}

function vendor({ repoRoot, targetDir, version }) {
  const vendorRoot = path.join(targetDir, '.devlog-tracker');
  for (const entry of VENDOR_ENTRIES) {
    const src = path.join(repoRoot, entry);
    if (!fs.existsSync(src)) continue;
    copyRecursive(src, path.join(vendorRoot, entry));
  }
  fs.writeFileSync(path.join(vendorRoot, 'VERSION'), `${version}\n`);
  fs.writeFileSync(path.join(vendorRoot, 'env.sh'), envShContent(vendorRoot));
  return vendorRoot;
}

module.exports = { vendor, VENDOR_ENTRIES };
