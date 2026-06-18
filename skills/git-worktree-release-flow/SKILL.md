---
name: git-worktree-release-flow
description: Manage versioned release, dev, feature, hotfix, and business branches with dedicated git worktrees for parallel development. Use when Codex needs to start a new feature, set up a hotfix from an older release, create or clean up worktrees, follow a repo-specific branching policy, or keep parallel tasks isolated across multiple branches.
---

# Git Worktree Release Flow

Use this skill to create and manage branch-per-task worktrees in repos that maintain a stable production branch plus versioned release or dev lines.

## Workflow

1. Read the repo's branch policy before acting.
   Check targeted files first: `AGENTS.md`, `docs/branching-worktree.md`, `README` release notes, or other user-provided branch docs.
   Extract only the repo-specific profile: production branch, release branch naming, dev branch naming, feature/hotfix naming, worktree root, merge-back rules, and push policy.

2. Pick the lane from the task.
   Use `feature` when the user is developing a new capability from the active dev line.
   Use `hotfix` when the user is repairing an older supported production version.
   Use the long-lived business line only when the task explicitly belongs to that isolated branch family.

3. Resolve names and base branch.
   Use the repo policy when present.
   If the repo has no policy, default to:
   `main`
   `dev/<version>`
   `release/<version>`
   `feature/<version>/<name>`
   `hotfix/<version>/<name>`
   Worktree root: `<repo>/.codex_build/worktrees/<version>/<short-name>`

4. Create one branch and one worktree per task.
   Prefer creating a fresh local branch from the correct base branch.
   Prefer a dedicated worktree directory for every active feature or hotfix.
   Use one agent or thread per worktree to avoid cross-task contamination.

5. Perform implementation inside the target worktree.
   Run all reads, edits, builds, and verification from the selected worktree instead of the primary checkout.
   Keep the main checkout clean for coordination work only.

6. Merge back on completion.
   Merge `feature` back into the matching dev branch.
   Merge `hotfix` back into the matching release branch first, then port the fix into the active dev branch if the repo policy requires it.

7. Clean up safely.
   Remove a worktree only after checking for uncommitted changes.
   Do not auto-push unless the user or repo policy explicitly allows it.
   When no repo policy exists, default to removing the local worktree after merge and keeping the branch until the user asks to delete it.

8. Use the script when setup is already resolved.
   If the repo profile has already told you the base branch, target branch, and worktree path, prefer the bundled script instead of rebuilding raw git commands by hand.
   Use `scripts/git_worktree_flow.py create` for new feature or hotfix worktrees.
   Use `scripts/git_worktree_flow.py cleanup` after merge when the local worktree should be removed.

## Operating Rules

- Prefer local branch and worktree creation without asking when the task is clear and the action is reversible.
- Ask only when the repo policy is missing and the branch naming or merge target is materially ambiguous.
- Run `git worktree list` before creating or removing worktrees.
- Run `git status --short` in the target worktree before cleanup.
- If a branch is already checked out in another worktree, reuse that worktree or create a different branch name instead of forcing it.
- Keep repo-specific rules out of this skill; store only the generic workflow here and let each repo keep a thin profile.

## Minimal Command Pattern

Feature setup pattern:

```powershell
git fetch --all --prune
git worktree add -b <feature-branch> <worktree-path> <dev-branch>
```

Hotfix setup pattern:

```powershell
git fetch --all --prune
git worktree add -b <hotfix-branch> <worktree-path> <release-branch>
```

Safe cleanup pattern:

```powershell
git -C <worktree-path> status --short
git worktree remove <worktree-path>
```

## Script Mode

Use the bundled script after resolving repo-specific names from `AGENTS.md` or other repo docs.

Create a worktree:

```powershell
python scripts/git_worktree_flow.py create --repo <repo> --base <base-branch> --branch <new-branch> --path <worktree-path>
```

Create from an existing local branch:

```powershell
python scripts/git_worktree_flow.py create --repo <repo> --branch <existing-branch> --path <worktree-path> --existing-branch
```

Clean up a merged worktree:

```powershell
python scripts/git_worktree_flow.py cleanup --repo <repo> --path <worktree-path>
```
