'use strict';

const fs = require('fs');
const path = require('path');

function extractChangelogNotes(changelogPath, version) {
  if (!fs.existsSync(changelogPath)) {
    return `Release v${version}`;
  }
  const text = fs.readFileSync(changelogPath, 'utf8');
  const cleanVer = version.replace(/^v/i, '');
  const lines = text.split(/\r?\n/);
  const out = [];
  let capturing = false;

  for (const line of lines) {
    if (/^##\s+/.test(line)) {
      if (capturing) break;
      const heading = line.match(/^##\s+\[v?([^\]]+)\]/);
      if (heading && heading[1] === cleanVer) {
        capturing = true;
        continue;
      }
    } else if (capturing) {
      out.push(line);
    }
  }

  const trimmed = out.join('\n').trim();
  return trimmed || `Release v${cleanVer}`;
}

function buildCurseForgeMetadata({ version, releaseType, changelog, gameVersions }) {
  if (!['release', 'beta'].includes(releaseType)) throw new Error('Unsupported CurseForge release type.');
  if (!Array.isArray(gameVersions) || gameVersions.length === 0) throw new Error('Supported CurseForge game versions are required.');
  return {
    changelog: changelog || `Release v${version}`,
    changelogType: 'markdown',
    displayName: `ULO v${version}`,
    gameVersions: Array.isArray(gameVersions) ? gameVersions : [],
    releaseType: releaseType === 'release' ? 'release' : 'beta',
  };
}

function writeReleaseNotesFiles({ outDir, version, channel, changelog }) {
  fs.mkdirSync(outDir, { recursive: true });
  const label = channel === 'stable' ? 'Release' : 'Beta';
  const ghNotes = `# ULO v${version} (${label})\n\n${changelog}\n`;
  const cfNotes = changelog + '\n';
  fs.writeFileSync(path.join(outDir, 'GITHUB_RELEASE.md'), ghNotes, 'utf8');
  fs.writeFileSync(path.join(outDir, 'CURSEFORGE_RELEASE.md'), cfNotes, 'utf8');
}

function resolveRelease({ tag, channel, prerelease }) {
  if (!/^v\d+\.\d+\.\d+(?:-[0-9A-Za-z.-]+)?$/.test(tag || '')) throw new Error('Expected a version tag such as v1.0.1 or v1.0.1-beta.1.');
  const version = tag.slice(1);
  channel = channel || (prerelease === true || version.includes('-') ? 'beta' : 'stable');
  if (!['stable', 'beta'].includes(channel)) throw new Error('Unsupported release channel.');
  if (channel === 'stable' && (version.includes('-') || prerelease === true)) throw new Error('A prerelease cannot be published as stable.');
  return { tag, version, channel };
}

function readGameVersionNames(repoRoot) {
  const { TOC_FILES } = require('./release_distribution');
  const names = new Set();
  for (const relative of TOC_FILES) {
    const text = fs.readFileSync(path.join(repoRoot, relative), 'utf8');
    const line = text.match(/^##\s*Interface:\s*([\d, ]+)\r?$/m);
    if (!line) throw new Error(`No interface versions in ${relative}.`);
    for (const value of line[1].split(',')) {
      const n = Number(value.trim());
      if (!Number.isInteger(n) || n < 10000) throw new Error(`Invalid interface in ${relative}.`);
      names.add(`${Math.floor(n / 10000)}.${Math.floor(n / 100) % 100}.${n % 100}`);
    }
  }
  return [...names].sort();
}

function selectGameVersions(records, wanted) {
  if (!Array.isArray(records)) throw new Error('Invalid CurseForge game version response.');
  const supported = records.filter(v => wanted.includes(v.name) && Number.isInteger(v.id) && v.id > 0);
  const ids = [...new Set(supported.map(v => v.id))];
  if (ids.length === 0) throw new Error('No declared interface versions are available on CurseForge; refusing unrelated fallback versions.');
  return { ids, matched: [...new Set(supported.map(v => v.name))].sort(), missing: wanted.filter(n => !supported.some(v => v.name === n)) };
}

module.exports = {
  extractChangelogNotes,
  buildCurseForgeMetadata,
  writeReleaseNotesFiles,
  resolveRelease,
  readGameVersionNames,
  selectGameVersions,
};
