#!/usr/bin/env node
'use strict';
const { execFileSync } = require('child_process');
const fs = require('fs');
const path = require('path');

const BUMPS = ['minor', 'patch'];

function defaultRun(cmd, args) {
  return execFileSync(cmd, args, { encoding: 'utf8', stdio: ['ignore', 'pipe', 'inherit'] }).trim();
}

function preflight(run) {
  const problems = [];
  const branch = run('git', ['rev-parse', '--abbrev-ref', 'HEAD']);
  if (branch !== 'main') problems.push(`must be on main (currently on ${branch})`);
  if (run('git', ['status', '--porcelain'])) problems.push('working tree has uncommitted changes');
  run('git', ['fetch', 'origin', 'main']);
  const [ahead, behind] = run('git', ['rev-list', '--left-right', '--count', 'HEAD...origin/main'])
    .split(/\s+/)
    .map(Number);
  if (behind > 0) problems.push(`main is ${behind} commit(s) behind origin/main`);
  if (ahead > 0) problems.push(`main has ${ahead} unpushed commit(s)`);
  return problems;
}

function release(bump, { run = defaultRun, dryRun = false, log = console.log, root = path.join(__dirname, '..') } = {}) {
  if (!BUMPS.includes(bump)) throw new Error(`usage: release <${BUMPS.join('|')}> [--dry-run]`);

  const problems = preflight(run);
  if (problems.length) throw new Error(`Cannot release:\n- ${problems.join('\n- ')}`);

  const current = JSON.parse(fs.readFileSync(path.join(root, 'package.json'), 'utf8')).version;
  const [major, minor, patch] = current.split('.').map(Number);
  const next = bump === 'minor' ? `${major}.${minor + 1}.0` : `${major}.${minor}.${patch + 1}`;
  const tag = `v${next}`;

  const steps = [
    ['npm', ['test']],
    ['pnpm', ['version', bump]],
    ['git', ['push', '--follow-tags']],
    ['gh', ['release', 'create', tag, '--generate-notes']],
  ];
  log(`${dryRun ? '[dry-run] ' : ''}release ${current} -> ${next}`);
  for (const [cmd, args] of steps) {
    log(`$ ${cmd} ${args.join(' ')}`);
    if (!dryRun) run(cmd, args);
  }
  return { current, next, tag };
}

if (require.main === module) {
  const args = process.argv.slice(2);
  try {
    release(args.find((a) => !a.startsWith('--')), { dryRun: args.includes('--dry-run') });
  } catch (err) {
    console.error(err.message);
    process.exitCode = 1;
  }
}

module.exports = { release, preflight };
