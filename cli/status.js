'use strict';
const fs = require('fs');
const path = require('path');

function status({ targetDir, currentVersion }) {
  const versionFile = path.join(targetDir, '.devlog-tracker', 'VERSION');
  if (!fs.existsSync(versionFile)) {
    return { installed: false, vendoredVersion: null, upToDate: false };
  }
  const vendoredVersion = fs.readFileSync(versionFile, 'utf8').trim();
  return { installed: true, vendoredVersion, upToDate: vendoredVersion === currentVersion };
}

module.exports = { status };
