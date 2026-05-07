---
allowed-tools: Bash(gh issue view:*), Bash(gh search:*), Bash(gh issue list:*), Bash(gh pr comment:*), Bash(gh pr diff:*), Bash(gh pr view:*), Bash(gh pr list:*), Bash(gh api:*)
description: PR のコードレビューを実行する
disable-model-invocation: false
---

**重要: このコマンド内のすべての出力・エージェントへの指示・GitHubへのレビューコメントは日本語で記述すること。**

Provide a code review for the given pull request.

To do this, follow these steps precisely:

1. Use a Haiku agent to check if the pull request (a) is closed, (b) is a draft, (c) does not need a code review (eg. because it is an automated pull request, or is very simple and obviously ok), or (d) already has a code review from you from earlier. If so, do not proceed.
2. Use another Haiku agent to give you a list of file paths to (but not the contents of) any relevant CLAUDE.md files from the codebase: the root CLAUDE.md file (if one exists), as well as any CLAUDE.md files in the directories whose files the pull request modified
3. Use a Haiku agent to view the pull request, and ask the agent to return a summary of the change
4. Then, launch 5 parallel Sonnet agents to independently code review the change. All agents must write their findings in Japanese. The agents should do the following, then return a list of issues. For each issue, return: `file` (ファイルパス), `line` (該当行番号), `description` (指摘内容), `reason` (eg. CLAUDE.md 違反、バグ、履歴的文脈等):
   a. Agent #1: Audit the changes to make sure they comply with the CLAUDE.md. Note that CLAUDE.md is guidance for Claude as it writes code, so not all instructions will be applicable during code review.
   b. Agent #2: Read the file changes in the pull request, then do a shallow scan for obvious bugs. Avoid reading extra context beyond the changes, focusing just on the changes themselves. Focus on large bugs, and avoid small issues and nitpicks. Ignore likely false positives.
   c. Agent #3: Read the git blame and history of the code modified, to identify any bugs in light of that historical context
   d. Agent #4: Read previous pull requests that touched these files, and check for any comments on those pull requests that may also apply to the current pull request.
   e. Agent #5: Read code comments in the modified files, and make sure the changes in the pull request comply with any guidance in the comments.
5. For each issue found in #4, launch a parallel Haiku agent that takes the PR, issue description, and list of CLAUDE.md files (from step 2), and returns a score to indicate the agent's level of confidence for whether the issue is real or false positive. To do that, the agent should score each issue on a scale from 0-100, indicating its level of confidence. For issues that were flagged due to CLAUDE.md instructions, the agent should double check that the CLAUDE.md actually calls out that issue specifically. The scale is (give this rubric to the agent verbatim):
   a. 0: Not confident at all. This is a false positive that doesn't stand up to light scrutiny, or is a pre-existing issue.
   b. 25: Somewhat confident. This might be a real issue, but may also be a false positive. The agent wasn't able to verify that it's a real issue. If the issue is stylistic, it is one that was not explicitly called out in the relevant CLAUDE.md.
   c. 50: Moderately confident. The agent was able to verify this is a real issue, but it might be a nitpick or not happen very often in practice. Relative to the rest of the PR, it's not very important.
   d. 75: Highly confident. The agent double checked the issue, and verified that it is very likely it is a real issue that will be hit in practice. The existing approach in the PR is insufficient. The issue is very important and will directly impact the code's functionality, or it is an issue that is directly mentioned in the relevant CLAUDE.md.
   e. 100: Absolutely certain. The agent double checked the issue, and confirmed that it is definitely a real issue, that will happen frequently in practice. The evidence directly confirms this.
6. Filter out any issues with a score less than 80. If there are no issues that meet this criteria, do not proceed.
7. Use a Haiku agent to repeat the eligibility check from #1, to make sure that the pull request is still eligible for code review.
8. Finally, post the review to GitHub using the Review API with inline comments per issue:
   a. Get the PR head commit SHA: `gh pr view --json headRefOid --jq '.headRefOid'`
   b. Get PR number: `gh pr view --json number --jq '.number'`
   c. Get repo info: `gh repo view --json nameWithOwner --jq '.nameWithOwner'` (format: OWNER/REPO)
   d. For each issue, determine:
      - `path`: ファイルパス（リポジトリルートからの相対パス）
      - `line`: 該当行番号（PR の差分内の行。差分外の行はインラインコメント不可）
      - `body`: 1〜2文の日本語指摘。参照コードや CLAUDE.md があればリンクを含める
   e. 差分外の行に紐づく指摘（またはファイル全体に関わる指摘）はインラインコメントにせず、サマリ本文に含める
   f. 以下の形式で JSON ファイルを生成し `gh api` で投稿する:

```bash
cat > /tmp/pr-review-payload.json << 'ENDJSON'
{
  "commit_id": "<HEAD_SHA>",
  "body": "### コードレビュー\n\nN 件の指摘があります。\n\n<差分外の指摘があればここに記載>\n\n🤖 Generated with [Claude Code](https://claude.ai/code)\n\n<sub>役に立った場合は 👍、そうでない場合は 👎 をリアクションしてください。</sub>",
  "event": "COMMENT",
  "comments": [
    {
      "path": "src/example.ts",
      "line": 42,
      "side": "RIGHT",
      "body": "日本語の指摘内容。[参照リンク](https://github.com/...)"
    }
  ]
}
ENDJSON
gh api repos/OWNER/REPO/pulls/PR_NUM/reviews --method POST --input /tmp/pr-review-payload.json
```

   g. 指摘が 0 件の場合は `gh pr comment` で以下を投稿して終了:

```
### コードレビュー

指摘事項なし。バグおよび CLAUDE.md 準拠を確認しました。

🤖 Generated with [Claude Code](https://claude.ai/code)
```

Examples of false positives, for steps 4 and 5:

- Pre-existing issues
- Something that looks like a bug but is not actually a bug
- Pedantic nitpicks that a senior engineer wouldn't call out
- Issues that a linter, typechecker, or compiler would catch (eg. missing or incorrect imports, type errors, broken tests, formatting issues, pedantic style issues like newlines). No need to run these build steps yourself -- it is safe to assume that they will be run separately as part of CI.
- General code quality issues (eg. lack of test coverage, general security issues, poor documentation), unless explicitly required in CLAUDE.md
- Issues that are called out in CLAUDE.md, but explicitly silenced in the code (eg. due to a lint ignore comment)
- Changes in functionality that are likely intentional or are directly related to the broader change
- Real issues, but on lines that the user did not modify in their pull request

Notes:

- Do not check build signal or attempt to build or typecheck the app. These will run separately, and are not relevant to your code review.
- Use `gh` to interact with Github (eg. to fetch a pull request, or to create inline comments), rather than web fetch
- Make a todo list first
- You must cite and link each bug (eg. if referring to a CLAUDE.md, you must link it)
- When linking to code in inline comment bodies, use the full SHA format: `https://github.com/OWNER/REPO/blob/<full-sha>/path/to/file.ts#L42-L45`
