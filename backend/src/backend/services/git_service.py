import asyncio
import os
import shutil
from pathlib import Path
from typing import List, Optional, Tuple

from backend.schemas.git import (
    GitActionResult,
    GitCommitRequest,
    GitDiffResponse,
    GitFileChange,
    GitStatusResponse,
)


class GitService:
    @staticmethod
    def _get_project_root(project_path_str: str) -> Path:
        resolved = Path(os.path.expanduser(project_path_str)).resolve()
        if not resolved.exists() or not resolved.is_dir():
            raise ValueError(f"Project directory '{project_path_str}' does not exist.")
        return resolved

    @classmethod
    async def _run_git_cmd(
        cls,
        project_root: Path,
        args: List[str],
        timeout: float = 30.0,
    ) -> Tuple[int, str, str]:
        cmd = ["git"] + args
        process = await asyncio.create_subprocess_exec(
            *cmd,
            cwd=str(project_root),
            stdout=asyncio.subprocess.PIPE,
            stderr=asyncio.subprocess.PIPE,
        )
        try:
            stdout, stderr = await asyncio.wait_for(process.communicate(), timeout=timeout)
            out_str = stdout.decode("utf-8", errors="replace")
            err_str = stderr.decode("utf-8", errors="replace")
            return process.returncode or 0, out_str, err_str
        except asyncio.TimeoutError:
            process.kill()
            return -1, "", "Git command timed out."

    @classmethod
    async def get_status(cls, project_path_str: str) -> GitStatusResponse:
        project_root = cls._get_project_root(project_path_str)

        # Check if git repository
        code, out, _ = await cls._run_git_cmd(project_root, ["rev-parse", "--is-inside-work-tree"])
        if code != 0 or out.strip() != "true":
            return GitStatusResponse(is_repo=False)

        # Get branch and file status in porcelain format
        code, status_out, _ = await cls._run_git_cmd(
            project_root, ["status", "--porcelain=v1", "-b", "-uall"]
        )

        branch = "HEAD"
        tracking = None
        ahead = 0
        behind = 0
        staged: List[GitFileChange] = []
        unstaged: List[GitFileChange] = []
        untracked: List[GitFileChange] = []

        lines = status_out.splitlines()
        for line in lines:
            if not line:
                continue
            if line.startswith("## "):
                # Header: e.g. ## master...origin/master [ahead 1, behind 2] or ## Initial commit on master
                header = line[3:].strip()
                if "..." in header:
                    parts = header.split("...")
                    branch = parts[0].strip()
                    rest = parts[1].strip()
                    if "[" in rest:
                        t_parts = rest.split("[")
                        tracking = t_parts[0].strip()
                        bracket_info = t_parts[1].rstrip("]")
                        if "ahead" in bracket_info:
                            for item in bracket_info.split(","):
                                if "ahead" in item:
                                    ahead = int("".join(filter(str.isdigit, item)) or 0)
                                if "behind" in item:
                                    behind = int("".join(filter(str.isdigit, item)) or 0)
                    else:
                        tracking = rest
                else:
                    branch = header.split(" ")[0].strip()
            else:
                if len(line) < 4:
                    continue
                x = line[0]
                y = line[1]
                path = line[3:].strip()

                if x == "?" and y == "?":
                    untracked.append(GitFileChange(path=path, status="U", is_staged=False))
                else:
                    # Index (staged) change
                    if x in ["M", "A", "D", "R", "C"]:
                        staged.append(
                            GitFileChange(
                                path=path,
                                status=x,
                                is_staged=True,
                            )
                        )
                    # Working tree (unstaged) change
                    if y in ["M", "D"]:
                        unstaged.append(
                            GitFileChange(
                                path=path,
                                status=y,
                                is_staged=False,
                            )
                        )

        # Get last commit info
        _, log_out, _ = await cls._run_git_cmd(
            project_root, ["log", "-1", "--format=%H|%an|%ar|%s"]
        )
        last_hash = None
        last_author = None
        last_date = None
        last_msg = None
        if log_out.strip():
            parts = log_out.strip().split("|", 3)
            if len(parts) >= 4:
                last_hash = parts[0][:7]
                last_author = parts[1]
                last_date = parts[2]
                last_msg = parts[3]

        is_clean = len(staged) == 0 and len(unstaged) == 0 and len(untracked) == 0

        return GitStatusResponse(
            is_repo=True,
            branch=branch,
            tracking=tracking,
            ahead=ahead,
            behind=behind,
            is_clean=is_clean,
            staged=staged,
            unstaged=unstaged,
            untracked=untracked,
            last_commit_hash=last_hash,
            last_commit_author=last_author,
            last_commit_date=last_date,
            last_commit_message=last_msg,
        )

    @classmethod
    async def get_diff(
        cls,
        project_path_str: str,
        relative_path: Optional[str] = None,
        staged: bool = False,
    ) -> GitDiffResponse:
        project_root = cls._get_project_root(project_path_str)

        args = ["diff"]
        if staged:
            args.append("--cached")

        if relative_path and relative_path.strip():
            rel_clean = relative_path.strip()
            args.extend(["--", rel_clean])
            code, diff_out, _ = await cls._run_git_cmd(project_root, args)

            # If unstaged diff is empty and file is untracked, show whole file as addition diff
            if not diff_out.strip() and not staged:
                target_file = (project_root / rel_clean).resolve()
                if target_file.exists() and target_file.is_file():
                    try:
                        with open(target_file, "r", encoding="utf-8", errors="replace") as f:
                            content = f.read()
                        diff_lines = [
                            f"diff --git a/{rel_clean} b/{rel_clean}",
                            "new file mode 100644",
                            "--- /dev/null",
                            f"+++ b/{rel_clean}",
                            "@@ -0,0 +1," + str(len(content.splitlines())) + " @@",
                        ]
                        for l in content.splitlines():
                            diff_lines.append("+" + l)
                        diff_out = "\n".join(diff_lines)
                    except Exception:
                        pass

            return GitDiffResponse(diff=diff_out, path=rel_clean, staged=staged)
        else:
            code, diff_out, _ = await cls._run_git_cmd(project_root, args)
            return GitDiffResponse(diff=diff_out, path=None, staged=staged)

    @classmethod
    async def stage_files(cls, project_path_str: str, paths: Optional[List[str]] = None) -> GitActionResult:
        project_root = cls._get_project_root(project_path_str)
        if paths and len(paths) > 0:
            code, out, err = await cls._run_git_cmd(project_root, ["add", "--"] + paths)
        else:
            code, out, err = await cls._run_git_cmd(project_root, ["add", "-A"])

        return GitActionResult(
            success=code == 0,
            message="Staged successfully" if code == 0 else f"Failed to stage: {err}",
            stdout=out,
            stderr=err,
        )

    @classmethod
    async def unstage_files(cls, project_path_str: str, paths: Optional[List[str]] = None) -> GitActionResult:
        project_root = cls._get_project_root(project_path_str)
        if paths and len(paths) > 0:
            code, out, err = await cls._run_git_cmd(project_root, ["restore", "--staged", "--"] + paths)
            if code != 0:
                code, out, err = await cls._run_git_cmd(project_root, ["reset", "HEAD", "--"] + paths)
        else:
            code, out, err = await cls._run_git_cmd(project_root, ["restore", "--staged", "."])
            if code != 0:
                code, out, err = await cls._run_git_cmd(project_root, ["reset", "HEAD"])

        return GitActionResult(
            success=code == 0,
            message="Unstaged successfully" if code == 0 else f"Failed to unstage: {err}",
            stdout=out,
            stderr=err,
        )

    @classmethod
    async def discard_changes(cls, project_path_str: str, paths: List[str]) -> GitActionResult:
        project_root = cls._get_project_root(project_path_str)
        errors = []

        # Check git status first to know untracked vs tracked
        status = await cls.get_status(project_path_str)
        untracked_set = {u.path for u in status.untracked}

        tracked_to_restore = []
        for p in paths:
            if p in untracked_set:
                target = (project_root / p).resolve()
                try:
                    target.relative_to(project_root)
                    if target.is_file():
                        os.remove(target)
                    elif target.is_dir():
                        shutil.rmtree(target)
                except Exception as e:
                    errors.append(f"Failed to delete {p}: {e}")
            else:
                tracked_to_restore.append(p)

        if tracked_to_restore:
            code, out, err = await cls._run_git_cmd(project_root, ["restore", "--"] + tracked_to_restore)
            if code != 0:
                code, out, err = await cls._run_git_cmd(project_root, ["checkout", "--"] + tracked_to_restore)
                if code != 0:
                    errors.append(err)

        if errors:
            return GitActionResult(success=False, message="; ".join(errors))
        return GitActionResult(success=True, message="Changes discarded successfully")

    @classmethod
    async def commit(cls, req: GitCommitRequest) -> GitActionResult:
        project_root = cls._get_project_root(req.project_path)
        if not req.message.strip():
            return GitActionResult(success=False, message="Commit message cannot be empty")

        if req.stage_all:
            await cls._run_git_cmd(project_root, ["add", "-A"])

        code, out, err = await cls._run_git_cmd(project_root, ["commit", "-m", req.message.strip()])
        return GitActionResult(
            success=code == 0,
            message="Committed successfully" if code == 0 else f"Commit failed: {err or out}",
            stdout=out,
            stderr=err,
        )

    @classmethod
    async def push(cls, project_path_str: str) -> GitActionResult:
        project_root = cls._get_project_root(project_path_str)
        code, out, err = await cls._run_git_cmd(project_root, ["push"], timeout=60.0)
        return GitActionResult(
            success=code == 0,
            message="Pushed to remote successfully" if code == 0 else f"Push failed: {err or out}",
            stdout=out,
            stderr=err,
        )

    @classmethod
    async def pull(cls, project_path_str: str) -> GitActionResult:
        project_root = cls._get_project_root(project_path_str)
        code, out, err = await cls._run_git_cmd(project_root, ["pull"], timeout=60.0)
        return GitActionResult(
            success=code == 0,
            message="Pulled from remote successfully" if code == 0 else f"Pull failed: {err or out}",
            stdout=out,
            stderr=err,
        )

    @classmethod
    async def get_branches(cls, project_path_str: str) -> List[str]:
        project_root = cls._get_project_root(project_path_str)
        code, out, _ = await cls._run_git_cmd(project_root, ["branch", "--format=%(refname:short)"])
        if code != 0:
            return []
        return [b.strip() for b in out.splitlines() if b.strip()]


git_service = GitService()
