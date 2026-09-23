'use strict';
const fs = require('fs');
const path = require('path');
const { spawnSync } = require('child_process');

// npx 子命令（report／timeline）直接轉呼 core/scripts 的 bash 腳本：專案有
// vendored 版本就用它（與 hooks 同一份），否則用套件內附的版本。
function resolveScript({ targetDir, repoRoot, name }) {
  const vendored = path.join(targetDir, '.devlog-tracker', 'core', 'scripts', name);
  return fs.existsSync(vendored) ? vendored : path.join(repoRoot, 'core', 'scripts', name);
}

function runCoreScript({ targetDir, repoRoot, name, args }) {
  const script = resolveScript({ targetDir, repoRoot, name });
  const r = spawnSync('bash', [script, ...args], {
    cwd: targetDir,
    env: { ...process.env, DEVLOG_PROJECT_DIR: targetDir },
    encoding: 'utf8',
  });
  return { status: r.status === null ? 1 : r.status, stdout: r.stdout || '', stderr: r.stderr || '' };
}

module.exports = { resolveScript, runCoreScript };
