#!/usr/bin/env node
'use strict';
const path = require('path');

async function main(argv) {
  const [command, ...rest] = argv;
  const pkg = require('../package.json');

  if (command === '--version' || command === '-v') {
    console.log(pkg.version);
    return 0;
  }
  if (!command || command === '--help' || command === '-h') {
    console.log('Usage: devlog-tracker <init|status> [--codex] [--cursor]');
    return 0;
  }
  if (command === 'init') {
    const { run } = require('../cli/init');
    const { vendorRoot, platforms } = await run(rest, {
      repoRoot: path.join(__dirname, '..'),
      targetDir: process.cwd(),
      version: pkg.version,
    });
    console.log(`devlog-tracker installed to ${vendorRoot} for: ${platforms.join(', ')}`);
    return 0;
  }
  if (command === 'status') {
    console.error('"status" is not wired up yet.');
    return 1;
  }
  console.error(`Unknown command: ${command}`);
  return 1;
}

main(process.argv.slice(2)).then(
  (code) => { process.exitCode = code; },
  (err) => { console.error(err); process.exitCode = 1; }
);
