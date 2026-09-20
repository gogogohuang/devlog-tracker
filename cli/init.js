'use strict';
const readline = require('readline');
const { vendor } = require('./vendor');
const claude = require('./platforms/claude');
const codex = require('./platforms/codex');
const cursor = require('./platforms/cursor');

const PLATFORMS = { claude, codex, cursor };

function parseArgs(argv) {
  const platforms = [];
  for (const arg of argv) {
    if (arg === '--claude') platforms.push('claude');
    else if (arg === '--codex') platforms.push('codex');
    else if (arg === '--cursor') platforms.push('cursor');
    else if (arg.startsWith('-')) {
      throw new Error(`Unknown option: ${arg} (supported: --claude, --codex, --cursor)`);
    }
  }
  return { platforms };
}

function promptPlatforms() {
  if (!process.stdin.isTTY) return Promise.resolve(Object.keys(PLATFORMS));
  const rl = readline.createInterface({ input: process.stdin, output: process.stdout });
  return new Promise((resolve) => {
    rl.question('要裝哪個平台？(claude/codex/cursor，逗號分隔，留空=全部): ', (answer) => {
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
    try {
      PLATFORMS[name].install({ repoRoot, targetDir, vendorRoot });
    } catch (err) {
      throw new Error(
        `Installed files to ${vendorRoot} but failed to configure ${name}: ${String(err.message).replace(/\.$/, '')}. Fix the issue and re-run \`devlog-tracker init\` (safe to re-run).`
      );
    }
  }
  return { vendorRoot, platforms: selected };
}

module.exports = { run, parseArgs, PLATFORMS };
