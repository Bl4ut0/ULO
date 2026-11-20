'use strict';

const fs = require('fs');
const path = require('path');
const crypto = require('crypto');
const { buildCurseForgeMetadata, resolveRelease, readGameVersionNames, selectGameVersions } = require('./curseforge_deployment');
const API_BASE = 'https://wow.curseforge.com/api';

function parseArgs(argv) {
  const args = {};
  for (let i = 0; i < argv.length; i += 2) {
    if (!/^--[a-z-]+$/.test(argv[i]) || !argv[i + 1] || argv[i + 1].startsWith('--')) throw new Error('Every upload option requires a value.');
    args[argv[i].slice(2)] = argv[i + 1];
  }
  return args;
}

async function upload(args, { env = process.env, fetchImpl = fetch, repoRoot = path.resolve(__dirname, '..'), log = console.log } = {}) {
  const projectId = String(args['project-id'] || env.CURSEFORGE_PROJECT_ID || '');
  const token = (env.CURSEFORGE_API_TOKEN || '').trim();
  if (!/^\d+$/.test(projectId) || !token) throw new Error('CURSEFORGE_PROJECT_ID and CURSEFORGE_API_TOKEN must be configured.');
  const { version, channel } = resolveRelease({ tag: `v${args.version || ''}`, channel: args.channel || 'beta' });
  if (!args.file || !fs.existsSync(args.file)) throw new Error('Release ZIP is missing.');
  const bytes = fs.readFileSync(args.file);
  if (bytes.subarray(0, 4).toString('hex') !== '504b0304') throw new Error('Release file is not a ZIP archive.');
  const sha256 = crypto.createHash('sha256').update(bytes).digest('hex');
  if (args.receipt && fs.existsSync(args.receipt)) {
    const receipt = JSON.parse(fs.readFileSync(args.receipt, 'utf8').replace(/^\uFEFF/, ''));
    if (receipt.projectId !== projectId || receipt.version !== version || receipt.sha256 !== sha256 || !Number.isInteger(receipt.id) || receipt.id < 1) throw new Error('Existing CurseForge receipt does not match this release.');
    log(`CurseForge file ${receipt.id} already records this exact archive; skipping duplicate upload.`);
    return receipt;
  }
  const response = await fetchImpl(`${API_BASE}/game/versions`, { headers: { 'X-Api-Token': token }, redirect: 'error', signal: AbortSignal.timeout(30000) });
  if (!response.ok) throw new Error(`CurseForge game versions request failed (HTTP ${response.status}).`);
  const selected = selectGameVersions(await response.json(), readGameVersionNames(repoRoot));
  if (selected.missing.length) throw new Error(`CurseForge lacks declared versions: ${selected.missing.join(', ')}. Update support metadata explicitly before publishing.`);
  const changelog = args.notes ? fs.readFileSync(args.notes, 'utf8') : `Release v${version}`;
  const metadata = buildCurseForgeMetadata({ version, releaseType: channel === 'stable' ? 'release' : 'beta', changelog, gameVersions: selected.ids });
  const form = new FormData();
  form.append('metadata', JSON.stringify(metadata));
  form.append('file', new Blob([bytes], { type: 'application/zip' }), path.basename(args.file));
  log(`Uploading ULO v${version} (${channel}) for ${selected.matched.join(', ')}.`);
  const res = await fetchImpl(`${API_BASE}/projects/${projectId}/upload-file`, { method: 'POST', headers: { 'X-Api-Token': token }, body: form, redirect: 'error', signal: AbortSignal.timeout(120000) });
  if (!res.ok) throw new Error(`CurseForge upload failed (HTTP ${res.status}).`);
  const result = await res.json();
  if (!Number.isInteger(result.id) || result.id < 1) throw new Error('CurseForge did not return a valid file ID.');
  const receipt = { id: result.id, projectId, version, sha256, gameVersions: selected.ids };
  if (args.receipt) {
    fs.mkdirSync(path.dirname(args.receipt), { recursive: true });
    fs.writeFileSync(args.receipt, JSON.stringify(receipt, null, 2) + '\n');
  }
  log(`CurseForge accepted file ${result.id}; moderation may still be pending.`);
  return receipt;
}

if (require.main === module) upload(parseArgs(process.argv.slice(2))).catch(err => { console.error(err.message); process.exitCode = 1; });
module.exports = { parseArgs, upload };
