#!/usr/bin/env bash
# install.sh — Install claude-project-profile to ~/.local/bin
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
INSTALL_DIR="${INSTALL_DIR:-$HOME/.local/bin}"
INSTALL_PATH="$INSTALL_DIR/claude-project-profile"

echo "Installing claude-project-profile..."

mkdir -p "$INSTALL_DIR"

# Create wrapper script that sources from the repo
cat > "$INSTALL_PATH" <<EOF
#!/usr/bin/env bash
exec "$SCRIPT_DIR/claude-project-profile" "\$@"
EOF
chmod +x "$INSTALL_PATH"

echo "Installed to $INSTALL_PATH"

# Check if INSTALL_DIR is in PATH
if [[ ":$PATH:" != *":$INSTALL_DIR:"* ]]; then
  echo ""
  echo "Add $INSTALL_DIR to your PATH:"
  echo "  export PATH=\"$INSTALL_DIR:\$PATH\""
  echo ""
  echo "Add this to your ~/.zshrc or ~/.bashrc to make it permanent."
fi

# Install shell completions
COMP_DIR="$SCRIPT_DIR/completions"
if [[ -d "$COMP_DIR" ]]; then
  # Zsh completions
  ZSH_COMP_DIR="${ZSH_COMP_DIR:-$HOME/.local/share/zsh/site-functions}"
  if [[ -f "$COMP_DIR/_claude-project-profile" ]]; then
    mkdir -p "$ZSH_COMP_DIR"
    cp "$COMP_DIR/_claude-project-profile" "$ZSH_COMP_DIR/"
    echo "Zsh completions installed to $ZSH_COMP_DIR"
  fi

  # Bash completions
  BASH_COMP_DIR="${BASH_COMP_DIR:-$HOME/.local/share/bash-completion/completions}"
  if [[ -f "$COMP_DIR/claude-project-profile.bash" ]]; then
    mkdir -p "$BASH_COMP_DIR"
    cp "$COMP_DIR/claude-project-profile.bash" "$BASH_COMP_DIR/"
    echo "Bash completions installed to $BASH_COMP_DIR"
  fi
fi

echo ""
echo "Done! Run 'claude-project-profile help' to get started."
echo "Open a new shell to load tab completion: exec zsh or exec bash"
