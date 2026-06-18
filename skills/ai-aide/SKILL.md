---
name: ai-aide
description: Coordinate a delegated Claude Code or other CLI execution aide under Codex control for code writing, large refactors, and automated build/test loops. Use when the user asks for an AI aide/helper/assistant, Claude Code, a Codex CLI helper, or a visible terminal chat session such as WT/PowerShell, or when a task benefits from large-file edits, boilerplate generation, cross-file rewrites, compile/test execution, or other token-heavy mechanical work while Codex remains the architect, reviewer, and final verifier.
---

# AI Aide

## Core Contract

Use this skill to run a second AI tool as a bounded execution aide, while Codex stays the user-facing lead and final verifier.

- Codex owns task framing, architecture, root-cause analysis, security and design review, integration, verification, and the final report.
- The aide executes the delegated coding slice, including large-file read/write, bulk edits, boilerplate generation, and build/test loops, and writes machine-readable status under `.codex_delegate/`.
- The user talks to Codex, not directly to the aide.
- Default to a visible CLI chat window when the adapter supports it. Background print/json mode is opt-in only.
- Prefer the lightest path that preserves quality, but default to moving token-heavy mechanical work to the aide once scope is clear.

## Operating Model

This skill is optimized for code implementation, large refactors, and automated verification by splitting static judgment from dynamic execution.

- **Static / high-value decisions stay in Codex**: requirement decomposition, architecture, tricky bug reasoning, security review, naming, boundary decisions, and final acceptance.
- **Dynamic / heavy execution moves to the aide**: large source reads, repetitive code writing, broad cross-file edits, WPF/XAML/ViewModel or service/mapper scaffolding, build/test/lint runs, and local compile-fix loops.
- **Asynchronous toolchain**: Codex writes the task package, launches the visible CLI aide, waits on short status plus short reports, and avoids reading full transcripts or long raw logs unless something failed.

## Role Split

### Codex App

- Act as the architect and strategy brain.
- Turn user intent into a bounded implementation or refactor plan.
- Review the aide's diff, commands, and remaining risks before accepting the result.
- Avoid reading giant source files or manually doing repetitive edits unless the aide stalls or the task is too small to delegate.

### Claude Code CLI or other aide

- Act as the mechanical implementer and automated executor.
- Perform large code writes, repetitive edits, refactors, and sample or scaffold generation.
- Run build, lint, typecheck, smoke, and test commands inside the allowed scope.
- Fix local compile or test failures when they are mechanical and within the approved scope before escalating.
- Reply in Chinese only, including chat replies, reports, and summaries.

## Delegation Rules

Delegate to an AI aide for:

- Large-file code reading and writing, especially when the file or diff would waste main-thread tokens.
- Batch mechanical edits, repetitive pattern replacement, or boilerplate generation.
- Cross-file refactors, namespace moves, API signature propagation, and repetitive call-site rewrites.
- WPF/XAML/ViewModel, service, mapper, DTO, configuration, or test scaffold generation.
- Long build, lint, typecheck, smoke, unit test, or integration test runs, plus local fixups for failures inside scope.
- Initial impact mapping, candidate path comparison, gap checks, or long log summarization.
- A user request that explicitly asks for an AI aide such as Claude Code or a Codex CLI helper.

Special attention for legacy .NET / classic project systems:

- If the project uses a classic non-SDK `.csproj`, do not assume a newly created `.cs`, `.xaml`, or test file is auto-included. Inspect the project file and add the required `<Compile Include=...>`, `<Page Include=...>`, or related item when needed.
- Do not trust a bare `dotnet test` exit code on classic .NET Framework MSTest projects when output is suspiciously thin. Prefer a verification path that proves the new file was compiled and tests were actually discovered and executed, such as solution-level `msbuild` with the correct configuration/platform plus `vstest.console.exe`.

Keep work in Codex for:

- Small single-file or two-file edits.
- Product judgment, requirement tradeoffs, architecture boundaries, naming, or final plan decisions.
- Complex bug root-cause analysis when the problem is still unclear and broad implementation would be premature.
- Final diff review, accept/reject decisions, and user-facing explanation.
- Secrets, credentials, private keys, account data, or production-sensitive configuration.
- Destructive or irreversible operations.
- Editing this skill or the delegation protocol itself, unless the user specifically asks to involve an aide.

## Aide Adapters

Select the aide implementation from the current environment and user request.

- **Claude Code adapter**: Use when Claude Code is available or explicitly requested. Default to a visible interactive terminal chat session. On Windows, prefer a dedicated `powershell.exe` window first, then `pwsh.exe`, and use `wt.exe` only as a fallback.
- **Codex CLI adapter**: Use when the user asks for a Codex CLI helper or the workspace has a configured helper command. Default to the normal visible TUI/REPL instead of print/json modes, and reuse the same task package, status JSON, waiting, and verification contract.
- **Other local AI CLI adapter**: Use only when the user requested it or the workspace documents it. Keep the same bounded-task protocol.

Do not silently downgrade a visible aide workflow into a background print mode. If the requested adapter is unavailable after reasonable launch attempts, either execute directly or report the adapter blocker, depending on whether the user explicitly required that aide.

## Repository State

Use the current repository root unless the user specifies another workspace. Store delegation artifacts here:

```text
.codex_delegate/
  prompts/       # Task packages written by Codex for the aide
  reports/       # Detailed reports only for blockers, failures, risks, or decisions
  state/         # Small status JSON files; Codex reads these by default
  logs/          # Lightweight launch logs or short failure tails
```

Create only the directories needed for the task. Do not store full aide transcripts or stream-json output as the main workflow.

## Task Shape

Keep aide tasks narrow and verifiable. Do not package investigation, decision making, broad implementation, subjective self-review, and final acceptance into one aide task.

Default execution pattern for substantive code work:

1. Codex performs framing and chooses the boundaries.
2. The aide performs `implement` for the heavy coding lane.
3. The aide performs `verify` for build/test/lint and self-heals local failures when possible.
4. Codex reviews diff plus short report and decides whether the result is acceptable.

For legacy build systems, include project-file wiring in `implement` and runner selection in `verify` when those are required for the new code to become real.

Use phases for open-ended, subjective, or high-risk work:

1. `discover`: collect evidence, risks, and candidate paths; avoid broad edits.
2. `propose`: produce options for Codex to decide.
3. `implement`: make bounded code changes inside an approved scope; prefer doing the real edits instead of stopping at analysis.
4. `verify`: run build/test/lint/typecheck or other targeted checks, repair local mechanical failures when authorized, and identify remaining gaps.

Suggested task IDs:

- `<slug>-discover`
- `<slug>-propose`
- `<slug>-implement`
- `<slug>-verify`

## Task Package Template

Write each aide prompt to `.codex_delegate/prompts/<task-id>.md` as UTF-8. For Chinese or other non-ASCII content, keep readable characters in the file and pass only a short ASCII launch instruction that points to the file.

```markdown
# AI Aide Subtask

## Task ID
<task-id>

## Task Type
<discover | propose | implement | verify>

## Current Phase
Only do this phase. If the next phase is needed, stop and update status/report instead of continuing.

## Role
You are an AI execution aide focused on heavy coding and automated verification. Codex is the lead and final verifier. Do not ask the user questions.

## Output Language
Chinese only.

## User Goal
<one-sentence goal>

## This Subtask
<one narrow, bounded task>

## Allowed Scope
- <files, directories, commands, or read/write boundaries>

## Forbidden
- Do not modify files outside the allowed scope.
- Do not add dependencies unless explicitly authorized.
- Do not run destructive git or filesystem commands.
- Do not read, print, or exfiltrate secrets, tokens, private keys, certificates, or production credentials.
- Do not ask the user questions; write uncertainty into status or report.

## Output Rules
- On start, write `.codex_delegate/state/<task-id>.json` with `status: "running"`.
- During long work, update `updated_at` and one-sentence `summary`.
- All chat replies, summaries, reports, and status `summary` values must be in Chinese.
- For `implement` tasks, prefer completing the actual code changes instead of stopping at file reading or passive analysis.
- When adding a new source file or test file in a classic project, verify that the project file includes it. Do not claim completion if the file exists on disk but is not compiled into the project.
- For `implement` and `verify` tasks, run the relevant build/test/lint/typecheck commands inside scope. If they fail for local, fixable reasons, fix and retry before escalating.
- Choose verification commands that match the build system. For classic .NET Framework test projects, prefer the runner that truly compiles and executes the updated tests; if `dotnet test` output is inconclusive, switch to `msbuild`, `vstest.console`, or another project-appropriate runner.
- On normal completion, write `status: "ok"` as the final explicit status update.
- For `implement` or `verify` tasks that changed code or ran verification commands, also write a short handoff report to `.codex_delegate/reports/<task-id>.md` covering changed files, commands run, verification result, and remaining risk.
- Do not mark `status: "ok"` before the required short handoff report has been written.
- If Codex attention is needed, write a detailed report first, then update status with `status: "needs_attention"` and `report_path`.
- Evidence tasks may return at most 8 entries in `path:line:summary` form.
- Summarize long logs; do not paste full logs.

## Acceptance Criteria
- <verifiable condition>
- Suggested command: <command, or "none">
```

## Status JSON

The aide must write a small JSON file under `.codex_delegate/state/<task-id>.json`.

Running:

```json
{
  "task_id": "<task-id>",
  "status": "running",
  "updated_at": "<ISO-8601 timestamp with timezone>",
  "changed_files": [],
  "commands_failed": [],
  "needs_codex_attention": false,
  "summary": "current phase in one sentence"
}
```

Normal completion:

```json
{
  "task_id": "<task-id>",
  "status": "ok",
  "updated_at": "<ISO-8601 timestamp with timezone>",
  "changed_files": [],
  "commands_failed": [],
  "needs_codex_attention": false,
  "summary": "one-sentence result"
}
```

Needs Codex attention:

```json
{
  "task_id": "<task-id>",
  "status": "needs_attention",
  "updated_at": "<ISO-8601 timestamp with timezone>",
  "changed_files": [],
  "commands_failed": [],
  "needs_codex_attention": true,
  "summary": "one-sentence issue or decision point",
  "report_path": ".codex_delegate/reports/<task-id>.md"
}
```

## Launch Protocol

Before launch:

1. Write the task package to disk.
2. Ensure `.codex_delegate/state/` exists. For visible terminal workflows, also ensure `.codex_delegate/prompts/`, `.codex_delegate/reports/`, and `.codex_delegate/logs/` exist.
3. Default to a visible CLI chat window when the adapter supports it. On Windows, prefer a dedicated `powershell.exe` window first, then `pwsh.exe`, and use `wt.exe` only as a fallback.
4. Copy the prompt file contents to the clipboard before submitting the task in the visible session.

Claude Code adapter:

```powershell
claude --dangerously-skip-permissions
```

On Windows, prefer the bundled helper:

```powershell
powershell -ExecutionPolicy Bypass -File "<skill-dir>\scripts\launch-visible-aide.ps1" `
  -RepoRoot "<repo-root>" `
  -PromptPath "<absolute-prompt-path>" `
  -TaskId "<task-id>"
```

The bundled Windows helper is the preferred path because it opens a dedicated visible terminal and starts Claude with a short ASCII initial message that tells it to read the on-disk task file. This keeps the workflow unattended without relying on global paste keystrokes. The clipboard copy remains only as a human fallback.

Visible-session rules:

- Launch the normal chat TUI in a visible terminal. Do not pass the full prompt as a CLI argument.
- Default to automatic unattended task start through a CLI prompt argument that references the on-disk task file. Do not rely on global paste keystrokes for normal operation.
- Keep the clipboard copy as a manual fallback only.
- Verify the handoff succeeded by confirming the prompt was visibly submitted in the chat/session, or by observing the aide's response or report output.
- If the unattended CLI prompt-argument start fails, fall back to visible manual paste. Do not silently continue without proof that the prompt was actually submitted.
- Do not use global `Ctrl+V` or `Enter` injection as a normal path.
- Do not use `claude -p`, `--output-format stream-json`, `--include-partial-messages`, or `--include-hook-events` unless the user explicitly requested non-interactive or machine-consumable output.
- If `claude -p --output-format stream-json` is explicitly requested, include `--verbose`.
- When launching Claude Code for this skill, the preferred operating mode is implementation plus verification, not passive browsing. The prompt should tell the aide to edit code, run checks, and respond in Chinese.

For Chinese or long prompts on Windows, never pass the full prompt text as a terminal argument. Use a UTF-8 prompt file plus clipboard handoff. If quoting or adapter-specific launch arguments are fragile, use a temporary `.ps1` or `.cmd` wrapper that opens the visible TUI and points to the on-disk prompt.

If `CLAUDE_DELEGATE_EXE`, `CLAUDE_DELEGATE_ARGS`, or workspace-specific wrapper commands would switch the session back to print/json or other hidden background modes, ignore them unless the user explicitly asked for that non-visual mode.

Codex CLI or other AI CLI adapter:

- Use the workspace-documented command if one exists.
- Launch the normal visible TUI/REPL when the adapter supports it. Keep the same prompt-file handoff, clipboard paste, and status JSON contract.
- If the adapter is inherently non-visual, make that explicit in the progress update and keep status JSON as the coordination surface.

## Waiting Protocol

When a task ID is known:

- Prefer an existing repository wait helper if available, such as a script that watches `.codex_delegate/state/<task-id>.json`.
- Otherwise poll the status JSON every 20-30 seconds.
- If `status` is `running` and `updated_at` keeps changing, continue waiting and do not read long aide transcripts or logs.
- If `status` is `ok`, read the short report when one exists for `implement` or `verify`, then begin Codex verification.
- If `status` is not `ok`, `needs_codex_attention` is true, or `commands_failed` is non-empty, read the detailed report or relevant log tail.
- If `updated_at` is stale for 5-10 minutes, send the aide a short status request in the same visible session if possible; otherwise take over or report the blocker. Do not spin up a hidden print/json retry while a visible session is the intended workflow.

Once the aide owns an investigation lane, do not duplicate the same search in Codex while waiting unless the aide stalls, exceeds scope, or gives an untrustworthy result.

## Codex Verification

After aide completion, Codex must verify independently.

Always check:

```powershell
git diff --stat
git diff --check
```

Then run the repository's relevant build, test, lint, typecheck, smoke, or install steps based on the changed surface and local instructions such as `AGENTS.md`, `CLAUDE.md`, package scripts, or project docs.

Review:

- Whether the diff stayed inside the authorized scope.
- Whether dependencies, generated files, or unrelated refactors were added.
- Whether project instructions were followed.
- Whether the aide actually implemented code and ran checks when the task called for it, instead of stopping at read-only analysis.
- Whether newly added source files were actually wired into the build system and not left uncompiled.
- Whether the chosen build/test runner was appropriate for the project type, especially for legacy .NET Framework projects.
- Whether test and build output really passed.
- Whether status JSON, reports, and actual diff agree.

Codex owns final acceptance even when the aide reports success.

## Retry Rules

Automatically retry or re-instruct the same aide task up to 2 times when:

- Status JSON is missing or invalid.
- `status` remains `running` but `updated_at` is stale.
- A detailed report is missing when status says attention is needed.
- Build or tests fail for a local, fixable reason.
- The aide modified files outside scope but can be corrected safely.
- The launch method violated this protocol and should be restarted correctly.

After 2 failed retries, take over directly or report a clear blocker.

## Safety Boundary

Never let the aide run destructive commands unless the user explicitly authorized the exact operation, target path, and risk. Forbidden by default:

```text
git reset --hard
git checkout -- .
git clean -fd
Remove-Item -Recurse -Force <unclear-path>
rm -rf
format
del /s
force-push
uploading secrets or source code to external services
```

## Final Report

Keep the final report short and outcome-first:

- Whether an AI aide was used.
- Prompt path, status JSON path, and report path if a report exists.
- The aide's core conclusion, not the full process.
- Whether the aide handled implementation, build, and test work as intended.
- Codex verification commands and results.
- Changed files and remaining risk.

If the aide avoided long logs or duplicate search in the main thread, mention that in one sentence.
