# Code Review Bundler

A universal code review bundler that creates comprehensive Markdown documentation of your codebase for AI-assisted review.

**Source**: https://github.com/Strode-Mountain/machine-shop

## Features

- **Universal language support**: Works with Android, JavaScript/TypeScript, Python, and more
- **Automatic file splitting**: Splits large bundles when they exceed size limits (default 8MB)
- **Smart file selection**: Includes source code and important configs, excludes binaries and lock files
- **Previous output cleanup**: Automatically removes old bundle files before generating new ones
- **TODO/FIXME tracking**: Scans for and summarizes TODO, FIXME, XXX, HACK, and BUG comments
- **Configurable limits**: Control maximum file size and bundle size via arguments or environment variables
- **GitHub PR integration**: Automatically detects open PRs and creates a separate diff bundle for merge review

## Outputs

Generated in `scripts/code_review/output/`:
- `CODE_REVIEW_BUNDLE.md` (or `CODE_REVIEW_BUNDLE_001.md`, `_002.md`, etc. for large codebases)
- `REVIEW_PROMPT.md` — AI reviewer instructions that reference the bundle file(s)
- `PR_DIFF_BUNDLE.md` — (Optional) Generated when an open GitHub PR is detected, contains the full diff for merge review

## Usage

### Basic Usage

```bash
# From repo root (recommended)
python3 scripts/code_review/bundle_review.py

# Or from anywhere
python3 scripts/code_review/bundle_review.py --root /path/to/repo
```

### GitHub PR Detection

The script automatically detects if there's an open GitHub PR for the current branch:
- Requires GitHub CLI (`gh`) to be installed and authenticated
- Creates a separate `PR_DIFF_BUNDLE.md` with the full diff
- Shows what changes would be merged into the base branch
- Includes change statistics and affected files list

### Advanced Options

```bash
# Limit the number of files included (keeps most recent N)
python3 scripts/code_review/bundle_review.py --max-files 800

# Set maximum bundle size (in MB, default is 8)
python3 scripts/code_review/bundle_review.py --max-bundle-mb 20

# Combine options
python3 scripts/code_review/bundle_review.py --root /path/to/repo --max-files 500 --max-bundle-mb 10
```

## Environment Variables

```bash
# Set default maximum file size to include (bytes, default 256KB)
export BUNDLE_MAX_FILE_BYTES=524288  # 512KB

# Set default maximum bundle size (MB, default 8)
export BUNDLE_MAX_BUNDLE_MB=20
```
