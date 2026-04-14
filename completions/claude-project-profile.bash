_claude_project_profile() {
  local cur prev commands
  COMPREPLY=()
  cur="${COMP_WORDS[COMP_CWORD]}"
  prev="${COMP_WORDS[COMP_CWORD-1]}"
  commands="new fork use list current show edit delete deactivate save history diff restore statusline version help"

  if [[ ${COMP_CWORD} -eq 1 ]]; then
    COMPREPLY=($(compgen -W "$commands" -- "$cur"))
    return 0
  fi

  local profiles_dir
  profiles_dir="$(git rev-parse --show-toplevel 2>/dev/null)/.claude-profiles"

  case "${COMP_WORDS[1]}" in
    use|show|edit|delete|history|diff|restore|save)
      if [[ -d "$profiles_dir" ]]; then
        local profiles
        profiles="$(command ls -1 "$profiles_dir" 2>/dev/null | grep -v '^\.')"
        COMPREPLY=($(compgen -W "$profiles" -- "$cur"))
      fi
      ;;
    deactivate)
      COMPREPLY=($(compgen -W "--keep" -- "$cur"))
      ;;
    statusline)
      COMPREPLY=($(compgen -W "install uninstall" -- "$cur"))
      ;;
  esac

  return 0
}

complete -F _claude_project_profile claude-project-profile
