'use strict';
const path = require('path');
const { mergeHooksTemplate } = require('../merge-hooks');
const { upsertAgentsMd } = require('../agents-md');

function install({ repoRoot, targetDir, vendorRoot }) {
  mergeHooksTemplate({
    templatePath: path.join(repoRoot, 'codex', 'hooks.json'),
    targetPath: path.join(targetDir, '.codex', 'hooks.json'),
    vendorRoot,
  });
  upsertAgentsMd(targetDir);
}

module.exports = { install };
