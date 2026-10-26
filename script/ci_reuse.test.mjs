import assert from 'node:assert/strict';
import { execFileSync } from 'node:child_process';
import { mkdirSync, mkdtempSync, readFileSync, rmSync, statSync, utimesSync, writeFileSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import test from 'node:test';
import { fileURLToPath } from 'node:url';
import { canRestoreCompilerCache, findCache, findValidation, fullValidation, suites, trustedRun } from './ci_reuse.mjs';

const repository = 'SakuraCordApp/SakuraCord';
const sha = 'a'.repeat(40);
const run = {
  id: 123, run_attempt: 2, head_sha: sha, head_branch: 'nightly', event: 'push',
  status: 'completed', conclusion: 'success', path: '.github/workflows/ci.yml',
  repository: { full_name: repository }, head_repository: { full_name: repository },
};
const jobs = suites.map(suite => ({ name: `build (${suite})`, conclusion: 'success', steps: [
  { name: 'Build and test', status: 'completed', conclusion: 'success' },
  { name: 'Verify checked-out commit', status: 'completed', conclusion: 'success' },
  { name: 'Record clean compilation', status: 'completed', conclusion: 'success' },
] }));

test('compiler archives preserve exact fractional output timestamps after extraction', t => {
  const directory = mkdtempSync(join(tmpdir(), 'sakuracord-compiler-archive-'));
  t.after(() => rmSync(directory, { recursive: true, force: true }));
  const outputs = join(directory, 'App/.build/out');
  mkdirSync(outputs, { recursive: true });
  const object = join(outputs, 'fixture.o');
  writeFileSync(object, 'compiled output');
  utimesSync(object, 1700000000.123456, 1700000000.123456);
  const expectedTimestamp = statSync(object, { bigint: true }).mtimeNs;
  assert.notEqual(expectedTimestamp % 1_000_000_000n, 0n);

  execFileSync(process.execPath, [fileURLToPath(new URL('./ci_reuse.mjs', import.meta.url)), 'archive', 'app'], {
    cwd: directory,
    env: { ...process.env, GITHUB_REPOSITORY: repository, GITHUB_RUN_ID: '999', RUNNER_TEMP: directory },
  });
  rmSync(outputs, { recursive: true });
  execFileSync('tar', ['-xf', join(directory, 'swiftpm-app.tar')], { cwd: directory });

  assert.equal(readFileSync(object, 'utf8'), 'compiled output');
  assert.equal(statSync(object, { bigint: true }).mtimeNs, expectedTimestamp);
});

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
  for (const job of jobs) {
    assert.equal(fullValidation(jobs.map(item => item === job ? { ...item, conclusion: 'skipped' } : item)), false);
    for (const step of job.steps) {
      const changed = { ...job, steps: job.steps.map(item => item === step ? { ...item, conclusion: 'skipped' } : item) };
      assert.equal(fullValidation(jobs.map(item => item === job ? changed : item)), false);
    }
  }
});

test('validation requires every build suite', () => {
  for (const job of jobs) assert.equal(fullValidation(jobs.filter(item => item !== job)), false);
  assert.equal(fullValidation(jobs.filter(job => ['build (packages)', 'build (app)'].includes(job.name))), false);
});

test('incremental branch validation cannot substitute for clean release validation', () => {
  const incremental = jobs.map(job => ({ ...job, steps: job.steps.filter(step => step.name !== 'Record clean compilation') }));
  assert.equal(fullValidation(incremental), false);
  for (const suite of suites) {
    assert.equal(canRestoreCompilerCache(suite, 'pull_request', 'refs/pull/1/merge'), true);
    for (const branch of ['main', 'nightly']) {
      assert.equal(canRestoreCompilerCache(suite, 'push', `refs/heads/${branch}`), true);
    }
    assert.equal(canRestoreCompilerCache(suite, 'push', 'refs/tags/v0.1.5'), false);
    assert.equal(canRestoreCompilerCache(suite, 'workflow_dispatch', 'refs/heads/main'), false);
  }
  assert.equal(canRestoreCompilerCache('release', 'push', 'refs/tags/v0.1.5'), true);
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
  const key = 'swiftpm-v1-app-compatible';
  const artifact = { id: 1, name: key, expired: false, workflow_run: { id: 123, head_sha: sha } };
  for (const change of [
    { expired: true }, { name: 'different-toolchain' }, { workflow_run: { id: 999, head_sha: sha } },
    { workflow_run: { id: 123, head_sha: 'b'.repeat(40) } },
  ]) {
    const api = async path => path.includes('/artifacts?') ? { artifacts: [{ ...artifact, ...change }] } : run;
    assert.equal(await findCache({ api, repository, key, configuration: 'app', currentRun: 999,
      isAncestor: () => true }), null);
  }
  for (const source of [run, { ...run, event: 'pull_request' }]) {
    const api = async path => path.includes('/artifacts?') ? { artifacts: [artifact] } : source;
    assert.equal(await findCache({ api, repository, key, configuration: 'app', currentRun: 999,
      isAncestor: () => false }), null);
  }
  const api = async path => path.includes('/artifacts?') ? { artifacts: [artifact] } : run;
  const match = await findCache({ api, repository, key, configuration: 'app', currentRun: 999,
    isAncestor: candidate => candidate === sha });
  assert.equal(match.artifact.id, 1);
});
