#!/usr/bin/env bash
# Remote installer for claude-project-profile
# Usage: curl -fsSL https://raw.githubusercontent.com/yarikleto/claude-project-profile/main/remote-install.sh | bash
set -euo pipefail

REPO="https://github.com/yarikleto/claude-project-profile.git"
CLONE_DIR="$(mktemp -d)"
trap 'rm -rf "$CLONE_DIR"' EXIT

echo "Installing claude-project-profile..."
git clone --depth 1 "$REPO" "$CLONE_DIR/claude-project-profile" 2>/dev/null
bash "$CLONE_DIR/claude-project-profile/install.sh"
