// Build an agent prompt: instructions + the issue (and its comments) as
// clearly delimited untrusted data.
import { execFileSync } from "node:child_process";
import { readFileSync, writeFileSync } from "node:fs";

const [instructionsPath, outputPath] = process.argv.slice(2);
const number = process.env.ISSUE_NUMBER;
const issue = JSON.parse(
  execFileSync("gh", ["issue", "view", number, "--json", "number,title,body,labels,comments"], {
    encoding: "utf8",
    maxBuffer: 20 * 1024 * 1024,
  }),
);
const strip = (text) => String(text ?? "").replace(/<!--[\s\S]*?-->/g, "").slice(0, 12000);
const comments = issue.comments
  .slice(-30)
  .map((comment) => `--- comment by ${comment.author?.login ?? "unknown"} ---\n${strip(comment.body)}`)
  .join("\n\n");
const prompt = `${readFileSync(instructionsPath, "utf8")}

<untrusted-issue number="${issue.number}">
Title: ${issue.title}
Labels: ${issue.labels.map((label) => label.name).join(", ")}

${strip(issue.body)}

${comments}
</untrusted-issue>
`;
writeFileSync(outputPath, prompt);
