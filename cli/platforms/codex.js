'use strict';
const path = require('path');
const { mergeHooksTemplate } = require('../merge-hooks');

function install({ repoRoot, targetDir, vendorRoot }) {
  mergeHooksTemplate({
    templatePath: path.join(repoRoot, 'codex', 'hooks.json'),
    targetPath: path.join(targetDir, '.codex', 'hooks.json'),
    vendorRoot,
  });
}

module.exports = { install };
