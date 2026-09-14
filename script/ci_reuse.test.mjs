import assert from 'node:assert/strict';
import test from 'node:test';
import { findCache, findValidation, fullValidation, trustedRun } from './ci_reuse.mjs';

const repository = 'SakuraCordApp/SakuraCord';
const sha = 'a'.repeat(40);
const run = {
  id: 123, run_attempt: 2, head_sha: sha, head_branch: 'nightly', event: 'push',
  status: 'completed', conclusion: 'success', path: '.github/workflows/ci.yml',
  repository: { full_name: repository }, head_repository: { full_name: repository },
};
const jobs = [{ name: 'build', conclusion: 'success', steps: [
  { name: 'Build and test', status: 'completed', conclusion: 'success' },
  { name: 'Verify checked-out commit', status: 'completed', conclusion: 'success' },
] }];

test('only successful first-party branch pushes can supply full validation', () => {
  assert.equal(trustedRun(run, repository), true);
  for (const change of [
    { event: 'pull_request' }, { event: 'workflow_dispatch' }, { head_branch: 'feature' },
    { status: 'in_progress' }, { conclusion: 'failure' }, { conclusion: 'cancelled' },
    { path: '.github/workflows/other.yml' }, { repository: { full_name: 'fork/repo' } },
    { head_repository: { full_name: 'fork/repo' } },
  ]) assert.equal(trustedRun({ ...run, ...change }, repository), false, JSON.stringify(change));
});

test('a green workflow with skipped tests or checks-only work is not validation', () => {
  assert.equal(fullValidation(jobs), true);
  assert.equal(fullValidation([{ ...jobs[0], conclusion: 'skipped' }]), false);
  assert.equal(fullValidation([{ ...jobs[0], steps: [{ ...jobs[0].steps[0], conclusion: 'skipped' }] }]), false);
  assert.equal(fullValidation([{ ...jobs[0], steps: [{ ...jobs[0].steps[0], name: 'Validate release sources' }] }]), false);
});

test('validation requires the exact SHA and inspects the successful attempt', async () => {
  const calls = [];
  const api = async path => {
    calls.push(path);
    return path.includes('/jobs?') ? { jobs } : { workflow_runs: [
      { ...run, id: 120, head_sha: 'b'.repeat(40) },
      { ...run, id: 121, event: 'pull_request' },
      { ...run, id: 999 }, run,
    ] };
  };
  assert.equal((await findValidation({ api, repository, sha, currentRun: 999 })).id, 123);
  assert.equal(calls.length, 2);
  assert.match(calls[1], /runs\/123\/attempts\/2\/jobs/);
});

test('missing qualifying validation leaves the full suite required', async () => {
  for (const entries of [[], [{ ...run, head_sha: 'b'.repeat(40) }], [run]]) {
    const api = async path => path.includes('/jobs?') ? { jobs: [] } : { workflow_runs: entries };
    assert.equal(await findValidation({ api, repository, sha, currentRun: 999 }), null);
  }
  await assert.rejects(findValidation({ api: async () => { throw new Error('API unavailable'); },
    repository, sha, currentRun: 999 }));
});

test('release caches require successful release tag pushes', () => {
  assert.equal(trustedRun({ ...run, head_branch: 'v0.1.5-Beta-8' }, repository, 'release'), true);
  assert.equal(trustedRun({ ...run, head_branch: 'v0.1.5' }, repository, 'release'), true);
  assert.equal(trustedRun(run, repository, 'release'), false);
  assert.equal(trustedRun({ ...run, head_branch: 'v-malformed' }, repository, 'release'), false);
});

test('cache selection rejects expired, wrong-key, foreign, and unrelated sources', async () => {
  const key = 'swiftpm-v1-debug-compatible';
  const artifact = { id: 1, name: key, expired: false, workflow_run: { id: 123, head_sha: sha } };
  for (const change of [
    { expired: true }, { name: 'different-toolchain' }, { workflow_run: { id: 999, head_sha: sha } },
    { workflow_run: { id: 123, head_sha: 'b'.repeat(40) } },
  ]) {
    const api = async path => path.includes('/artifacts?') ? { artifacts: [{ ...artifact, ...change }] } : run;
    assert.equal(await findCache({ api, repository, key, configuration: 'debug', currentRun: 999,
      isAncestor: () => true }), null);
  }
  for (const source of [run, { ...run, event: 'pull_request' }]) {
    const api = async path => path.includes('/artifacts?') ? { artifacts: [artifact] } : source;
    assert.equal(await findCache({ api, repository, key, configuration: 'debug', currentRun: 999,
      isAncestor: () => false }), null);
  }
  const api = async path => path.includes('/artifacts?') ? { artifacts: [artifact] } : run;
  const match = await findCache({ api, repository, key, configuration: 'debug', currentRun: 999,
    isAncestor: candidate => candidate === sha });
  assert.equal(match.artifact.id, 1);
});
