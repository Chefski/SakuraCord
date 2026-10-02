# SakuraCord documentation

This directory contains durable repository documentation. It is intentionally
small: implementation details should be discoverable from code and tests, while
planned work and progress belong in the canonical roadmap service.

## Canonical documents

| Document | Purpose |
| --- | --- |
| [Architecture](ARCHITECTURE.md) | Package ownership, runtime boundaries, persistence, plugins, and packaging. |
| [Protocol baseline](PROTOCOL_BASELINE.md) | Current SakuraCord network contracts, safety rules, capability gates, and dated protocol evidence. |
| [Testing](TESTING.md) | Criteria for committed automated tests, test design, and verification without new tests. |
| [Development](DEVELOPMENT.md) | Local setup, launch modes, credentials, commands, and validation. |
| [Releasing](RELEASING.md) | Versioned release workflow, service setup, signing limitations, and recovery. |
| [GitHub release notes style](RELEASE_NOTES_STYLE.md) | Evidence, layout, wording, and review rules for detailed GitHub release notes. |
| [Discord release announcement style](DISCORD_RELEASE_ANNOUNCEMENTS_STYLE.md) | Concise user-facing announcement structure and generated Discord framing. |
| [Third-party notices](THIRD_PARTY_NOTICES.md) | Attribution and license notices that must remain with the repository. |

The root [README](../README.md) is the public project entry point.
Repository-wide agent rules live in [AGENTS.md](../AGENTS.md).

## Developer and agent bootstrap

Every fresh clone must install the repository-managed Git hooks before its
first commit or push:

```sh
./script/install_git_hooks.sh
git config --local --get core.hooksPath
```

The second command must print `.githooks`. This setup applies to developers and
coding agents. The installer is safe to rerun, but deliberately refuses to
replace a different existing hooks path; integrate that hook configuration
explicitly instead of bypassing the repository pre-commit and pre-push checks.

Before a change is considered ready to push, run:

```sh
./script/code_quality.sh check
```

That command is the pinned SwiftFormat and SwiftLint path shared by local
development, both Git hooks, and CI. Pre-commit validates the exact staged
index snapshot; pre-push independently validates the committed ref tips. See
the [development guide](DEVELOPMENT.md) for launch modes and broader validation.

## Roadmap

The deployed roadmap service is the only source of truth for planned work,
lifecycle state, acceptance criteria, verification, research gaps, and linked
Discord discussions. Use the
[Roadmap Management plugin](plugin://roadmap-management@personal) instead of
adding or updating a repository `ROADMAP.md`.

Roadmap state is revisioned independently of Git. A code match or commit is
evidence to review, not proof that a roadmap item is complete.

## Documentation policy

- Update an existing canonical document when a change alters a durable
  repository-wide contract.
- Put feature status, acceptance criteria, research, and verification on the
  canonical roadmap item.
- Put narrow, time-bound implementation evidence in the pull request or commit
  description. Update `PROTOCOL_BASELINE.md` only when it establishes or
  supersedes a repository-wide network baseline.
- Do not add one Markdown implementation journal per feature. Create a new
  document only for a durable cross-cutting workflow, architecture boundary,
  or legal requirement that does not fit an existing document.
- Date observations and name their evidence. Do not present an old client
  build, benchmark, or live verification as current.
- Prefer deleting obsolete documentation over leaving a tombstone that agents
  may treat as current.

Adjacent asset inventories under `Brand/`, packaging attribution under
`App/Packaging/`, and vendored dependency READMEs under `Packages/DaveKit/` are
scoped to their own directories and are not SakuraCord planning documents.

## Community reports and agents

The issue hub syncs reports and comments between GitHub, Discord, and the
website. Each new report starts one read-only **triage and investigation**
agent on GitHub Actions, using GPT-6 Luna against the nightly checkout. It
reads the report, recent discussion, screenshot evidence, and similar reports,
then posts one assessment with classification, questions, duplicate suggestions,
and code findings. The hub validates that result before changing issue metadata.
Both bugs and suggestions require the latest published nightly or regular release.
The agent can correct either category and considers closed reports as duplicates.
It compares the reported release with source and verifies fix-commit ancestry:
fixed in code, published in nightly, and published in regular are distinct states.
A build already containing a claimed fix is investigated as a possible regression.
Verified existing fixes join the hub's release tracking; unreleased fixes stay open.

Maintainers can rerun it with `agent: investigate` or Discord's Manage menu.
The label stays until the hub applies the result; retry a failed run in Actions.
`agent: fix` remains a separate, explicitly triggered agent on the macOS runner
that opens a draft PR against nightly. Neither agent merges changes.
