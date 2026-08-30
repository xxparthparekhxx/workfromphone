import os
import re
from pathlib import Path
from typing import List, Optional, Tuple

from backend.schemas.fs import (
    BrowseResponse,
    DirectoryItem,
    ProjectFilesResponse,
    QuickPathsResponse,
    ValidatePathResponse,
)

_IGNORED_PROJECT_DIRECTORIES = {
    ".dart_tool",
    ".git",
    ".gradle",
    ".idea",
    ".venv",
    ".vscode",
    "__pycache__",
    "build",
    "dist",
    "node_modules",
    "Pods",
}


class FSService:
    @staticmethod
    def get_home_dir() -> Path:
        return Path.home().resolve()

    @staticmethod
    def detect_project_type(directory_path: Path) -> Tuple[bool, Optional[str]]:
        if not directory_path.is_dir():
            return False, None

        markers = [
            ("pubspec.yaml", "flutter"),
            ("package.json", "node"),
            ("pyproject.toml", "python"),
            ("requirements.txt", "python"),
            ("Cargo.toml", "rust"),
            ("go.mod", "go"),
            ("pom.xml", "java-maven"),
            ("build.gradle", "java-gradle"),
            ("build.gradle.kts", "kotlin-gradle"),
            ("CMakeLists.txt", "cpp-cmake"),
            (".git", "git"),
        ]

        for marker, p_type in markers:
            marker_path = directory_path / marker
            if marker_path.exists():
                return True, p_type

        return False, None

    @classmethod
    def browse(cls, target_path_str: Optional[str] = None) -> BrowseResponse:
        home = cls.get_home_dir()
        if not target_path_str or target_path_str.strip() == "":
            target_path = home
        else:
            target_path = Path(os.path.expanduser(target_path_str)).resolve()

        if not target_path.exists() or not target_path.is_dir():
            target_path = home

        items: List[DirectoryItem] = []
        try:
            with os.scandir(target_path) as entries:
                for entry in entries:
                    try:
                        item_path = Path(entry.path)
                        if not item_path.exists():
                            continue

                        is_dir = entry.is_dir(follow_symlinks=False)
                        is_project = False
                        project_type = None
                        if is_dir:
                            is_project, project_type = cls.detect_project_type(item_path)

                        try:
                            stat = entry.stat(follow_symlinks=False)
                            size = None if is_dir else stat.st_size
                            modified = str(int(stat.st_mtime))
                        except Exception:
                            size = None
                            modified = None

                        items.append(
                            DirectoryItem(
                                name=entry.name,
                                path=str(item_path),
                                is_dir=is_dir,
                                is_project=is_project,
                                project_type=project_type,
                                size_bytes=size,
                                modified_at=modified,
                            )
                        )
                    except Exception:
                        continue
        except PermissionError:
            pass

        # Sort: directories first (alphabetical), then files (alphabetical)
        items.sort(key=lambda x: (not x.is_dir, x.name.lower()))

        parent_path = str(target_path.parent) if target_path.parent != target_path else None
        is_cur_project, cur_project_type = cls.detect_project_type(target_path)

        return BrowseResponse(
            current_path=str(target_path),
            parent_path=parent_path,
            home_path=str(home),
            items=items,
            is_project=is_cur_project,
            project_type=cur_project_type,
        )

    @classmethod
    def validate_path(cls, path_str: str) -> ValidatePathResponse:
        try:
            resolved = Path(os.path.expanduser(path_str)).resolve()
            if not resolved.exists():
                return ValidatePathResponse(
                    valid=False,
                    path=str(resolved),
                    exists=False,
                    is_dir=False,
                    message="Directory does not exist",
                )
            if not resolved.is_dir():
                return ValidatePathResponse(
                    valid=False,
                    path=str(resolved),
                    exists=True,
                    is_dir=False,
                    message="Path is a file, not a directory",
                )

            is_project, p_type = cls.detect_project_type(resolved)
            return ValidatePathResponse(
                valid=True,
                path=str(resolved),
                exists=True,
                is_dir=True,
                is_project=is_project,
                project_type=p_type,
                message="Valid project directory",
            )
        except Exception as e:
            return ValidatePathResponse(
                valid=False,
                path=path_str,
                exists=False,
                is_dir=False,
                message=str(e),
            )

    @classmethod
    def get_quick_paths(cls) -> QuickPathsResponse:
        home = cls.get_home_dir()
        current_workspace = str(Path.cwd().resolve())

        common_candidates = [
            home / "code",
            home / "Projects",
            home / "development",
            home / "Desktop",
            home / "Documents",
            Path(current_workspace),
        ]

        quick_items: List[DirectoryItem] = []
        seen = set()

        for cand in common_candidates:
            if cand.exists() and cand.is_dir() and str(cand) not in seen:
                seen.add(str(cand))
                is_proj, p_type = cls.detect_project_type(cand)
                quick_items.append(
                    DirectoryItem(
                        name=cand.name if cand != home else "Home",
                        path=str(cand),
                        is_dir=True,
                        is_project=is_proj,
                        project_type=p_type,
                    )
                )

        return QuickPathsResponse(
            home=str(home),
            current_workspace=current_workspace,
            common_paths=quick_items,
        )

    @staticmethod
    def list_project_files(project_path: str, limit: int) -> ProjectFilesResponse:
        project_root = Path(os.path.expanduser(project_path)).resolve()
        if not project_root.exists() or not project_root.is_dir():
            raise FileNotFoundError("Project directory not found")

        files: list[str] = []
        for current_root, directories, filenames in os.walk(project_root):
            directories[:] = sorted(
                (
                    name
                    for name in directories
                    if name not in _IGNORED_PROJECT_DIRECTORIES
                ),
                key=str.casefold,
            )
            for filename in sorted(filenames, key=str.casefold):
                path = Path(current_root, filename)
                files.append(path.relative_to(project_root).as_posix())
                if len(files) > limit:
                    return ProjectFilesResponse(
                        files=files[:limit],
                        truncated=True,
                    )

        return ProjectFilesResponse(files=files)


fs_service = FSService()
