import { createHash } from 'node:crypto';
import { execFileSync } from 'node:child_process';
import { mkdtempSync, readFileSync, rmSync, writeFileSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { basename, join, resolve } from 'node:path';
import { setTimeout } from 'node:timers/promises';
import { fileURLToPath } from 'node:url';

const repository = 'SakuraCordApp/SakuraCord';
const hash = bytes => createHash('sha256').update(bytes).digest('hex');

export function validateHotfixTarget(release, latest, tag, build, appcast) {
  if (!/^v\d+\.\d+\.\d+$/.test(tag) || release.tag_name !== tag
      || release.draft !== false || release.prerelease !== false
      || release.immutable === true || latest.id !== release.id) {
    throw new Error('Hotfixes require the existing latest, mutable regular release.');
  }
  const previous = appcast.match(/<sparkle:version>(\d+)<\/sparkle:version>/)?.[1];
  if (!previous || !/^[1-9]\d*$/.test(build) || BigInt(build) <= BigInt(previous)) {
    throw new Error('The hotfix build must be newer than the published build. Use a new dispatch, not a rerun of an already published hotfix.');
  }
}

// All remote writes stay in this function. It neither creates/releases a tag
// nor edits release metadata, and has no Discord delivery path.
export async function publishHotfix({ tag, build, source, runId, archive, appcast, io }) {
  const state = await io.readState();
  validateHotfixTarget(state.release, state.latest, tag, build, state.appcast);
  if (!/^[0-9a-f]{40}$/.test(source) || !/^\d+$/.test(runId)) {
    throw new Error('A full source commit and workflow run ID are required.');
  }
  const name = `SakuraCord.${tag}.dmg`;
  if (basename(archive.path) !== name
      || !appcast.bytes.toString().includes(`<sparkle:version>${build}</sparkle:version>`)
      || !appcast.bytes.toString().includes(`https://github.com/${repository}/releases/download/${tag}/${name}`)) {
    throw new Error('The verified archive and appcast do not match this hotfix.');
  }
  const manifest = Buffer.from(`${JSON.stringify({
    schemaVersion: 1, tagName: tag, buildNumber: build, sourceCommit: source,
    runId, archiveName: name, sha256: hash(archive.bytes), appcastSHA256: hash(appcast.bytes),
  }, null, 2)}\n`);

  // Keep a build-specific recovery copy outside the website's .dmg selection.
  // Replace the signed feed only after verifying the canonical download.
  await io.preserveOriginal(state.release, name);
  await io.uploadImmutable(`hotfix-build-${build}.dmg.backup`, archive.bytes);
  await io.uploadImmutable(`hotfix-build-${build}.json`, manifest);
  await io.replace(name, archive.bytes);
  await io.verify(name, archive.bytes);
  await io.replace('appcast.xml', appcast.bytes);
  await io.verify('appcast.xml', appcast.bytes);
}

function gh(args) {
  return execFileSync('gh', args, { maxBuffer: 128 * 1024 * 1024 });
}

function releaseFor(tag) {
  return JSON.parse(gh(['api', `repos/${repository}/releases/tags/${tag}`]));
}

function assetBytes(release, name) {
  const asset = release.assets.find(asset => asset.name === name);
  if (!asset) throw new Error(`Missing published asset: ${name}`);
  return gh(['api', `repos/${repository}/releases/assets/${asset.id}`, '-H', 'Accept: application/octet-stream']);
}

async function main() {
  const { SAKURACORD_RELEASE_TAG: tag, SAKURACORD_HOTFIX_COMMIT: source,
    GITHUB_RUN_NUMBER: build, GITHUB_RUN_ID: runId } = process.env;
  if (process.env.GITHUB_REPOSITORY !== repository || !/^v\d+\.\d+\.\d+$/.test(tag ?? '')) {
    throw new Error('Quiet hotfix publication is restricted to this repository and a regular release tag.');
  }
  const readState = () => {
    const release = releaseFor(tag);
    return { release, latest: JSON.parse(gh(['api', `repos/${repository}/releases/latest`])),
      appcast: assetBytes(release, 'appcast.xml').toString() };
  };
  if (process.argv[2] === 'preflight') {
    const state = readState();
    validateHotfixTarget(state.release, state.latest, tag, build, state.appcast);
    console.log(`Quiet hotfix preflight passed for ${tag}, build ${build}.`);
    return;
  }
  if (process.argv[2] !== 'publish') throw new Error('Expected preflight or publish.');
  const staging = mkdtempSync(join(tmpdir(), 'sakuracord-hotfix-'));
  try {
    const upload = (name, bytes, replace) => {
      const path = join(staging, name);
      writeFileSync(path, bytes);
      gh(['release', 'upload', tag, path, '--repo', repository, ...(replace ? ['--clobber'] : [])]);
    };
    const verify = async (name, bytes) => {
      for (let attempt = 1; attempt <= 5; attempt++) {
        try {
          if (!assetBytes(releaseFor(tag), name).equals(bytes)) {
            throw new Error(`Published asset differs from verified input: ${name}`);
          }
          return;
        } catch (error) {
          if (attempt === 5) throw error;
          await setTimeout(2000);
        }
      }
    };
    const archivePath = process.env.SAKURACORD_DMG_PATH;
    await publishHotfix({ tag, build, source, runId,
      archive: { path: archivePath, bytes: readFileSync(archivePath) },
      appcast: { bytes: readFileSync('dist/appcast.xml') },
      io: { readState, verify,
        preserveOriginal: (release, name) => {
          const backup = `original-${name}.backup`;
          const existing = release.assets.find(asset => asset.name === backup);
          if (existing) {
            if (existing.state !== 'uploaded' || existing.size <= 0) {
              throw new Error('The original archive backup is incomplete.');
            }
          } else {
            const bytes = assetBytes(release, name);
            upload(backup, bytes, false);
            return verify(backup, bytes);
          }
        },
        replace: (name, bytes) => upload(name, bytes, true),
        uploadImmutable: (name, bytes) => {
          const release = releaseFor(tag);
          if (release.assets.some(asset => asset.name === name)) return verify(name, bytes);
          upload(name, bytes, false);
        },
      },
    });
    console.log(`Published ${tag} build ${build}; release metadata and Discord were untouched.`);
  } finally {
    rmSync(staging, { recursive: true, force: true });
  }
}

if (process.argv[1] && resolve(process.argv[1]) === fileURLToPath(import.meta.url)) {
  main().catch(error => { console.error(error.message); process.exitCode = 1; });
}
