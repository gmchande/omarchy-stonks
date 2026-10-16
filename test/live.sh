#!/usr/bin/env bash
# Deploy a committed ref to the live plugin worktree and restart the shell.
set -euo pipefail
live="$HOME/.config/omarchy/plugins/grvc.stonks"
ref="${1:?usage: test/live.sh <branch-or-commit>}"
if [ -n "$(git -C "$live" status --porcelain)" ]; then echo "refusing: $live has local changes" >&2; exit 1; fi
if ! git -C "$live" rev-parse --verify --quiet "$ref^{commit}" > /dev/null; then echo "refusing: no such ref: $ref" >&2; exit 1; fi
git -C "$live" checkout --quiet --detach "$ref"
omarchy restart shell
git -C "$live" log -1 --oneline
