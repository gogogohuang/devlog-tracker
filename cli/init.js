'use strict';
const readline = require('readline');
const { vendor } = require('./vendor');
const codex = require('./platforms/codex');
const cursor = require('./platforms/cursor');

const PLATFORMS = { codex, cursor };

function parseArgs(argv) {
  const platforms = [];
  for (const arg of argv) {
    if (arg === '--codex') platforms.push('codex');
    else if (arg === '--cursor') platforms.push('cursor');
  }
  return { platforms };
}

function promptPlatforms() {
  if (!process.stdin.isTTY) return Promise.resolve(Object.keys(PLATFORMS));
  const rl = readline.createInterface({ input: process.stdin, output: process.stdout });
  return new Promise((resolve) => {
    rl.question('要裝哪個平台？(codex/cursor，逗號分隔，留空=全部): ', (answer) => {
      rl.close();
      const trimmed = answer.trim();
      if (!trimmed) return resolve(Object.keys(PLATFORMS));
      resolve(
        trimmed
          .split(',')
          .map((s) => s.trim())
          .filter((s) => PLATFORMS[s])
      );
    });
  });
}

async function run(argv, { repoRoot, targetDir, version }) {
  const { platforms } = parseArgs(argv);
  const selected = platforms.length > 0 ? platforms : await promptPlatforms();
  const vendorRoot = vendor({ repoRoot, targetDir, version });
  for (const name of selected) {
    PLATFORMS[name].install({ repoRoot, targetDir, vendorRoot });
  }
  return { vendorRoot, platforms: selected };
}

module.exports = { run, parseArgs, PLATFORMS };
