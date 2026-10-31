import test from 'node:test';
import assert from 'node:assert/strict';
import { generateKeyPairSync, createPublicKey, verify } from 'node:crypto';
import { validateOrigin, signingKey, signedAppcast, mergeCatalog, distributionRelease, latestBuildsByPullRequest,
  discardFailedDraftUploads, openPullRequestCatalog, resolvePullRequest, validateBuiltCommit, verifyCIJobs, SOURCE, DISTRIBUTION } from './pr_builds.mjs';

const head = 'a'.repeat(40), base = 'b'.repeat(40), merge = 'c'.repeat(40);
function fixture(fork = false) {
  const metadata = { schemaVersion: 1, id: 'pr-7-run-99-attempt-2', pullRequest: 7,
    runID: 99, runAttempt: 2, headSHA: head, baseSHA: base, builtSHA: merge,
    configuration: 'debug', architecture: 'arm64' };
  const run = { id: 99, run_attempt: 2, workflow_id: 4, repository: { id: 1, full_name: SOURCE },
    run_started_at: '2026-10-09T10:00:00Z', updated_at: '2026-10-09T10:10:00Z',
    path: '.github/workflows/ci.yml', event: 'pull_request', status: 'completed', conclusion: 'success',
    head_sha: head, head_repository: { id: fork ? 2 : 1 }, pull_requests: [{ number: 7, head: { sha: head, repo: { id: fork ? 2 : 1 } }, base: { sha: base } }] };
  const artifact = { created_at: '2026-10-09T10:09:00Z', name: 'pr-build-99-2', expired: false, workflow_run: { id: 99, head_sha: head, head_repository_id: fork ? 2 : 1 } };
  return [run, artifact, metadata, 4];
}

test('publication binds repository, successful CI workflow, run attempt, artifact and PR commits', () => {
  assert.equal(validateOrigin(...fixture()).id, 'pr-7-run-99-attempt-2');
  for (const mutate of [
    ([run]) => { run.repository.full_name = 'attacker/SakuraCord'; },
    ([run]) => { run.workflow_id = 8; },
    ([run]) => { run.conclusion = 'failure'; },
    ([run]) => { run.event = 'push'; },
    ([, artifact]) => { artifact.workflow_run.head_sha = merge; },
    ([, artifact]) => { artifact.expired = true; },
    ([, artifact]) => { artifact.created_at = '2026-10-09T09:59:59Z'; },
    ([, artifact]) => { artifact.created_at = '2026-10-09T10:10:01Z'; },
    ([,, metadata]) => { metadata.runAttempt = 1; },
    ([,, metadata]) => { metadata.headSHA = merge; },
    ([,, metadata]) => { metadata.baseSHA = 'invalid'; },
    ([,, metadata]) => { metadata.id = 'pr-8-run-99-attempt-2'; },
  ]) {
    const input = fixture(); mutate(input); assert.throws(() => validateOrigin(...input));
  }
});

test('fork builds publish automatically while retaining immutable commit provenance', () => {
  assert.equal(validateOrigin(...fixture(true)).fork, true);
  const moved = fixture(true); moved[0].head_sha = base; moved[1].workflow_run.head_sha = base;
  assert.throws(() => validateOrigin(...moved), /PR commit provenance mismatch/);
  moved[2].headSHA = base;
  assert.equal(validateOrigin(...moved).headSHA, base);
  // GitHub updates the associated PR summary after a new push. The run's
  // immutable head_sha still identifies the earlier build during recovery.
  const historical = fixture(true); historical[0].pull_requests[0].head.sha = base;
  assert.equal(validateOrigin(...historical).headSHA, head);
});

test('missing fork run summaries require the exact PR repository and current or historical commit', async () => {
  const [run,, metadata] = fixture(true);
  const pr = run.pull_requests[0];
  run.pull_requests = [];
  let commits = [];
  const request = async (repo, endpoint) => {
    assert.equal(repo, SOURCE);
    if (endpoint === 'pulls/7') return pr;
    assert.equal(endpoint, 'pulls/7/commits?per_page=100&page=1');
    return commits;
  };
  assert.equal(await resolvePullRequest(run, metadata, request), pr);
  pr.head.sha = base;
  await assert.rejects(resolvePullRequest(run, metadata, request), /CI commit is not part/);
  commits = [{ sha: head }];
  assert.equal(await resolvePullRequest(run, metadata, request), pr);
  pr.head.repo.id = 3;
  await assert.rejects(resolvePullRequest(run, metadata, request), /PR repository provenance mismatch/);
});

test('refreshed PR merges require the exact head and forward ancestry on the canonical target', async () => {
  const [, , context] = fixture();
  const newerBase = 'd'.repeat(40), target = 'e'.repeat(40);
  const pr = { base: { sha: base, ref: 'nightly', repo: { full_name: SOURCE } } };
  const commit = { sha: merge, parents: [{ sha: newerBase }, { sha: head }] };
  let status = 'ahead';
  const seen = [];
  const request = async (repo, endpoint) => {
    assert.equal(repo, SOURCE);
    seen.push(endpoint);
    if (endpoint === `commits/${merge}`) return commit;
    if (endpoint === 'branches/nightly') return { commit: { sha: target } };
    assert.ok([`compare/${base}...${newerBase}`, `compare/${newerBase}...${target}`].includes(endpoint));
    return { status, merge_base_commit: { sha: endpoint.slice(8).split('...')[0] } };
  };
  assert.equal(await validateBuiltCommit(context, pr, request), commit);
  assert.equal(seen.length, 4);
  status = 'diverged';
  await assert.rejects(validateBuiltCommit(context, pr, request), /not a forward update/);
  status = 'ahead';
  pr.base.repo.full_name = 'attacker/repo';
  await assert.rejects(validateBuiltCommit(context, pr, request), /Invalid PR base repository/);
  pr.base.repo.full_name = SOURCE;
  commit.parents[1].sha = base;
  await assert.rejects(validateBuiltCommit(context, pr, request), /recorded PR head/);
  commit.parents = [{ sha: base }, { sha: head }];
  assert.equal(await validateBuiltCommit(context, pr, request), commit);
});

test('CI verification waits for delayed step records but rejects failed, skipped and foreign jobs', async () => {
  const steps = ['Build and test', 'Package downloadable pull request app and matching symbols', 'Upload pull request build'];
  const jobs = ['packages', 'app', 'protocol', 'media'].map(suite => ({
    name: `build (${suite})`, run_id: 99, run_attempt: 2, conclusion: 'success',
    steps: (suite === 'app' ? steps : steps.slice(0, 1)).map(name => ({ name, conclusion: 'success' })),
  }));
  let reads = 0, waits = 0;
  const request = async (_repo, endpoint) => {
    assert.equal(endpoint, 'actions/runs/99/attempts/2/jobs?per_page=100&page=1');
    reads++;
    return { jobs: reads === 1 ? [] : reads === 2 ? jobs.map(job => ({ ...job, steps: [] })) : jobs };
  };
  await verifyCIJobs(99, 2, request, async () => { waits++; });
  assert.equal(waits, 2);
  for (const conclusion of ['failure', 'skipped', 'cancelled']) {
    jobs[2].steps[0].conclusion = conclusion;
    await assert.rejects(verifyCIJobs(99, 2, request), /CI step did not pass/);
  }
  jobs[2].steps[0].conclusion = 'success';
  jobs[2].run_attempt = 1;
  await assert.rejects(verifyCIJobs(99, 2, request), /run\/attempt mismatch/);
  jobs[2].run_attempt = 2;
  waits = 0;
  await assert.rejects(verifyCIJobs(99, 2, async () => ({ jobs: [] }), async () => { waits++; }), /still incomplete/);
  assert.equal(waits, 19);
});

test('Sparkle archive and feed signatures bind bytes and XML escapes untrusted PR titles', () => {
  const pair = generateKeyPairSync('ed25519');
  const seed = pair.privateKey.export({ type: 'pkcs8', format: 'der' }).subarray(-32).toString('base64');
  const pub = pair.publicKey.export({ type: 'spki', format: 'der' }).subarray(-32).toString('base64');
  const key = signingKey(seed, pub);
  assert.throws(() => signingKey(seed, Buffer.alloc(32).toString('base64')), /does not match/);
  const archive = Buffer.from('archive bytes');
  const feed = signedAppcast({ title: '<![CDATA[</title>]]>', pullRequest: 7, headSHA: head, id: 'test',
    createdAt: '2026-10-09T00:00:00Z', buildVersion: '4000000000000099002', version: '0.1.5',
    archiveURL: 'https://github.com/SakuraCordApp/Builds/releases/download/test/SakuraCord.app.zip' }, archive, key);
  const marker = feed.indexOf('<!-- sparkle-signatures:\n');
  const body = feed.subarray(0, marker);
  const signature = /\nedSignature: (\S+)/.exec(feed.toString())[1];
  assert.equal(verify(null, body, createPublicKey(key), Buffer.from(signature, 'base64')), true);
  assert.match(body.toString(), /&lt;!\[CDATA\[/);
  assert.equal(Number(/\nlength: (\d+)/.exec(feed.toString())[1]), body.length);
  const archiveSignature = /sparkle:edSignature="([^"]+)"/.exec(body.toString())[1];
  assert.equal(verify(null, archive, pair.publicKey, Buffer.from(archiveSignature, 'base64')), true);
  assert.equal(verify(null, Buffer.from('tampered'), pair.publicKey, Buffer.from(archiveSignature, 'base64')), false);
});

test('catalog retries preserve immutable identity and retain earlier builds', () => {
  const first = { id: 'first', runID: 1, runAttempt: 1, sha256: 'old' };
  let catalog = mergeCatalog({ schemaVersion: 1, builds: [] }, first);
  assert.deepEqual(mergeCatalog(catalog, first), catalog);
  assert.throws(() => mergeCatalog(catalog, { ...first, sha256: 'changed' }), /Conflicting/);
  catalog = mergeCatalog(catalog, { id: 'second', runID: 2, runAttempt: 1 });
  assert.deepEqual(catalog.builds.map(x => x.id), ['second', 'first']);
});

test('discovery follows open PRs across pages and close/reopen without discarding build history', async () => {
  const catalog = { schemaVersion: 1, builds: [
    { id: 'open-latest', pullRequest: 101 }, { id: 'closed', pullRequest: 102 },
    { id: 'merged', pullRequest: 103 }, { id: 'open-old', pullRequest: 101 },
  ] };
  const original = structuredClone(catalog);
  let open = [{ number: 101 }];
  const request = async (repo, endpoint) => {
    assert.equal(repo, SOURCE);
    if (endpoint === 'pulls?state=open&per_page=100&page=1') {
      return Array.from({ length: 100 }, (_, index) => ({ number: index + 1 }));
    }
    assert.equal(endpoint, 'pulls?state=open&per_page=100&page=2');
    return open;
  };
  assert.deepEqual((await openPullRequestCatalog(catalog, request)).builds.map(x => x.id), ['open-latest', 'open-old']);
  open = [];
  assert.deepEqual((await openPullRequestCatalog(catalog, request)).builds, []);
  open = [{ number: 102 }];
  assert.deepEqual((await openPullRequestCatalog(catalog, request)).builds.map(x => x.id), ['closed']);
  assert.deepEqual(catalog, original);
  await assert.rejects(openPullRequestCatalog(catalog, async () => { throw new Error('GitHub unavailable'); }), /GitHub unavailable/);
});

test('publication retries resume the unique draft without changing its manifest or assets', async () => {
  for (const tag of ['pr-7-run-99-attempt-2', 'pr-7', 'pr-builds']) {
    const draft = { id: 42, tag_name: tag, draft: true, prerelease: true,
      assets: [{ id: 9, name: tag === 'pr-builds' ? 'catalog.json' : 'build.json' }] };
    const original = structuredClone(draft);
    const requests = [];
    const request = async (repo, endpoint, options) => {
      assert.equal(repo, DISTRIBUTION);
      assert.deepEqual(options, { token: 'test-token' }); // No POST, PATCH, or DELETE.
      requests.push(endpoint);
      if (endpoint === `releases/tags/${tag}`) return null;
      if (endpoint === 'releases?per_page=100&page=1') {
        return Array.from({ length: 100 }, (_, i) => ({ id: i + 100, tag_name: `other-${i}`, draft: true }));
      }
      assert.equal(endpoint, 'releases?per_page=100&page=2');
      return [draft];
    };
    assert.equal(await distributionRelease(tag, 'test-token', request), draft);
    assert.deepEqual(draft, original);
    assert.equal(requests.length, 3);

    await assert.rejects(distributionRelease(tag, 'test-token', async (_repo, endpoint, options) => {
      assert.deepEqual(options, { token: 'test-token' });
      return endpoint.startsWith('releases/tags/') ? null : [draft, { ...draft, id: 43 }];
    }), /Ambiguous draft releases/);
  }
});

test('PR tracks choose the latest run and attempt without rolling back on an old publication retry', () => {
  const old = { id: 'old', pullRequest: 7, runID: 99, runAttempt: 9 };
  const current = { id: 'current', pullRequest: 7, runID: 100, runAttempt: 1 };
  const rerun = { ...current, id: 'rerun', runAttempt: 2 };
  const other = { id: 'other', pullRequest: 8, runID: 101, runAttempt: 1 };
  let catalog = { schemaVersion: 1, builds: [other, rerun, old, current] };
  assert.deepEqual(latestBuildsByPullRequest(catalog).map(build => build.id), ['other', 'rerun']);
  catalog = mergeCatalog(catalog, old);
  assert.deepEqual(latestBuildsByPullRequest(catalog).map(build => build.id), ['other', 'rerun']);
  assert.equal(catalog.builds.length, 4); // Immutable history remains available.
  assert.deepEqual(latestBuildsByPullRequest({ builds: [] }), []);
});

test('interrupted draft uploads discard only empty starter reservations', async () => {
  const calls = [];
  const request = async (_repo, endpoint, options) => {
    calls.push([endpoint, options]);
    return endpoint.includes('/assets?') ? [
      { id: 1, name: 'build.json', state: 'starter', size: 0 },
      { id: 2, name: 'SakuraCord.app.zip', state: 'uploaded', size: 200 },
      { id: 3, name: 'unexpected', state: 'starter', size: 20 },
      { id: 4, name: 'empty-complete', state: 'uploaded', size: 0 },
    ] : null;
  };
  await discardFailedDraftUploads({ id: 42, draft: true }, 'token', request);
  assert.deepEqual(calls, [
    ['releases/42/assets?per_page=100&page=1', { token: 'token' }],
    ['releases/assets/1', { method: 'DELETE', token: 'token' }],
  ]);
  calls.length = 0;
  await discardFailedDraftUploads({ id: 42, draft: false }, 'token', request);
  assert.deepEqual(calls, []);
});
