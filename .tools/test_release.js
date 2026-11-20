'use strict';
const assert = require('node:assert/strict');
const fs = require('node:fs');
const os = require('node:os');
const path = require('node:path');
const { resolveRelease, readGameVersionNames, selectGameVersions, buildCurseForgeMetadata, extractChangelogNotes } = require('./curseforge_deployment');
const { upload, parseArgs } = require('./curseforge_upload');
const root = path.resolve(__dirname, '..');
const temp = fs.mkdtempSync(path.join(os.tmpdir(), 'ulo-release-tests-'));
let passed = 0;
async function test(name, run) { await run(); console.log(`PASS ${name}`); passed++; }

async function main() {
  const names = ['1.15.9', '1.60.1', '12.0.1', '12.1.5', '2.5.6', '5.5.4'];
  const records = names.map((name, index) => ({ id: index + 101, name }));
  const file = path.join(temp, 'ULO-v1.0.1-beta.1.zip');
  const notes = path.join(temp, 'notes.md');
  const receipt = path.join(temp, 'receipt.json');
  fs.writeFileSync(file, Buffer.concat([Buffer.from('504b0304', 'hex'), Buffer.from('upload-contract-fixture')]));
  fs.writeFileSync(notes, 'Real release notes.');
  const args = { file, notes, receipt, version: '1.0.1-beta.1', channel: 'beta' };
  const env = { CURSEFORGE_PROJECT_ID: '123', CURSEFORGE_API_TOKEN: 'private-test-token' };
  const logs = [];
  const base = { env, repoRoot: root, log: line => logs.push(line) };
  await test('release-tag-and-channel-validation', () => {
    assert.deepEqual(resolveRelease({ tag: 'v1.0.1' }), { tag: 'v1.0.1', version: '1.0.1', channel: 'stable' });
    assert.equal(resolveRelease({ tag: 'v1.0.1-beta.1' }).channel, 'beta');
    assert.throws(() => resolveRelease({ tag: 'v1.0.1-beta.1', channel: 'stable' }));
    for (const tag of ['dev', '../v1.0.1', 'v1.0.1\nextra', 'v1.0.1"; write-output x']) assert.throws(() => resolveRelease({ tag }));
  });
  await test('game-version-bindings-follow-all-manifests', () => assert.deepEqual(readGameVersionNames(root), names));
  await test('unsupported-game-versions-never-fall-back-to-unrelated-IDs', () => {
    const selected = selectGameVersions([...records, { id: 999, name: '9.9.9' }], names);
    assert.deepEqual(selected.ids, [101, 102, 103, 104, 105, 106]);
    assert.deepEqual(selected.missing, []);
    assert.throws(() => selectGameVersions([{ id: 999, name: '9.9.9' }], names));
    assert.deepEqual(selectGameVersions(records.slice(1), names).missing, ['1.15.9']);
  });
  await test('metadata-requires-supported-release-contract', () => {
    assert.throws(() => buildCurseForgeMetadata({ version: '1.0.1', releaseType: 'release', gameVersions: [] }));
    assert.throws(() => buildCurseForgeMetadata({ version: '1.0.1', releaseType: 'typo', gameVersions: [101] }));
    assert.equal(buildCurseForgeMetadata({ version: '1.0.1', releaseType: 'release', gameVersions: [101] }).releaseType, 'release');
  });
  await test('release-notes-match-exact-version-section', () => {
    const changelog = path.join(temp, 'changelog.md');
    fs.writeFileSync(changelog, '# Changelog\n\n## [v1.0.10]\nWrong release\n\n## [v1.0.1]\nCorrect release\n');
    assert.equal(extractChangelogNotes(changelog, '1.0.1'), 'Correct release');
  });
  await test('missing-credentials-fail-before-network', async () => {
    await assert.rejects(upload(args, { ...base, env: {}, fetchImpl: () => { throw new Error('Network must not run'); } }), /must be configured/);
    assert.throws(() => parseArgs(['--file']));
  });
  await test('multipart-upload-records-exact-archive-and-file-ID', async () => {
    let calls = 0;
    const result = await upload(args, { ...base, fetchImpl: async (url, request) => {
      calls++;
      assert.equal(request.headers['X-Api-Token'], env.CURSEFORGE_API_TOKEN);
      assert.equal(request.redirect, 'error');
      if (calls === 1) { assert.equal(url, 'https://wow.curseforge.com/api/game/versions'); return { ok: true, json: async () => records }; }
      assert.equal(url, 'https://wow.curseforge.com/api/projects/123/upload-file');
      assert.equal(request.method, 'POST');
      const metadata = JSON.parse(request.body.get('metadata'));
      assert.equal(metadata.releaseType, 'beta');
      assert.equal(metadata.changelog, 'Real release notes.');
      assert.deepEqual(metadata.gameVersions, [101, 102, 103, 104, 105, 106]);
      assert.deepEqual(Buffer.from(await request.body.get('file').arrayBuffer()), fs.readFileSync(file));
      return { ok: true, json: async () => ({ id: 456 }) };
    } });
    assert.equal(calls, 2);
    assert.equal(result.id, 456);
    assert.equal(JSON.parse(fs.readFileSync(receipt)).sha256, result.sha256);
    assert.equal(logs.join('\n').includes(env.CURSEFORGE_API_TOKEN), false);
  });
  await test('exact-upload-receipt-prevents-duplicate-publication', async () => {
    assert.equal((await upload(args, { ...base, fetchImpl: () => { throw new Error('Duplicate upload'); } })).id, 456);
  });
  await test('receipt-mismatch-rejects-a-different-project-or-archive', async () => {
    await assert.rejects(upload({ ...args, 'project-id': '789' }, base), /does not match/);
    const changed = path.join(temp, 'changed.zip');
    fs.writeFileSync(changed, Buffer.concat([Buffer.from('504b0304', 'hex'), Buffer.from('other bytes')]));
    await assert.rejects(upload({ ...args, file: changed }, base), /does not match/);
  });
  await test('partial-version-support-aborts-before-upload', async () => {
    let calls = 0;
    await assert.rejects(upload({ ...args, receipt: undefined }, { ...base, fetchImpl: async () => { calls++; return { ok: true, json: async () => records.slice(1) }; } }), /lacks declared versions/);
    assert.equal(calls, 1);
  });
  await test('HTTP-failures-never-print-response-secrets', async () => {
    await assert.rejects(upload({ ...args, receipt: undefined }, { ...base, fetchImpl: async () => ({ ok: false, status: 403, text: () => { throw new Error(env.CURSEFORGE_API_TOKEN); } }) }), /^Error: CurseForge game versions request failed \(HTTP 403\)\.$/);
  });
  console.log(`Release publishing checks passed (${passed} cases).`);
}
main().catch(err => { console.error(err); process.exitCode = 1; }).finally(() => {
  // Only flat files created by these fixtures; no recursive deletion.
  for (const name of fs.readdirSync(temp)) fs.unlinkSync(path.join(temp, name));
  fs.rmdirSync(temp);
});
