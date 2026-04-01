#!/usr/bin/env python3
"""
Universal code-review bundler
Source: https://github.com/Strode-Mountain/machine-shop

Creates outputs under /scripts/code_review/output:
  - CODE_REVIEW_BUNDLE.md (or split files) : Markdown bundle with relevant source
  - REVIEW_PROMPT.md : Companion prompt for an AI reviewer

Automatically splits large bundles when they exceed size limits.
Cleans up previous output before generating new files.
Ensures /scripts/code_review/output/ is in the repo .gitignore.

Usage:
  python scripts/code_review/bundle_review.py [--root /path/to/repo] [--max-files N] [--max-bundle-mb N]

Defaults:
  --root  -> repo root inferred as two levels up from this script (../../)
  --max-files -> unlimited; set to cap files included (oldest-first pruned)
  --max-bundle-mb -> 8MB per file (configurable via BUNDLE_MAX_BUNDLE_MB env var)
"""
import os
import re
import sys
import argparse
import subprocess
import json
from pathlib import Path
from datetime import datetime, timezone

# ------------------------------ Config ------------------------------
# Directories at the REPO ROOT to ignore (your request)
ROOT_EXCLUDE_DIRS = {
    ".github", ".claude", ".expo", "docs", "archive", "specs", "scripts"
}

# Always-ignored directories anywhere in the tree
GLOBAL_EXCLUDE_DIRS = {
    # Version control and IDE
    ".git", ".gradle", ".idea",
    # Python virtual environments
    ".tox", ".venv", "venv", "env",
    # Build and output directories
    "build", "out", "dist", "coverage", ".cache", ".turbo",
    # JavaScript/TypeScript ecosystems
    "node_modules", ".next", "storybook-static", "cypress"
}

# Output directory (relative to repo root)
REL_OUT_DIR = Path("scripts/code_review/output")

# Include/Exclude rules for files
INCLUDE_EXT = {
    # Android/Java/Kotlin
    ".kt", ".java", ".gradle", ".kts", ".pro", ".xml",
    # JavaScript/TypeScript
    ".ts", ".tsx", ".js", ".jsx", ".cjs", ".mjs",
    # Python
    ".py", ".pyx", ".pyi",
    # Documentation and config
    ".md", ".properties", ".txt", ".json", ".yaml", ".yml", ".toml", ".ini", ".cfg"
}
INCLUDE_NAMES = {
    "AndroidManifest.xml", "Proguard-rules.pro", "proguard-rules.pro", "README.md", "LICENSE",
    "settings.gradle", "settings.gradle.kts", "Dockerfile", "docker-compose.yml", "Makefile"
}

# Important config files to always include regardless of extension
ALWAYS_INCLUDE_BASENAMES = {
    # Package managers
    "package.json", "pyproject.toml", "requirements.txt", "Cargo.toml", "go.mod",
    # TypeScript/JavaScript configs
    "tsconfig.json", "tsconfig.base.json", "jsconfig.json",
    "next.config.js", "next.config.mjs", "vite.config.ts", "vite.config.js",
    "babel.config.js", "babel.config.cjs", "babel.config.json",
    "eslint.config.js", ".eslintrc.json", ".eslintrc.js",
    "jest.config.js", "jest.config.ts", "playwright.config.ts", "vitest.config.ts",
    "webpack.config.js", "rollup.config.js",
    ".prettierrc", ".prettierrc.json", ".prettierrc.js", "prettier.config.js",
    # React Native
    "metro.config.js", "react-native.config.js",
    # Testing
    "cypress.config.ts", "cypress.config.js",
    # CI/CD
    ".gitlab-ci.yml", ".travis.yml", "azure-pipelines.yml"
}

BINARY_EXT = {
    ".apk", ".aar", ".so", ".dll", ".dylib", ".a", ".png", ".jpg", ".jpeg", ".webp", ".gif", ".svg",
    ".jar", ".keystore", ".jks", ".ttf", ".otf", ".ico", ".pdf", ".mp3", ".wav", ".mp4"
}

EXCLUDE_FILES = {
    "local.properties", ".env", ".env.local", ".envrc",
    # Lock files and large metadata
    "yarn.lock", "pnpm-lock.yaml", "package-lock.json", "poetry.lock", "Cargo.lock"
}

# Maximum file size to include (default 256KB, configurable via env)
MAX_FILE_BYTES = int(os.getenv("BUNDLE_MAX_FILE_BYTES", 256 * 1024))

LANG_BY_EXT = {
    # JVM languages
    ".kt": "kotlin",
    ".java": "java",
    ".gradle": "groovy",
    ".kts": "kotlin",
    # Web languages
    ".ts": "typescript",
    ".tsx": "tsx",
    ".js": "javascript",
    ".jsx": "jsx",
    ".cjs": "javascript",
    ".mjs": "javascript",
    # Python
    ".py": "python",
    ".pyx": "python",
    ".pyi": "python",
    # Markup and config
    ".xml": "xml",
    ".md": "markdown",
    ".pro": "conf",
    ".properties": "properties",
    ".json": "json",
    ".yaml": "yaml",
    ".yml": "yaml",
    ".toml": "toml",
    ".ini": "ini",
    ".cfg": "ini",
    ".txt": "text"
}

# ------------------------------ GitHub PR Detection ------------------------------

def detect_github_pr(repo_root: Path) -> dict | None:
    """Detect if there's an open GitHub PR for the current branch.
    Returns PR info dict or None if no PR found."""
    try:
        # Check if gh CLI is available
        result = subprocess.run(
            ["gh", "--version"],
            capture_output=True,
            text=True,
            cwd=repo_root,
            timeout=5
        )
        if result.returncode != 0:
            print("[info] GitHub CLI (gh) not found. Skipping PR detection.")
            return None

        # Get current branch
        result = subprocess.run(
            ["git", "branch", "--show-current"],
            capture_output=True,
            text=True,
            cwd=repo_root,
            timeout=5
        )
        if result.returncode != 0:
            return None
        current_branch = result.stdout.strip()

        # List PRs for current branch
        result = subprocess.run(
            ["gh", "pr", "list", "--head", current_branch, "--json", "number,title,baseRefName,headRefName,url,state"],
            capture_output=True,
            text=True,
            cwd=repo_root,
            timeout=10
        )
        if result.returncode != 0:
            return None

        prs = json.loads(result.stdout)
        if not prs:
            return None

        # Get the first open PR
        for pr in prs:
            if pr.get("state") == "OPEN":
                return pr

        return None
    except Exception as e:
        print(f"[warn] Error detecting GitHub PR: {e}")
        return None


def get_pr_diff(repo_root: Path, pr_info: dict) -> str | None:
    """Get the diff for a PR comparing current branch to base branch."""
    try:
        base_branch = pr_info.get("baseRefName", "main")

        # Get the merge-base to find where branches diverged
        result = subprocess.run(
            ["git", "merge-base", base_branch, "HEAD"],
            capture_output=True,
            text=True,
            cwd=repo_root,
            timeout=5
        )
        if result.returncode != 0:
            # Fallback to simple diff if merge-base fails
            result = subprocess.run(
                ["git", "diff", f"{base_branch}...HEAD"],
                capture_output=True,
                text=True,
                cwd=repo_root,
                timeout=30
            )
        else:
            # Get diff from merge-base to HEAD
            merge_base = result.stdout.strip()
            result = subprocess.run(
                ["git", "diff", f"{merge_base}..HEAD"],
                capture_output=True,
                text=True,
                cwd=repo_root,
                timeout=30
            )

        if result.returncode != 0:
            return None

        return result.stdout
    except Exception as e:
        print(f"[warn] Error getting PR diff: {e}")
        return None


def write_pr_diff_bundle(repo_root: Path, pr_info: dict, diff_content: str, out_dir: Path) -> Path | None:
    """Write PR diff to a separate bundle file."""
    try:
        out_dir.mkdir(parents=True, exist_ok=True)
        out_path = out_dir / "PR_DIFF_BUNDLE.md"

        pr_number = pr_info.get("number", "unknown")
        pr_title = pr_info.get("title", "Untitled PR")
        pr_url = pr_info.get("url", "")
        base_branch = pr_info.get("baseRefName", "main")
        head_branch = pr_info.get("headRefName", "current")
        now = datetime.now(timezone.utc).strftime("%Y-%m-%d %H:%M:%SZ")

        # Parse diff to get statistics
        files_changed = set()
        additions = 0
        deletions = 0

        for line in diff_content.splitlines():
            if line.startswith("diff --git"):
                # Extract filename from diff header
                parts = line.split()
                if len(parts) >= 3:
                    # Remove a/ or b/ prefix
                    fname = parts[2][2:] if parts[2].startswith("a/") else parts[2]
                    files_changed.add(fname)
            elif line.startswith("+") and not line.startswith("+++"):
                additions += 1
            elif line.startswith("-") and not line.startswith("---"):
                deletions += 1

        content = f"""# PR DIFF BUNDLE

Pull Request changes for review.
<!-- Generated by bundle_review.py from https://github.com/Strode-Mountain/machine-shop -->

## PR Information
- **PR Number**: #{pr_number}
- **Title**: {pr_title}
- **URL**: {pr_url}
- **Base Branch**: {base_branch}
- **Head Branch**: {head_branch}
- **Generated**: {now} UTC

## Change Statistics
- **Files Changed**: {len(files_changed)}
- **Lines Added**: {additions:,}
- **Lines Deleted**: {deletions:,}
- **Net Change**: {additions - deletions:+,}

## Changed Files
{chr(10).join(f'- {f}' for f in sorted(files_changed))}

## Full Diff

The following shows all changes that would be merged from `{head_branch}` into `{base_branch}`:

```diff
{diff_content}
```

## Review Focus Areas

When reviewing this PR, consider:
1. **Backwards Compatibility**: Will these changes break existing functionality?
2. **Migration Requirements**: Do these changes require data migration or configuration updates?
3. **Test Coverage**: Are the changes adequately tested?
4. **Documentation**: Are API changes and new features properly documented?
5. **Performance Impact**: Do these changes affect performance characteristics?
6. **Security Implications**: Are there any security considerations with these changes?
"""

        out_path.write_text(content, encoding="utf-8")
        size_mb = out_path.stat().st_size / (1024 * 1024)
        print(f"  Created: {out_path.name} ({size_mb:.2f} MB) - PR #{pr_number} diff")
        return out_path
    except Exception as e:
        print(f"[error] Failed to write PR diff bundle: {e}")
        return None

# ------------------------------ Helpers ------------------------------

def detect_repo_root(via_arg: str | None) -> Path:
    if via_arg:
        return Path(via_arg).resolve()
    # Default: two levels up from this script: repo_root/scripts/code_review/bundle_review.py
    return Path(__file__).resolve().parents[2]


def ensure_gitignore_has_output(repo_root: Path, rel_out: Path) -> None:
    gitignore = repo_root / ".gitignore"
    rel_line = f"/{rel_out.as_posix().rstrip('/')}/\n"
    try:
        if gitignore.exists():
            text = gitignore.read_text(encoding="utf-8", errors="ignore")
            if rel_line.strip() not in {ln.strip() for ln in text.splitlines()}:
                with gitignore.open("a", encoding="utf-8") as f:
                    f.write("\n# Ignore code-review bundle outputs\n")
                    f.write(rel_line)
        else:
            with gitignore.open("w", encoding="utf-8") as f:
                f.write("# Ignore code-review bundle outputs\n")
                f.write(rel_line)
    except Exception as e:
        print(f"[warn] Unable to update .gitignore: {e}")


def cleanup_previous_output(out_dir: Path) -> None:
    """Remove previous bundle and prompt files before generating new ones."""
    patterns = [
        "CODE_REVIEW_BUNDLE*.md",
        "REVIEW_PROMPT.md",
        "PR_DIFF_BUNDLE.md"
    ]
    for pattern in patterns:
        for file in out_dir.glob(pattern):
            file.unlink()
            print(f"  Cleaned up: {file.name}")


def should_include_file(path: Path, repo_root: Path) -> bool:
    name = path.name
    ext = path.suffix.lower()
    
    # Exclude blacklisted files and binary files
    if name in EXCLUDE_FILES or ext in BINARY_EXT:
        return False
    
    # Always include important config files
    if name in ALWAYS_INCLUDE_BASENAMES:
        return True
    
    # Check standard include rules
    if name in INCLUDE_NAMES or ext in INCLUDE_EXT:
        # Apply size limit to prevent huge files
        try:
            if path.stat().st_size > MAX_FILE_BYTES:
                return False
        except Exception:
            pass
        return True
    
    return False


def detect_lang(path: Path) -> str:
    return LANG_BY_EXT.get(path.suffix.lower(), "")


def read_text(path: Path) -> list[str]:
    try:
        return path.read_text(encoding="utf-8", errors="strict").splitlines()
    except Exception:
        return path.read_text(encoding="latin-1", errors="replace").splitlines()


def collect_files(repo_root: Path, max_files: int | None) -> list[Path]:
    files: list[Path] = []
    for root, dirs, fnames in os.walk(repo_root):
        root_path = Path(root)

        # Prune directories at the repo root (only when walking the root)
        if root_path == repo_root:
            dirs[:] = [d for d in dirs if d not in ROOT_EXCLUDE_DIRS]
        # Global pruning anywhere
        dirs[:] = [d for d in dirs if d not in GLOBAL_EXCLUDE_DIRS]

        # Also prune the output directory anywhere it appears
        # (resolved against repo root to be safe on first level)
        rels = [Path(d) for d in dirs]
        pruned = []
        for d in rels:
            absd = root_path / d
            if absd.resolve() == (repo_root / REL_OUT_DIR).resolve():
                continue
            pruned.append(d.name)
        dirs[:] = pruned

        for fname in fnames:
            fpath = root_path / fname
            # Skip anything inside the output dir
            try:
                if (repo_root / REL_OUT_DIR) in fpath.resolve().parents:
                    continue
            except Exception:
                pass
            if should_include_file(fpath, repo_root):
                files.append(fpath)

    files.sort(key=lambda p: (p.stat().st_mtime, p.as_posix()))  # stable, mtime increasing
    if max_files and len(files) > max_files:
        # Keep the most recent N files
        files = files[-max_files:]
    return files


def make_toc_anchor(path_str: str) -> str:
    return re.sub(r"[^a-z0-9]+", "-", path_str.lower()).strip('-')


# ------------------------------ Writers ------------------------------

def write_bundle_md(repo_root: Path, files: list[Path], out_dir: Path, max_bundle_mb: int = 8) -> list[Path]:
    """Write bundle MD file(s), splitting if content exceeds max_bundle_mb.
    Returns list of paths to all created files.
    
    Generated by bundle_review.py from https://github.com/Strode-Mountain/machine-shop
    """
    MAX_SIZE_BYTES = max_bundle_mb * 1024 * 1024
    out_dir.mkdir(parents=True, exist_ok=True)
    
    # Pre-scan for metadata
    rels = [p.relative_to(repo_root) for p in files]
    modules = sorted({str(p).split("/")[0] for p in rels if "/" in str(p)})
    manifests = [str(p) for p in rels if p.name == "AndroidManifest.xml"]
    gradle_files = [str(p) for p in rels if p.suffix in {".gradle", ".kts"} or p.name.startswith("settings.gradle")]
    package_files = [str(p) for p in rels if p.name in {"package.json", "pyproject.toml", "Cargo.toml", "go.mod"}]
    
    todos: list[str] = []
    for p in files:
        # Scan more file types for TODOs
        if p.suffix.lower() in {".kt", ".java", ".gradle", ".kts", ".xml", ".py", ".ts", ".tsx", ".js", ".jsx"}:
            try:
                for i, line in enumerate(read_text(p), start=1):
                    if re.search(r"\b(TODO|FIXME|XXX|HACK|BUG)\b", line):
                        todos.append(f"- {p.relative_to(repo_root)}:{i} {line.strip()[:160]}")
            except Exception:
                pass
    
    now = datetime.now(timezone.utc).strftime("%Y-%m-%d %H:%M:%SZ")
    
    # Build header content
    header_lines = [
        "# CODE_REVIEW_BUNDLE\n\n",
        "Auto-generated for comprehensive static review.\n",
        "<!-- Generated by bundle_review.py from https://github.com/Strode-Mountain/machine-shop -->\n\n",
        "## Overview\n",
        f"- **Generated**: {now} UTC\n",
        f"- **Files**: {len(files)} total\n",
        f"- **Modules**: {', '.join(modules) if modules else '(single-module)'}\n",
        f"- **Manifests**: {', '.join(manifests) or '(none found)'}\n",
        f"- **Gradle files**: {', '.join(gradle_files) or '(none found)'}\n",
        f"- **Package files**: {', '.join(package_files) or '(none found)'}\n",
        "- **TODO/FIXME/XXX/HACK/BUG sample**:\n",
        ("\n".join(todos[:30]) or "(none found)") + "\n\n"
    ]
    
    # Initialize tracking for file splitting
    bundle_files = []
    current_part = 1
    current_size = 0
    current_content = []
    
    def write_current_part() -> Path:
        """Write the current part to a file."""
        nonlocal current_part, current_size, current_content
        
        if current_part == 1 and len([p for p in files]) * 1000 < MAX_SIZE_BYTES:
            # Single file if small enough
            out_path = out_dir / "CODE_REVIEW_BUNDLE.md"
        else:
            # Multiple files with numbering
            out_path = out_dir / f"CODE_REVIEW_BUNDLE_{current_part:03d}.md"
        
        with out_path.open("w", encoding="utf-8") as f:
            f.write("".join(current_content))
        
        bundle_files.append(out_path)
        file_size_mb = current_size / (1024 * 1024)
        print(f"  Created: {out_path.name} ({file_size_mb:.2f} MB)")
        
        current_part += 1
        current_size = 0
        current_content = []
        return out_path
    
    def add_content(text: str) -> None:
        """Add content and track size."""
        nonlocal current_size, current_content
        content_bytes = text.encode("utf-8")
        current_size += len(content_bytes)
        current_content.append(text)
    
    # Add header to first part
    for line in header_lines:
        add_content(line)
    
    # Add table of contents (only in first file)
    add_content("## Table of Contents\n")
    for p in rels:
        anchor = make_toc_anchor(str(p))
        add_content(f"- [{p}](#{anchor})\n")
    add_content("\n---\n")
    
    # Process each file
    for p in files:
        rel = p.relative_to(repo_root)
        lang = detect_lang(p)
        
        # Build file content
        file_content = []
        file_content.append(f"\n## {rel}\n\n")
        file_content.append(f"```{lang}\n")
        
        lines = read_text(p)
        # Add line numbers for code files
        codeish = lang in {"kotlin", "java", "groovy", "typescript", "javascript", "python"}
        prefix = "// " if lang in {"kotlin", "java", "groovy", "typescript", "javascript"} else ("# " if lang in {"python", "yaml", "bash"} else "")
        
        if prefix:
            for i, line in enumerate(lines, start=1):
                file_content.append(f"{prefix}L{i:04d} {line}\n")
        else:
            for line in lines:
                file_content.append(f"{line}\n")
        file_content.append("```\n")
        
        # Check if adding this file would exceed the limit
        file_text = "".join(file_content)
        file_bytes = len(file_text.encode("utf-8"))
        
        if current_size + file_bytes > MAX_SIZE_BYTES and current_content:
            # Write current part and start a new one
            write_current_part()
            # Add continuation header for new part
            add_content(f"# CODE_REVIEW_BUNDLE (Part {current_part})\n\n")
            add_content(f"Continuation from Part {current_part - 1}\n\n")
        
        # Add the file content
        add_content(file_text)
    
    # Write any remaining content
    if current_content:
        write_current_part()
    
    return bundle_files


def write_prompt_md(repo_root: Path, files: list[Path], out_dir: Path, bundle_files: list[Path], pr_diff_file: Path | None = None) -> Path:
    out_path = out_dir / "REVIEW_PROMPT.md"
    rels = [p.relative_to(repo_root) for p in files]
    
    # Reference the bundle files appropriately
    if len(bundle_files) == 1:
        bundle_ref = "**CODE_REVIEW_BUNDLE.md**"
        bundle_note = ""
    else:
        bundle_names = ", ".join([f"**{f.name}**" for f in bundle_files])
        bundle_ref = f"the following bundle files: {bundle_names}"
        bundle_note = "\n\n**Note**: Due to size, the bundle has been split into multiple files. Review them in sequence."

    # Add PR diff reference if available
    pr_note = ""
    if pr_diff_file:
        pr_note = f"\n\n**Pull Request Diff**: Review **{pr_diff_file.name}** for proposed changes that would be merged."

    content = f"""
# Review Instructions (Companion Prompt)
You are reviewing a project bundle provided as {bundle_ref}. Treat it as read-only source; paths reflect the original repo.{bundle_note}{pr_note}

## Goals
1. **Architecture**: Evaluate design patterns, dependency management, module structure, separation of concerns.
2. **Platform-Specific Issues**:
   - Android: Lifecycle, background work, navigation, configuration changes
   - Web: Browser compatibility, state management, routing, bundling
   - Backend: API design, database patterns, authentication, scalability
3. **Security & Privacy**: Authentication, authorization, data validation, secrets management, OWASP compliance.
4. **Performance**: Load times, memory usage, network efficiency, caching strategies, optimization opportunities.
5. **Reliability**: Error handling, fault tolerance, logging, monitoring hooks, graceful degradation.
6. **Testing**: Test coverage, test quality, mocking strategies, edge cases, integration test gaps.
7. **Code Quality**: Readability, maintainability, documentation, type safety, linting compliance.
8. **PR-Specific Review** (if PR diff provided):
   - Validate changes against PR description and intent
   - Check for unintended changes or missing files
   - Ensure changes are complete and don't leave the codebase in an inconsistent state
   - Review for merge conflicts or compatibility issues with the base branch

## How to reference code
- Use the file headers and line numbers (e.g., `app/src/main/java/.../Foo.kt L0123`).
- Propose concrete patches or diff hunks when possible.

## Deliverables
- Top-level findings list (critical ➜ minor).
- File-specific comments grouped by path and line ranges.
- A prioritized refactor plan (1–2 weeks, 4–6 weeks).
- Risk register (user data, crashes, regressions) and quick mitigations.

## Context
- Bundle includes: Source code, configuration files, documentation, test files.
- Binaries, build outputs, secrets, images, and lock files are intentionally excluded.
- Root directories excluded from the scan: {', '.join(sorted(ROOT_EXCLUDE_DIRS))} (plus global ignores).
- Files larger than {MAX_FILE_BYTES // 1024}KB are skipped to prevent bundle bloat.

Report succinctly but precisely. Prefer code blocks and diffs over prose when giving fixes.
""".strip()

    out_dir.mkdir(parents=True, exist_ok=True)
    out_path.write_text(content, encoding="utf-8")
    return out_path


# ------------------------------ Main ------------------------------

def main():
    ap = argparse.ArgumentParser(description="Generate code review bundle and prompt (with automatic splitting for large outputs).")
    ap.add_argument("--root", type=str, default=None, help="Repo root (defaults to ../../ from this script)")
    ap.add_argument("--max-files", type=int, default=None, help="Optional cap on number of files (keeps most recent N)")
    ap.add_argument("--max-bundle-mb", type=int, default=int(os.getenv("BUNDLE_MAX_BUNDLE_MB", 8)),
                    help="Maximum size per bundle file in MB (default 8MB)")
    args = ap.parse_args()

    repo_root = detect_repo_root(args.root)
    out_dir = repo_root / REL_OUT_DIR

    # Clean up previous output
    if out_dir.exists():
        print("Cleaning up previous output...")
        cleanup_previous_output(out_dir)

    ensure_gitignore_has_output(repo_root, REL_OUT_DIR)

    files = collect_files(repo_root, args.max_files)
    if not files:
        print("No files matched include rules. Check your repository paths and config.")
        return 1

    print(f"Processing {len(files)} files...")
    bundle_paths = write_bundle_md(repo_root, files, out_dir, args.max_bundle_mb)

    # Check for GitHub PR and generate diff bundle if found
    pr_diff_file = None
    pr_info = detect_github_pr(repo_root)
    if pr_info:
        pr_number = pr_info.get("number", "unknown")
        pr_title = pr_info.get("title", "Untitled")
        print(f"\nDetected open PR #{pr_number}: {pr_title}")
        print("Generating PR diff bundle...")

        diff_content = get_pr_diff(repo_root, pr_info)
        if diff_content:
            pr_diff_file = write_pr_diff_bundle(repo_root, pr_info, diff_content, out_dir)
            if not pr_diff_file:
                print("[warn] Failed to create PR diff bundle")
        else:
            print("[warn] Could not retrieve PR diff")
    else:
        print("\n[info] No open GitHub PR detected for current branch")

    prompt_path = write_prompt_md(repo_root, files, out_dir, bundle_paths, pr_diff_file)

    print(f"\n✅ Successfully created {len(bundle_paths)} bundle file(s):")
    for bp in bundle_paths:
        size_mb = bp.stat().st_size / (1024 * 1024)
        print(f"   - {bp.name} ({size_mb:.2f} MB)")
    if pr_diff_file:
        size_mb = pr_diff_file.stat().st_size / (1024 * 1024)
        print(f"✅ Created PR diff bundle: {pr_diff_file.name} ({size_mb:.2f} MB)")
    print(f"✅ Wrote prompt: {prompt_path.name}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
