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
    console.log('Usage: devlog-tracker <init|status|report|timeline> [--claude] [--codex] [--cursor] [--prune] [--json] [--all-branches] [--out <path>]');
    return 0;
  }
  if (command === 'init') {
    const { run } = require('../cli/init');
    const result = await run(rest, {
      repoRoot: path.join(__dirname, '..'),
      targetDir: process.cwd(),
      version: pkg.version,
    });
    if (result.pruned !== undefined) {
      console.log(`Removed ${result.pruned} stale devlog-tracker hook(s).`);
      return 0;
    }
    console.log(`devlog-tracker installed to ${result.vendorRoot} for: ${result.platforms.join(', ')}`);
    return 0;
  }
  if (command === 'status') {
    const { status } = require('../cli/status');
    const result = status({ targetDir: process.cwd(), currentVersion: pkg.version });
    if (result.staleHooks.length > 0) {
      const n = result.staleHooks.reduce((sum, h) => sum + h.count, 0);
      const files = [...new Set(result.staleHooks.map((h) => h.file))].join(', ');
      console.log(`Warning: ${n} hook(s) in ${files} point to missing .devlog-tracker scripts. Run \`npx devlog-tracker init --prune\` to remove them (or \`init\` to reinstall).`);
    }
    if (!result.installed) {
      console.log('devlog-tracker is not installed in this project. Run `npx devlog-tracker init`.');
    } else if (result.upToDate) {
      console.log(`devlog-tracker ${result.vendoredVersion} is up to date.`);
    } else {
      console.log(
        `devlog-tracker ${result.vendoredVersion} is installed; ${pkg.version} is available. Run \`npx devlog-tracker init\` to upgrade.`
      );
    }
    return 0;
  }
  const CORE_COMMANDS = { report: 'report-devlog.sh', timeline: 'timeline-devlog.sh' };
  if (Object.prototype.hasOwnProperty.call(CORE_COMMANDS, command)) {
    const { runCoreScript } = require('../cli/core-script');
    const r = runCoreScript({
      targetDir: process.cwd(),
      repoRoot: path.join(__dirname, '..'),
      name: CORE_COMMANDS[command],
      args: rest,
    });
    process.stdout.write(r.stdout);
    process.stderr.write(r.stderr);
    return r.status;
  }
  console.error(`Unknown command: ${command}`);
  return 1;
}

main(process.argv.slice(2)).then(
  (code) => { process.exitCode = code; },
  (err) => {
    console.error(err instanceof Error ? err.message : err);
    process.exitCode = 1;
  }
);
