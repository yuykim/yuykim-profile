# yuykim Profile

Development environment profile for rebuilding my machines after a format or laptop/desktop change.

This repo does not keep a hand-written inventory. Run the collector scripts to generate a fresh machine snapshot.

## Quick Start

Windows:

```powershell
Set-ExecutionPolicy -Scope Process Bypass
.\scripts\collect-all.ps1
```

macOS/Linux:

```bash
chmod +x scripts/collect-all.sh
./scripts/collect-all.sh
```

Generated output:

```txt
data/machines/<machine-id>/*.json
data/summary.json
dev_env/index.md
dev_env/machines/<machine-id>.md
```

## Script Guide

`scripts/collect-all.ps1`

Runs the full Windows collector. Use this on the current Windows laptop or desktop.

`scripts/collect-all.sh`

Runs the macOS/Linux collector through Node.js. Use this on a Mac or Linux machine. Node.js must already be installed.

`scripts/collect-all.mjs`

Cross-platform collector used by `collect-all.sh`. It can also be run directly:

```bash
node scripts/collect-all.mjs
```

The smaller PowerShell scripts are convenience aliases for the full collector:

```txt
collect-system.ps1
collect-languages.ps1
collect-tools.ps1
collect-editors.ps1
collect-agents.ps1
collect-vscode-extensions.ps1
scan-workspace.ps1
render-dev-env.ps1
```

They currently call `collect-all.ps1`, so the output is always regenerated as one consistent snapshot.

## Normal Update Flow

1. Edit `.dev-env.json` if this is a new machine or the machine label/model changed.
2. Run the collector for the current OS.
3. Review generated files before committing:

```bash
git status
git diff
```

4. Check that no private path or token-like value is present:

```bash
rg -n "(C:\\\\Users|/Users/|AppData|OPENAI_API_KEY|GITHUB_TOKEN|access_token|password\\s*=|secret\\s*=|api_key\\s*=)" data dev_env
```

5. Commit and push:

```bash
git add .dev-env.json data dev_env scripts
git commit -m "docs: update dev environment snapshot"
git push
```

After push, GitHub Actions sends the update to `yuykim/yuykim-dev-diary`.

## Machine Identity

Edit `.dev-env.json` when a machine needs a stable public name.

```json
{
  "machine": {
    "id": "main-laptop",
    "label": "Main Laptop",
    "role": "daily development",
    "model": "ASUS TUF Gaming A14 FA401UV-RG025"
  }
}
```

If `machine.id` is empty, the collector derives it from the computer name. Set a stable `id` before collecting on multiple machines.

Recommended examples:

```txt
main-laptop
home-desktop
macbook
lab-pc
```

## What It Collects

- System: OS, CPU, RAM, GPU, disks, manufacturer/model
- Languages/runtimes: Python, Node.js, npm, pnpm, Java, .NET, Go, Rust, Git
- Tools: VS Code, Cursor, Unity Hub, Docker, WSL, Conda, Android tools, GitHub CLI, Homebrew on macOS
- Editor extensions: VS Code and Cursor extensions when their CLI commands are available
- Agents: Codex, Claude Code, Gemini CLI, OpenAI CLI, and agent-like editor extensions
- Workspace usage signals: `package.json`, `requirements.txt`, `pyproject.toml`, `.ipynb`, Unity projects, `.sln`, `.csproj`, Docker files

## Privacy

The collectors avoid serial numbers, MAC addresses, IP addresses, environment variable values, tokens, and full user-home paths. Keep private notes in `private/`; that folder is ignored by git.

## Publish

Push changes to this repo after running the collector. The GitHub Actions workflow sends a `dev_env_updated` dispatch event to `yuykim/yuykim-dev-diary`, where the public `dev_env` page is imported and deployed.

Required GitHub Actions secret in this repo:

```txt
BLOG_DISPATCH_TOKEN
```
