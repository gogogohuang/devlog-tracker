'use strict';
const path = require('path');
const { mergeHooksTemplate } = require('../merge-hooks');

function install({ repoRoot, targetDir, vendorRoot }) {
  mergeHooksTemplate({
    templatePath: path.join(repoRoot, 'cursor', 'hooks.json'),
    targetPath: path.join(targetDir, '.cursor', 'hooks.json'),
    vendorRoot,
  });
}

module.exports = { install };
