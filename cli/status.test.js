'use strict';
const test = require('node:test');
const assert = require('node:assert/strict');
const fs = require('fs');
const os = require('os');
const path = require('path');
const { status } = require('./status');

function tmpdir() {
  return fs.mkdtempSync(path.join(os.tmpdir(), 'devlog-tracker-status-'));
}

test('reports not installed when .devlog-tracker/VERSION is missing', () => {
  const targetDir = tmpdir();
  const result = status({ targetDir, currentVersion: '0.21.0' });
  assert.deepEqual(result, { installed: false, vendoredVersion: null, upToDate: false });
});

test('reports up to date when versions match', () => {
  const targetDir = tmpdir();
  fs.mkdirSync(path.join(targetDir, '.devlog-tracker'), { recursive: true });
  fs.writeFileSync(path.join(targetDir, '.devlog-tracker', 'VERSION'), '0.21.0\n');
  const result = status({ targetDir, currentVersion: '0.21.0' });
  assert.deepEqual(result, { installed: true, vendoredVersion: '0.21.0', upToDate: true });
});

test('reports out of date when versions differ', () => {
  const targetDir = tmpdir();
  fs.mkdirSync(path.join(targetDir, '.devlog-tracker'), { recursive: true });
  fs.writeFileSync(path.join(targetDir, '.devlog-tracker', 'VERSION'), '0.20.0\n');
  const result = status({ targetDir, currentVersion: '0.21.0' });
  assert.deepEqual(result, { installed: true, vendoredVersion: '0.20.0', upToDate: false });
});
