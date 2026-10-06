# Project Guide

Purpose: automate a fresh Debian/Ubuntu sing-box VLESS Reality VPS deployment and produce Clash Party/Shadowrocket client files.

## Files

- `SKILL.md`: Codex routing and operational boundaries.
- `scripts/deploy.py`: Mac-side SSH orchestration and client/report generation.
- `scripts/remote_deploy.sh`: root-only remote installation and checks.
- `scripts/test_deploy.py`: focused local tests.
- `references/deploy.md`: manual procedure and automation limits.

## Verification

Run `python3 scripts/test_deploy.py`, `python3 scripts/deploy.py --help`, and `bash -n scripts/remote_deploy.sh` after changes. A real deployment requires an explicitly supplied test VPS; never imply local tests prove network access or client egress.

## Constraints

Do not commit node credentials, generated client configs, SSH keys, or VPS reports. Do not disable SSH host-key verification. Stop when an existing sing-box config or occupied port would be overwritten. Keep provider firewall changes and client import as explicitly separate steps.

GitHub publishing: review `git status` and staged diff before commit/push. Do not add files outside this repository.
