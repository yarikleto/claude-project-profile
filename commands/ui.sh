# ui.sh — Claude Code status line integration

# Run a JSON transformation using the first available tool (jq, python3, node).
# Usage: _json_transform FILE MODE KEY [VALUE]
#   MODE is "merge" (set key to a statusLine-style object) or "delete" (remove key).
_json_transform() {
  local file="$1" mode="$2" key="$3" value="${4:-}"
  local tmp

  if command -v jq &>/dev/null; then
    tmp="$(mktemp)"
    local ok=false
    case "$mode" in
      merge)  jq --arg k "$key" --arg v "$value" '. + {($k): {"type": "command", "command": $v}}' "$file" > "$tmp" 2>/dev/null && ok=true ;;
      delete) jq --arg k "$key" 'del(.[$k])' "$file" > "$tmp" 2>/dev/null && ok=true ;;
    esac
    if [[ "$ok" == true ]]; then mv "$tmp" "$file"; return 0; fi
    rm -f "$tmp"
  fi

  if command -v python3 &>/dev/null; then
    case "$mode" in
      merge)
        python3 -c "
import json, sys
p = sys.argv[1]
with open(p) as f: d = json.load(f)
d[sys.argv[2]] = {'type': 'command', 'command': sys.argv[3]}
with open(p, 'w') as f: json.dump(d, f, indent=2)
" "$file" "$key" "$value" 2>/dev/null && return 0 ;;
      delete)
        python3 -c "
import json, sys
p = sys.argv[1]
with open(p) as f: d = json.load(f)
d.pop(sys.argv[2], None)
with open(p, 'w') as f: json.dump(d, f, indent=2)
" "$file" "$key" 2>/dev/null && return 0 ;;
    esac
  fi

  if command -v node &>/dev/null; then
    case "$mode" in
      merge)
        node -e "
const fs=require('fs'), f=process.argv[1];
const d=JSON.parse(fs.readFileSync(f,'utf8'));
d[process.argv[2]]={type:'command',command:process.argv[3]};
fs.writeFileSync(f,JSON.stringify(d,null,2)+'\n');
" "$file" "$key" "$value" 2>/dev/null && return 0 ;;
      delete)
        node -e "
const fs=require('fs'), f=process.argv[1];
const d=JSON.parse(fs.readFileSync(f,'utf8'));
delete d[process.argv[2]];
fs.writeFileSync(f,JSON.stringify(d,null,2)+'\n');
" "$file" "$key" 2>/dev/null && return 0 ;;
    esac
  fi

  return 1
}

# Safely merge a key into a JSON file. Uses jq, python3, or node.
_json_merge() { _json_transform "$1" merge "$2" "$3"; }

# Remove a key from a JSON file. Uses jq, python3, or node.
_json_remove_key() { _json_transform "$1" delete "$2"; }

cmd_statusline() {
  local action="${1:-install}"
  _ensure_paths

  local claude_dir="$PROJECT_ROOT/.claude"
  local statusline_script="$PROFILES_DIR/statusline.sh"

  case "$action" in
    install)
      if [[ -L "$statusline_script" ]]; then
        err "Refusing to overwrite symlink at $statusline_script"
        exit 1
      fi

      # Write the statusline script
      cat > "$statusline_script" <<'SCRIPT'
#!/bin/bash
input=$(cat)
model=$(echo "$input" | grep -o '"display_name":"[^"]*"' | head -1 | cut -d'"' -f4)
model="${model:-Claude}"

# Find project root via git
project_root="$(git rev-parse --show-toplevel 2>/dev/null)"
if [[ -n "$project_root" ]]; then
  profile_file="$project_root/.claude-profiles/.current"
  if [[ -f "$profile_file" ]]; then
    profile="$(tr -cd 'a-zA-Z0-9._-' < "$profile_file")"
    echo "${model} · project-profile: ${profile}"
    exit 0
  fi
fi

# No project profile — fall through to model only
# (global claude-profile statusline will handle global profile if installed at ~/.claude/settings.json)
echo "${model}"
SCRIPT
      chmod +x "$statusline_script"

      # Write to project-level settings
      local settings="$claude_dir/settings.json"
      mkdir -p "$claude_dir"

      if [[ -f "$settings" ]]; then
        if grep -q '"statusLine"' "$settings"; then
          warn "statusLine already configured in project settings.json"
          info "Manually set it to:"
          echo "  \"statusLine\": { \"type\": \"command\", \"command\": \"$statusline_script\" }"
        else
          if _json_merge "$settings" "statusLine" "$statusline_script"; then
            ok "Status line configured in project settings.json"
          else
            err "Could not update settings.json (no jq, python3, or node found)"
            info "Add manually to .claude/settings.json:"
            echo "  \"statusLine\": { \"type\": \"command\", \"command\": \"$statusline_script\" }"
            exit 1
          fi
        fi
      else
        echo "{ \"statusLine\": { \"type\": \"command\", \"command\": \"$statusline_script\" } }" > "$settings"
        ok "Created project settings.json with status line"
      fi

      ok "Status line installed at ${BOLD}$statusline_script${NC}"
      info "Restart Claude Code to see: ${DIM}model · project-profile: name${NC}"
      ;;

    uninstall)
      if [[ -f "$statusline_script" ]]; then
        rm "$statusline_script"
        ok "Removed ${BOLD}$statusline_script${NC}"
      else
        warn "No status line script found"
      fi

      # Remove statusLine from project settings
      local settings="$claude_dir/settings.json"
      if [[ -f "$settings" ]] && grep -q '"statusLine"' "$settings"; then
        if _json_remove_key "$settings" "statusLine"; then
          ok "Removed statusLine from project settings.json"
        else
          warn "Could not remove statusLine from settings.json — remove manually"
        fi
      fi
      ;;

    *)
      err "Usage: claude-project-profile statusline ${BOLD}install${NC}|${BOLD}uninstall${NC}"
      exit 1
      ;;
  esac
}
