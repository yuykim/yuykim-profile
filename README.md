# yuykim Profile

Development environment profile for rebuilding my machines after a format or laptop/desktop change.

This repo does not keep a hand-written inventory. Run the collector scripts to generate a fresh machine snapshot.

## Collect

```powershell
Set-ExecutionPolicy -Scope Process Bypass
.\scripts\collect-all.ps1
```

Generated output:

```txt
data/machines/<machine-id>/*.json
data/summary.json
dev_env/index.md
dev_env/machines/<machine-id>.md
```

## Machine Identity

Edit `.dev-env.json` when a machine needs a stable public name.

```json
{
  "machine": {
    "id": "main-laptop",
    "label": "Main Laptop",
    "role": "daily development"
  }
}
```

If `machine.id` is empty, the collector derives it from the Windows computer name.

## Privacy

The collectors avoid serial numbers, MAC addresses, IP addresses, environment variable values, tokens, and full user-home paths. Keep private notes in `private/`; that folder is ignored by git.

## Publish

Push changes to this repo after running `scripts/collect-all.ps1`. The GitHub Actions workflow sends a `dev_env_updated` dispatch event to `yuykim/yuykim-dev-diary`, where the public `dev_env` page is imported and deployed.
