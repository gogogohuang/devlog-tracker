'use strict';
const test = require('node:test');
const assert = require('node:assert/strict');
const fs = require('fs');
const os = require('os');
const path = require('path');
const { upsertAgentsMd, BEGIN, END } = require('./agents-md');
const { run } = require('./init');

function tmp() {
  return fs.mkdtempSync(path.join(os.tmpdir(), 'devlog-tracker-agents-'));
}

test('creates AGENTS.md when missing', () => {
  const dir = tmp();
  const file = upsertAgentsMd(dir);
  const text = fs.readFileSync(file, 'utf8');
  assert.ok(text.startsWith(BEGIN));
  assert.ok(text.includes('.devlog-tracker/commands/'));
  assert.ok(text.trimEnd().endsWith(END));
});

test('appends after existing content without touching it', () => {
  const dir = tmp();
  fs.writeFileSync(path.join(dir, 'AGENTS.md'), '# My rules\n\nBe nice.\n');
  const text = fs.readFileSync(upsertAgentsMd(dir), 'utf8');
  assert.ok(text.startsWith('# My rules\n\nBe nice.\n\n'));
  assert.ok(text.includes(BEGIN));
});

test('is idempotent and replaces the block in place', () => {
  const dir = tmp();
  fs.writeFileSync(path.join(dir, 'AGENTS.md'), `before\n${BEGIN}\nold stale text\n${END}\nafter\n`);
  const once = fs.readFileSync(upsertAgentsMd(dir), 'utf8');
  const twice = fs.readFileSync(upsertAgentsMd(dir), 'utf8');
  assert.equal(once, twice);
  assert.ok(!once.includes('old stale text'));
  assert.ok(once.startsWith('before\n'));
  assert.ok(once.endsWith('after\n'));
  assert.equal(once.split(BEGIN).length, 2);
});

test('block mentions every command doc so Codex has an entry for each', () => {
  const commandsDir = path.join(__dirname, '..', 'commands');
  const text = fs.readFileSync(upsertAgentsMd(tmp()), 'utf8');
  for (const file of fs.readdirSync(commandsDir).filter((f) => f.endsWith('.md'))) {
    assert.ok(text.includes(`commands/${file}`), `AGENTS.md block is missing commands/${file}`);
  }
});

test('init --codex writes AGENTS.md; --cursor alone does not', async () => {
  const repoRoot = path.join(__dirname, '..');
  const withCodex = tmp();
  await run(['--codex'], { repoRoot, targetDir: withCodex, version: '0.0.0' });
  assert.ok(fs.existsSync(path.join(withCodex, 'AGENTS.md')));

  const cursorOnly = tmp();
  await run(['--cursor'], { repoRoot, targetDir: cursorOnly, version: '0.0.0' });
  assert.ok(!fs.existsSync(path.join(cursorOnly, 'AGENTS.md')));
});
