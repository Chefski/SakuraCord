# Documentation

Choose the task first. Current contracts live in the linked guide; implementation
and tests provide the exact fields and algorithms. Planned scope and progress
belong in GitHub Issues and milestones, not these documents.

| I need to… | Start here |
| --- | --- |
| Install or build the app | [Root README](../README.md#build-from-source) |
| Run a local/offline build, choose credentials or signing | [Development](DEVELOPMENT.md) |
| Find the model, provider and presentation owner | [Architecture](ARCHITECTURE.md#find-the-owner) |
| Change a Discord request or event | [Protocol baseline](PROTOCOL_BASELINE.md), then its topic guide |
| Choose tests or run focused verification | [Testing](TESTING.md) |
| Diagnose a failure or report a bug | [Troubleshooting](DEVELOPMENT.md#troubleshooting) / [report a problem](DEVELOPMENT.md#report-a-problem) |
| Promote, tag, publish or repair a release | [Releasing](RELEASING.md) |
| Draft release copy | [GitHub notes](RELEASE_NOTES_STYLE.md) / [Discord announcement](DISCORD_RELEASE_ANNOUNCEMENTS_STYLE.md) |
| Find licences or asset provenance | [Third-party notices](THIRD_PARTY_NOTICES.md), [Brand](../Brand/README.md), [DMG sources](../App/Packaging/DMG/SOURCES.md) |

Repository-wide agent instructions live in [AGENTS.md](../AGENTS.md).
Vendored READMEs apply to their upstream components; the
[DaveKit wrapper](../Packages/DaveKit/README.md) identifies the app boundary.
Released `Releases/*.json` files are historical authored copy, not descriptions
of the current checkout.

## Developer and agent bootstrap

Every fresh clone must install the repository-managed Git hooks before its
first commit or push:

```sh
./script/install_git_hooks.sh
git config --local --get core.hooksPath
```

The second command must print `.githooks`. The installer refuses to replace a
different configured hook path; integrate it explicitly rather than bypassing
checks. Before considering a change ready to push, run:

```sh
./script/code_quality.sh check
```

This is the pinned SwiftFormat/SwiftLint policy shared with CI. Pre-commit checks
the staged snapshot; pre-push checks committed tips. Feature branches, including
forks, also validate the merged tree against canonical `nightly`. Conflicts,
unavailable bases and merged-tree failures block the push. Temporary snapshots
leave the checkout, index, branches and `FETCH_HEAD` unchanged.

Canonical `main`/`nightly` and tag pushes validate their committed trees without
a synthetic PR merge; fork branches with those names still get merge validation.
Snapshot checks use that snapshot's pinned policy. A later base change still
requires fresh CI. See Development for broader verification.

## Documentation ownership

| Information | One authoritative home |
| --- | --- |
| Package boundaries, lifecycle, persistence | Architecture |
| Commands, local configuration, troubleshooting | Development; release-specific procedures in Releasing |
| Shared network safety and verification policy | Protocol baseline |
| Feature-family wire contracts and deliberate deviations | Relevant `protocol/` topic |
| Which tests deserve maintenance and how to run them | Testing |
| Protocol rationale and source references | Beside the relevant contract; keep working research notes out of the repository |
| Scope, acceptance criteria, status and progress | GitHub Issues and milestones |

When updating documentation:

- Replace the superseded rule where it is owned; link from other documents.
- Keep code constants and exhaustive inventories in code unless a concise table
  materially helps the reader. Link the owner and representative checks.
- Document decisions, invariants and supported procedures. Avoid describing every
  view arrangement or narrating implementation steps.
- Distinguish static inspection, mocked tests and live observations. Include a
  source version or observation date only when it explains a contract.
- Add a topic only for a durable boundary that cannot fit its existing owner.
  Do not create one implementation journal per feature.
- Check local paths/anchors and changed command examples. Review inbound links
  before renaming headings. Preserve required licences and historical release copy.
- Delete obsolete guidance and research journals; retain only useful technical
  conclusions in the relevant contract.
- Keep personal timezones/locations, machine paths, test-account or server names,
  usage history and capture-session details out of documentation.

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
- Each new report starts one read-only triage and investigation agent on
  GitHub Actions, using GPT-6 Luna and the nightly checkout. It reads the report,
  recent comments, screenshots, and similar reports, then posts one assessment
  with classification, questions, duplicate suggestions, and code findings.
  The hub validates the result before changing issue metadata.
- Rerun with `agent: investigate` or Discord's Manage menu. The label stays
  until the hub applies the result; retry a failed run in Actions.
- `agent: fix` explicitly starts the separate macOS agent, which opens a draft
  pull request against `nightly`. Neither agent merges changes; review their
  output like any contribution.

Use `gh issue list`, `gh issue view`, and `gh api` to read and update issues.
Do not add a repository `ROADMAP.md`. A code match or commit is evidence to
review, not proof that an issue is complete.
