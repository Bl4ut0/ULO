'use strict';
const fs = require('fs');
const { resolveRelease } = require('./curseforge_deployment');
try {
  const meta = resolveRelease({ tag: process.env.RELEASE_TAG, channel: process.env.RELEASE_CHANNEL || undefined, prerelease: process.env.RELEASE_PRERELEASE === 'true' });
  if (!process.env.GITHUB_OUTPUT) throw new Error('GITHUB_OUTPUT is required.');
  fs.appendFileSync(process.env.GITHUB_OUTPUT, Object.entries(meta).map(([k, v]) => `${k}=${v}\n`).join(''));
  console.log(`Validated ${meta.tag} (${meta.channel}).`);
} catch (err) { console.error(err.message); process.exitCode = 1; }
