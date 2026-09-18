'use strict';
const test = require('node:test');
const assert = require('node:assert/strict');
const fs = require('fs');
const os = require('os');
const path = require('path');
const { syncVersion, checkVersion } = require('./sync-version');

function makeRoot({ pkg = '0.22.0', plugin = '0.21.0', market = '0.21.0', readme = '0.21.0' } = {}) {
  const root = fs.mkdtempSync(path.join(os.tmpdir(), 'devlog-tracker-sync-'));
  fs.mkdirSync(path.join(root, '.claude-plugin'));
  fs.writeFileSync(path.join(root, 'package.json'), `${JSON.stringify({ name: 'x', version: pkg }, null, 2)}\n`);
  fs.writeFileSync(
    path.join(root, '.claude-plugin', 'plugin.json'),
    `${JSON.stringify({ name: 'x', version: plugin, description: 'd' }, null, 2)}\n`
  );
  fs.writeFileSync(
    path.join(root, '.claude-plugin', 'marketplace.json'),
    `${JSON.stringify({ name: 'x', plugins: [{ name: 'x', version: market }] }, null, 2)}\n`
  );
  fs.writeFileSync(path.join(root, 'README.md'), `# x\n\n**版本** ${readme}\n\nbody 0.21.0 stays\n`);
  return root;
}

test('syncVersion copies package.json version into the three other files', () => {
  const root = makeRoot();
  const version = syncVersion(root);
  assert.equal(version, '0.22.0');
  const plugin = JSON.parse(fs.readFileSync(path.join(root, '.claude-plugin', 'plugin.json'), 'utf8'));
  const market = JSON.parse(fs.readFileSync(path.join(root, '.claude-plugin', 'marketplace.json'), 'utf8'));
  assert.equal(plugin.version, '0.22.0');
  assert.equal(plugin.description, 'd');
  assert.equal(market.plugins[0].version, '0.22.0');
  const readme = fs.readFileSync(path.join(root, 'README.md'), 'utf8');
  assert.match(readme, /^\*\*版本\*\* 0\.22\.0$/m);
  assert.match(readme, /body 0\.21\.0 stays/);
});

test('syncVersion is idempotent', () => {
  const root = makeRoot();
  syncVersion(root);
  const before = fs.readFileSync(path.join(root, 'README.md'), 'utf8');
  syncVersion(root);
  assert.equal(fs.readFileSync(path.join(root, 'README.md'), 'utf8'), before);
});

test('syncVersion throws when README has no version line', () => {
  const root = makeRoot();
  fs.writeFileSync(path.join(root, 'README.md'), '# x\n\nno version here\n');
  assert.throws(() => syncVersion(root), /README\.md/);
});

test('checkVersion passes when all four files agree', () => {
  const root = makeRoot({ pkg: '0.22.0', plugin: '0.22.0', market: '0.22.0', readme: '0.22.0' });
  assert.deepEqual(checkVersion(root), { ok: true, version: '0.22.0', problems: [] });
});

test('checkVersion names every file that disagrees', () => {
  const root = makeRoot({ pkg: '0.22.0', plugin: '0.21.0', market: '0.22.0', readme: '0.20.0' });
  const result = checkVersion(root);
  assert.equal(result.ok, false);
  assert.equal(result.problems.length, 2);
  assert.match(result.problems.join('\n'), /plugin\.json/);
  assert.match(result.problems.join('\n'), /README\.md/);
});

test('checkVersion with a tag requires tag === v<package version>', () => {
  const root = makeRoot({ pkg: '0.22.0', plugin: '0.22.0', market: '0.22.0', readme: '0.22.0' });
  assert.equal(checkVersion(root, { tag: 'v0.22.0' }).ok, true);
  const bad = checkVersion(root, { tag: 'v0.23.0' });
  assert.equal(bad.ok, false);
  assert.match(bad.problems.join('\n'), /v0\.23\.0/);
});
