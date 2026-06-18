---
name: lore-commit
description: "Draft git commit messages that follow the Lore protocol: intent-first subject, optional narrative body, and git-native trailers such as Constraint, Rejected, Confidence, Scope-risk, Directive, Tested, and Not-tested. Use when a repo or user asks for Lore commits, structured decision-record commit messages, or commit trailers beyond a normal Conventional Commit."
---

# Lore Commit

Use this skill to write a commit message, not to run `git commit`.

## Workflow

1. Inspect the staged or described change.
2. Identify the change intent, important constraints, rejected alternatives, verification performed, and any real verification gaps.
3. Write an intent-first subject line that explains why the change was made, not what files changed.
4. Add a short body only when the why is not obvious from the subject alone.
5. Add only the trailers that add value. Omit any trailer you cannot support with evidence.

## Format

```text
<intent line>

<body when needed>

Constraint: <external constraint that shaped the decision>
Rejected: <alternative considered> | <reason for rejection>
Confidence: <low|medium|high>
Scope-risk: <narrow|moderate|broad>
Reversibility: <clean|messy|irreversible>
Directive: <forward-looking warning or instruction>
Tested: <verification performed>
Not-tested: <known verification gap>
Related: <issue, PR, or commit reference>
```

## Rules

- Subject explains why, not the file edit.
- Use git-native `Key: value` trailers after a blank line.
- Multiple `Constraint:` or `Rejected:` lines are allowed when needed.
- Keep trailers factual. If a fact is unknown, omit it instead of guessing.
- Include `Not-tested:` whenever there is a real verification gap.
- Do not include filler such as "This commit does...", AI attribution, or file-by-file narration.
- If the repo also requires another convention, satisfy the repo requirement first. If requirements conflict, say so explicitly.

## Output

- Return only the commit message in a fenced `text` block unless the user asked for explanation.
- Do not stage files, run `git commit`, or amend history.

## Example

```text
Prevent retry storms after scanner reconnect

The reconnect path was replaying queued jobs before the device
health check finished, which caused duplicate submissions under
brief network flaps.

Constraint: Upstream scanner SDK reports reconnect before transport is stable
Rejected: Add fixed 5s delay | hides race and slows healthy reconnects
Confidence: high
Scope-risk: narrow
Directive: Do not move queue replay earlier without re-testing transient reconnect behavior
Tested: Manual reconnect with queued jobs
Not-tested: Long-running reconnect soak test
```
