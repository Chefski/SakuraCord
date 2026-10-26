import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import test from 'node:test';
import { publishHotfix, validateHotfixTarget } from './release_hotfix.mjs';

const tag = 'v0.1.6';
const release = { id: 7, tag_name: tag, draft: false, prerelease: false };
const oldFeed = '<sparkle:version>100</sparkle:version>';

test('hotfixes only replace the latest published regular release with a higher build', () => {
  validateHotfixTarget(release, release, tag, '101', oldFeed);
  for (const changed of [
    { draft: true }, { prerelease: true }, { immutable: true }, { tag_name: 'v0.1.5' },
  ]) assert.throws(() => validateHotfixTarget({ ...release, ...changed }, release, tag, '101', oldFeed));
  assert.throws(() => validateHotfixTarget(release, { id: 8 }, tag, '101', oldFeed));
  for (const build of ['99', '100', '', 'NaN']) {
    assert.throws(() => validateHotfixTarget(release, release, tag, build, oldFeed));
  }
  assert.throws(() => validateHotfixTarget(release, release, tag, '101', 'invalid feed'));
});

function publication(failVerification = false) {
  const calls = [];
  const name = 'SakuraCord.v0.1.6.dmg';
  const io = {
    readState: () => ({ release, latest: release, appcast: oldFeed }),
    preserveOriginal: (_release, name) => calls.push(['preserve', name]),
    uploadImmutable: (name, bytes) => calls.push(['immutable', name, bytes]),
    replace: (name, bytes) => calls.push(['replace', name, bytes]),
    verify: name => {
      calls.push(['verify', name]);
      if (failVerification) throw new Error('Downloaded bytes differ');
    },
  };
  return { calls, args: {
    tag, build: '101', source: 'a'.repeat(40), runId: '1234', io,
    archive: { path: `dist/${name}`, bytes: Buffer.from('verified archive') },
    appcast: { bytes: Buffer.from(`<sparkle:version>101</sparkle:version><enclosure url="https://github.com/SakuraCordApp/SakuraCord/releases/download/${tag}/${name}" />`) },
  } };
}

test('publication preserves source provenance and verifies downloads before switching the feed', async () => {
  const { calls, args } = publication();
  await publishHotfix(args);
  assert.deepEqual(calls.map(([operation, name]) => [operation, name]), [
    ['preserve', 'SakuraCord.v0.1.6.dmg'],
    ['immutable', 'hotfix-build-101.dmg.backup'],
    ['immutable', 'hotfix-build-101.json'],
    ['replace', 'SakuraCord.v0.1.6.dmg'],
    ['verify', 'SakuraCord.v0.1.6.dmg'],
    ['replace', 'appcast.xml'],
    ['verify', 'appcast.xml'],
  ]);
  const manifest = JSON.parse(calls[2][2]);
  assert.equal(manifest.sourceCommit, args.source);
  assert.equal(manifest.buildNumber, '101');
  assert.equal(manifest.tagName, tag);

  const failed = publication(true);
  await assert.rejects(publishHotfix(failed.args), /Downloaded bytes differ/);
  assert.equal(failed.calls.some(([operation, name]) => operation === 'replace' && name === 'appcast.xml'), false);
});

test('hotfix dispatch excludes release creation and Discord delivery at the workflow boundary', () => {
  const workflow = readFileSync(new URL('../.github/workflows/ci.yml', import.meta.url), 'utf8');
  for (const name of ['Publish or repair GitHub release', 'Send or update the pre-made Discord release announcement']) {
    assert.ok(workflow.includes(`- name: ${name}\n` + '        if: ${{ !inputs.hotfix_commit }}\n'));
  }
});
