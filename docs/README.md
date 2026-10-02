# SakuraCord documentation

This directory contains durable repository documentation. It is intentionally
small: implementation details should be discoverable from code and tests, while
planned work and progress belong in GitHub Issues and milestones.

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

For feature-branch pushes, including pushes to forks, pre-push also fetches
current `nightly` from the canonical repository and checks the merged tree
that PR CI will build. Merge conflicts, an unavailable base, or merged-tree
quality failures block the push. This uses temporary snapshots and a temporary
Git ref, leaving the checkout, index, branches, and `FETCH_HEAD` unchanged.
Direct pushes to the canonical repository's `main`/`nightly`, and tag pushes,
validate their committed trees without a synthetic PR merge. Fork branches
named `main` or `nightly` still receive merge validation. Snapshot checks use
the snapshot's own pinned tools and policy. A later base-branch change can
still require fresh CI validation.

## Issues and roadmap

GitHub Issues in this repository are the single source of truth for bugs,
suggestions, and planned work. The
[SakuraCord hub](https://github.com/SakuraCordApp/Roadmap) keeps every issue in
sync with its Discord forum post and
[sakuracord.app/tracker](https://sakuracord.app/tracker), including comments,
so discuss and update an issue in whichever place is convenient.

- Status is one `status: …` label (New, Needs Info, Confirmed, Planned,
  In Progress, In Nightly, Shipped, Declined, Can't Reproduce) or the close
  reason. Area and priority are `area: …` and `priority: …` labels; the issue
  type is Bug or Feature.
- Versions are milestones. A milestone's description is its roadmap entry: a
  headline line, an optional summary, then `- highlight (#N)` bullets. Assigning
  a milestone makes an issue Planned.
- Write `Fixes #N` in pull requests and nightly commits. An open PR moves the
  issue to In Progress, landing on `nightly` moves it to In Nightly, and the
  first release whose tag contains the fix closes it as Shipped and pings
  everyone following it.
- `agent: investigate` asks an agent to locate the cause and post findings;
  `agent: fix` asks an agent to open a draft pull request against `nightly`.
  Review agent output like any contribution.

Use `gh issue list`, `gh issue view`, and `gh api` to read and update issues.
Do not add a repository `ROADMAP.md`. A code match or commit is evidence to
review, not proof that an issue is complete.

## Documentation policy

- Update an existing canonical document when a change alters a durable
  repository-wide contract.
- Put feature status, acceptance criteria, research, and verification on the
  GitHub issue.
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
