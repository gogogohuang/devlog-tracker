'use strict';
const test = require('node:test');
const assert = require('node:assert/strict');
const fs = require('fs');
const os = require('os');
const path = require('path');
const { upsertAgentsMd, upsertMarkdown, BEGIN, END } = require('./agents-md');
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

test('block mentions every command doc and Codex skill naming convention', () => {
  const commandsDir = path.join(__dirname, '..', 'commands');
  const text = fs.readFileSync(upsertAgentsMd(tmp()), 'utf8');
  for (const file of fs.readdirSync(commandsDir).filter((f) => f.endsWith('.md'))) {
    assert.ok(text.includes(`commands/${file}`), `AGENTS.md block is missing commands/${file}`);
  }
  assert.ok(text.includes('$devlog-start'));
});

test('init --codex writes AGENTS.md and project skills; --cursor alone does not', async () => {
  const repoRoot = path.join(__dirname, '..');
  const withCodex = tmp();
  await run(['--codex'], { repoRoot, targetDir: withCodex, version: '0.0.0' });
  assert.ok(fs.existsSync(path.join(withCodex, 'AGENTS.md')));
  for (const file of fs.readdirSync(path.join(repoRoot, 'commands')).filter((file) => file.endsWith('.md'))) {
    const name = `devlog-${path.basename(file, '.md')}`;
    const skill = fs.readFileSync(path.join(withCodex, '.agents', 'skills', name, 'SKILL.md'), 'utf8');
    assert.match(skill, new RegExp(`^---\\nname: ${name}\\ndescription: ".+"\\n---\\n`));
  }
  assert.ok(!fs.existsSync(path.join(withCodex, '.codex', 'prompts')));

  const upgraded = tmp();
  const legacy = path.join(upgraded, '.codex', 'prompts');
  fs.mkdirSync(legacy, { recursive: true });
  fs.writeFileSync(path.join(legacy, 'devlog-start.md'), 'old');
  fs.writeFileSync(path.join(legacy, 'mine.md'), 'keep');
  await run(['--codex'], { repoRoot, targetDir: upgraded, version: '0.0.0' });
  assert.ok(!fs.existsSync(path.join(legacy, 'devlog-start.md')));
  assert.ok(fs.existsSync(path.join(legacy, 'mine.md')));

  const cursorOnly = tmp();
  await run(['--cursor'], { repoRoot, targetDir: cursorOnly, version: '0.0.0' });
  assert.ok(!fs.existsSync(path.join(cursorOnly, 'AGENTS.md')));
});

test('upsertMarkdown writes to a custom file name with a custom block', () => {
  const targetDir = tmp();

  const filePath = upsertMarkdown(targetDir, {
    fileName: 'CLAUDE.md',
    block: `${BEGIN}\n## custom\n${END}\n`,
  });

  assert.equal(filePath, path.join(targetDir, 'CLAUDE.md'));
  assert.equal(fs.readFileSync(filePath, 'utf8'), `${BEGIN}\n## custom\n${END}\n`);
});

test('upsertAgentsMd keeps writing AGENTS.md by default (back-compat)', () => {
  const targetDir = tmp();

  const filePath = upsertAgentsMd(targetDir);

  assert.equal(filePath, path.join(targetDir, 'AGENTS.md'));
});
