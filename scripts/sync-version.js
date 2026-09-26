#!/usr/bin/env node
'use strict';
const fs = require('fs');
const path = require('path');

const README_FILES = [
  { file: 'README.md', label: 'Version', line: /^\*\*Version\*\* \S+$/m },
  { file: 'README.zh-TW.md', label: '版本', line: /^\*\*版本\*\* \S+$/m },
];

function readJson(file) {
  return JSON.parse(fs.readFileSync(file, 'utf8'));
}

function writeJson(file, data) {
  fs.writeFileSync(file, `${JSON.stringify(data, null, 2)}\n`);
}

function syncVersion(root) {
  const { version } = readJson(path.join(root, 'package.json'));

  const pluginFile = path.join(root, '.claude-plugin', 'plugin.json');
  const plugin = readJson(pluginFile);
  plugin.version = version;
  writeJson(pluginFile, plugin);

  const codexPluginFile = path.join(root, '.codex-plugin', 'plugin.json');
  const codexPlugin = readJson(codexPluginFile);
  codexPlugin.version = version;
  writeJson(codexPluginFile, codexPlugin);

  const marketFile = path.join(root, '.claude-plugin', 'marketplace.json');
  const market = readJson(marketFile);
  market.plugins[0].version = version;
  writeJson(marketFile, market);

  for (const { file, label, line } of README_FILES) {
    const readmeFile = path.join(root, file);
    const readme = fs.readFileSync(readmeFile, 'utf8');
    if (!line.test(readme)) {
      throw new Error(`${file} has no "**${label}** X.Y.Z" line to update`);
    }
    fs.writeFileSync(readmeFile, readme.replace(line, `**${label}** ${version}`));
  }

  return version;
}

function checkVersion(root, { tag } = {}) {
  const { version } = readJson(path.join(root, 'package.json'));
  const problems = [];

  const plugin = readJson(path.join(root, '.claude-plugin', 'plugin.json'));
  if (plugin.version !== version) {
    problems.push(`.claude-plugin/plugin.json is ${plugin.version}, package.json is ${version}`);
  }
  const codexPlugin = readJson(path.join(root, '.codex-plugin', 'plugin.json'));
  if (codexPlugin.version !== version) {
    problems.push(`.codex-plugin/plugin.json is ${codexPlugin.version}, package.json is ${version}`);
  }
  const market = readJson(path.join(root, '.claude-plugin', 'marketplace.json'));
  if (market.plugins[0].version !== version) {
    problems.push(`.claude-plugin/marketplace.json is ${market.plugins[0].version}, package.json is ${version}`);
  }
  for (const { file, label, line } of README_FILES) {
    const readme = fs.readFileSync(path.join(root, file), 'utf8');
    const readmeLine = readme.match(line);
    if (!readmeLine || readmeLine[0] !== `**${label}** ${version}`) {
      problems.push(`${file} version line is not ${version}`);
    }
  }
  if (tag !== undefined && tag !== `v${version}`) {
    problems.push(`tag ${tag} does not match package.json version v${version}`);
  }

  return { ok: problems.length === 0, version, problems };
}

function main(argv) {
  const root = path.join(__dirname, '..');
  if (argv[0] === '--check') {
    const tagIndex = argv.indexOf('--tag');
    const tag = tagIndex === -1 ? undefined : argv[tagIndex + 1];
    const result = checkVersion(root, { tag });
    if (!result.ok) {
      console.error(`Version mismatch:\n- ${result.problems.join('\n- ')}`);
      return 1;
    }
    console.log(`Versions consistent: ${result.version}`);
    return 0;
  }
  console.log(`Synced version ${syncVersion(root)}`);
  return 0;
}

if (require.main === module) {
  try {
    process.exitCode = main(process.argv.slice(2));
  } catch (err) {
    console.error(err.message);
    process.exitCode = 1;
  }
}

module.exports = { syncVersion, checkVersion };
