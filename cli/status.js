'use strict';
const fs = require('fs');
const path = require('path');
const { findStaleHooks } = require('./stale-hooks');

function status({ targetDir, currentVersion }) {
  const staleHooks = findStaleHooks(targetDir);
  const versionFile = path.join(targetDir, '.devlog-tracker', 'VERSION');
  if (!fs.existsSync(versionFile)) {
    return { installed: false, vendoredVersion: null, upToDate: false, staleHooks };
  }
  const vendoredVersion = fs.readFileSync(versionFile, 'utf8').trim();
  return { installed: true, vendoredVersion, upToDate: vendoredVersion === currentVersion, staleHooks };
}

module.exports = { status };
