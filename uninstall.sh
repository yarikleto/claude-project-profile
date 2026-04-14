#!/usr/bin/env bash
# uninstall.sh — Remove claude-project-profile from ~/.local/bin
set -euo pipefail

INSTALL_DIR="${INSTALL_DIR:-$HOME/.local/bin}"
INSTALL_PATH="$INSTALL_DIR/claude-project-profile"

if [[ -f "$INSTALL_PATH" ]]; then
  rm "$INSTALL_PATH"
  echo "Removed $INSTALL_PATH"
else
  echo "claude-project-profile not found at $INSTALL_PATH"
fi

# Remove shell completions
ZSH_COMP_DIR="${ZSH_COMP_DIR:-$HOME/.local/share/zsh/site-functions}"
BASH_COMP_DIR="${BASH_COMP_DIR:-$HOME/.local/share/bash-completion/completions}"

[[ -f "$ZSH_COMP_DIR/_claude-project-profile" ]] && rm "$ZSH_COMP_DIR/_claude-project-profile" && echo "Removed zsh completions"
[[ -f "$BASH_COMP_DIR/claude-project-profile.bash" ]] && rm "$BASH_COMP_DIR/claude-project-profile.bash" && echo "Removed bash completions"

echo ""
echo "Uninstalled. Profile data in each project's .claude-profiles/ is untouched."
echo "Remove it manually if you want: rm -rf <project>/.claude-profiles"
