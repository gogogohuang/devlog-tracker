#!/usr/bin/env node
'use strict';

function main(argv) {
  const [command] = argv;
  const pkg = require('../package.json');

  if (command === '--version' || command === '-v') {
    console.log(pkg.version);
    return 0;
  }
  if (!command || command === '--help' || command === '-h') {
    console.log('Usage: devlog-tracker <init|status> [--codex] [--cursor]');
    return 0;
  }
  if (command === 'init' || command === 'status') {
    console.error(`"${command}" is not wired up yet.`);
    return 1;
  }
  console.error(`Unknown command: ${command}`);
  return 1;
}

process.exitCode = main(process.argv.slice(2));
