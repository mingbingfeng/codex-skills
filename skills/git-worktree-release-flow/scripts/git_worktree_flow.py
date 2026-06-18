#!/usr/bin/env python3
from __future__ import annotations

import argparse
import subprocess
import sys
from pathlib import Path


def fail(message: str) -> int:
    print(f"ERROR: {message}", file=sys.stderr)
    return 1


def git_command(repo: Path, args: list[str]) -> list[str]:
    return ["git", "-C", str(repo), *args]


def run(
    repo: Path,
    args: list[str],
    *,
    capture_output: bool = True,
    check: bool = True,
) -> subprocess.CompletedProcess[str]:
    return subprocess.run(
        git_command(repo, args),
        capture_output=capture_output,
        check=check,
        text=True,
    )


def resolve_repo(path_value: str) -> Path:
    repo = Path(path_value).resolve()
    try:
        result = run(repo, ["rev-parse", "--show-toplevel"])
    except subprocess.CalledProcessError as exc:
        message = exc.stderr.strip() or exc.stdout.strip() or "not a git repository"
        raise RuntimeError(message) from exc
    return Path(result.stdout.strip()).resolve()


def resolve_common_dir(path_value: str) -> Path:
    path = Path(path_value).resolve()
    try:
        result = run(path, ["rev-parse", "--path-format=absolute", "--git-common-dir"])
    except subprocess.CalledProcessError as exc:
        message = exc.stderr.strip() or exc.stdout.strip() or "not a git repository"
        raise RuntimeError(message) from exc
    return Path(result.stdout.strip()).resolve()


def ensure_ref_exists(repo: Path, ref: str) -> None:
    try:
        run(repo, ["rev-parse", "--verify", "--quiet", f"{ref}^{{commit}}"])
    except subprocess.CalledProcessError as exc:
        raise RuntimeError(f"ref does not exist: {ref}") from exc


def branch_exists(repo: Path, branch: str) -> bool:
    result = run(
        repo,
        ["show-ref", "--verify", "--quiet", f"refs/heads/{branch}"],
        check=False,
    )
    return result.returncode == 0


def parse_worktrees(repo: Path) -> list[dict[str, str]]:
    result = run(repo, ["worktree", "list", "--porcelain"])
    blocks = result.stdout.strip().split("\n\n") if result.stdout.strip() else []
    rows: list[dict[str, str]] = []
    for block in blocks:
        row: dict[str, str] = {}
        for line in block.splitlines():
            key, _, value = line.partition(" ")
            row[key] = value
        rows.append(row)
    return rows


def branch_checkout_path(repo: Path, branch: str) -> Path | None:
    target_ref = f"refs/heads/{branch}"
    for row in parse_worktrees(repo):
        if row.get("branch") == target_ref:
            return Path(row["worktree"]).resolve()
    return None


def print_command(command: list[str]) -> None:
    print(" ".join(f'"{part}"' if " " in part else part for part in command))


def ensure_path_ready(path: Path) -> None:
    if not path.exists():
        return

    if path.is_file():
        raise RuntimeError(f"path exists and is a file: {path}")

    if any(path.iterdir()):
        raise RuntimeError(f"path exists and is not empty: {path}")


def handle_create(args: argparse.Namespace) -> int:
    repo = resolve_repo(args.repo)
    path = Path(args.path).resolve()

    if args.existing_branch:
        if not branch_exists(repo, args.branch):
            return fail(f"branch does not exist: {args.branch}")
        checkout_path = branch_checkout_path(repo, args.branch)
        if checkout_path is not None:
            return fail(f"branch already checked out in worktree: {checkout_path}")
    else:
        ensure_ref_exists(repo, args.base)
        if branch_exists(repo, args.branch):
            checkout_path = branch_checkout_path(repo, args.branch)
            if checkout_path is not None:
                return fail(
                    f"branch already checked out in worktree: {checkout_path}"
                )
            return fail(
                f"branch already exists: {args.branch} (use --existing-branch to attach)"
            )

    ensure_path_ready(path)

    commands: list[list[str]] = []
    if not args.no_fetch:
        commands.append(git_command(repo, ["fetch", "--all", "--prune"]))

    if args.existing_branch:
        commands.append(git_command(repo, ["worktree", "add", str(path), args.branch]))
    else:
        commands.append(
            git_command(repo, ["worktree", "add", "-b", args.branch, str(path), args.base])
        )

    if args.dry_run:
        for command in commands:
            print_command(command)
        return 0

    path.parent.mkdir(parents=True, exist_ok=True)
    for command in commands:
        subprocess.run(command, check=True, text=True)

    print(f"Created worktree: {path}")
    print(f"Repo: {repo}")
    print(f"Branch: {args.branch}")
    if not args.existing_branch:
        print(f"Base: {args.base}")
    return 0


def handle_cleanup(args: argparse.Namespace) -> int:
    repo = resolve_repo(args.repo)
    path = Path(args.path).resolve()

    if not path.exists():
        return fail(f"worktree path does not exist: {path}")

    try:
        worktree_common_dir = resolve_common_dir(str(path))
    except RuntimeError as exc:
        return fail(f"target is not a git worktree: {exc}")

    repo_common_dir = resolve_common_dir(str(repo))
    if worktree_common_dir != repo_common_dir:
        return fail(f"worktree belongs to a different repository: {worktree_common_dir}")

    status = run(path, ["status", "--short"]).stdout.strip()
    if status and not args.force:
        return fail("worktree has uncommitted changes; rerun with --force to remove it")

    commands = [git_command(repo, ["worktree", "remove", *(["--force"] if args.force else []), str(path)])]
    if args.prune:
        commands.append(git_command(repo, ["worktree", "prune"]))

    if args.dry_run:
        if status:
            print("# worktree has uncommitted changes")
            print(status)
        for command in commands:
            print_command(command)
        return 0

    for command in commands:
        subprocess.run(command, check=True, text=True)

    print(f"Removed worktree: {path}")
    return 0


def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(
        description="Create and clean up git worktrees for feature or hotfix flows."
    )
    subparsers = parser.add_subparsers(dest="command", required=True)

    create_parser = subparsers.add_parser("create", help="create a worktree")
    create_parser.add_argument("--repo", default=".", help="repository root or any path inside it")
    create_parser.add_argument("--base", help="base ref for a new branch")
    create_parser.add_argument("--branch", required=True, help="target branch name")
    create_parser.add_argument("--path", required=True, help="worktree directory path")
    create_parser.add_argument(
        "--existing-branch",
        action="store_true",
        help="attach the worktree to an existing local branch instead of creating one",
    )
    create_parser.add_argument(
        "--no-fetch",
        action="store_true",
        help="skip git fetch --all --prune before worktree creation",
    )
    create_parser.add_argument(
        "--dry-run",
        action="store_true",
        help="print git commands without executing them",
    )
    create_parser.set_defaults(handler=handle_create)

    cleanup_parser = subparsers.add_parser("cleanup", help="remove a worktree")
    cleanup_parser.add_argument("--repo", default=".", help="repository root or any path inside it")
    cleanup_parser.add_argument("--path", required=True, help="worktree directory path")
    cleanup_parser.add_argument(
        "--force",
        action="store_true",
        help="remove the worktree even when it has uncommitted changes",
    )
    cleanup_parser.add_argument(
        "--prune",
        action="store_true",
        help="run git worktree prune after removal",
    )
    cleanup_parser.add_argument(
        "--dry-run",
        action="store_true",
        help="print git commands without executing them",
    )
    cleanup_parser.set_defaults(handler=handle_cleanup)

    return parser


def main(argv: list[str] | None = None) -> int:
    parser = build_parser()
    args = parser.parse_args(argv)

    if args.command == "create" and not args.existing_branch and not args.base:
        parser.error("create requires --base unless --existing-branch is set")

    return args.handler(args)


if __name__ == "__main__":
    sys.exit(main())
