// Post (or update) the investigation comment on the issue.
import { execFileSync } from "node:child_process";
import { readFileSync, writeFileSync } from "node:fs";

const number = process.env.ISSUE_NUMBER;
const repo = process.env.GITHUB_REPOSITORY;
const sha = process.env.SOURCE_SHA;
const run = `${process.env.GITHUB_SERVER_URL}/${repo}/actions/runs/${process.env.GITHUB_RUN_ID}`;
const result = JSON.parse(readFileSync(process.env.RESULT_PATH, "utf8"));
const clean = (text) => String(text ?? "").replace(/@(?=[A-Za-z0-9-])/g, "@​").trim();
const locations = result.locations
  .filter((location) => /^[\w./ -]+$/.test(location.path))
  .map(
    (location) =>
      `- [\`${location.path}:${location.line}\`](https://github.com/${repo}/blob/${sha}/${location.path.split("/").map(encodeURIComponent).join("/")}#L${location.line}) — ${clean(location.reason)}`,
  )
  .join("\n");
const body = `<!-- sakuracord:investigation -->
### Summary
${clean(result.summary)}

### Likely locations
${locations || "_No specific location identified._"}

### Probable cause
${clean(result.cause)}

### Suggested fix
${clean(result.suggestedFix)}

### Suggested test
${clean(result.suggestedTest)}

<sub>🔎 Investigation agent · confidence **${result.confidence}** · ${result.fixable ? "looks fixable — a maintainer can add the `agent: fix` label to open a draft PR" : "probably needs a maintainer"} · [run](${run}) · based on \`${sha.slice(0, 7)}\` (nightly)</sub>`;
writeFileSync("comment.md", body);
const existing = execFileSync(
  "gh",
  [
    "api",
    `repos/${repo}/issues/${number}/comments`,
    "--paginate",
    "--jq",
    '.[] | select(.body | startswith("<!-- sakuracord:investigation -->")) | .id',
  ],
  { encoding: "utf8" },
)
  .split("\n")
  .filter(Boolean);
if (existing.length) {
  execFileSync("gh", ["api", "-X", "PATCH", `repos/${repo}/issues/comments/${existing[existing.length - 1]}`, "-F", "body=@comment.md"], { stdio: "inherit" });
} else {
  execFileSync("gh", ["issue", "comment", number, "--body-file", "comment.md"], { stdio: "inherit" });
}
