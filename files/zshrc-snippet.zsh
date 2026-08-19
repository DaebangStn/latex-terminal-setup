# Run agents under TFormula by default so LaTeX renders as Kitty-graphics images.
# Safe as the default because hrmath spoofs argv[0] to the agent kind, and that is
# what herdr identifies a pane's agent by -- so the sidebar entry, hrname,
# working/idle state and `herdr agent prompt` keep working. `hrclaude`/`hrcodex`
# in ~/.local/bin do the same thing explicitly.
#
# Guards: HERDR_ENV (images only survive herdr's Ghostty core), TFORMULA_ACTIVE
# (tformula sets it in the child env -- prevents nesting), a TTY on both ends, and
# the headless subcommands, which must stay a clean pipe.
# Escape hatch: HRMATH_AGENTS=0, or `command claude ...`.
_hrmath_should_wrap() {
  [[ ${HRMATH_AGENTS:-1} == 1 && ${HERDR_ENV:-} == 1 && ${TFORMULA_ACTIVE:-} != 1 ]] \
    && [[ -t 0 && -t 1 ]] && (( $+commands[hrmath] ))
}

claude() {
  if _hrmath_should_wrap; then
    local arg
    for arg in "$@"; do
      case $arg in
        -p|--print) command claude "$@"; return $? ;;
      esac
    done
    hrmath claude "$@"
    return $?
  fi
  command claude "$@"
}

codex() {
  # `codex exec` is the headless mode; leave it unwrapped.
  if [[ ${1:-} != exec ]] && _hrmath_should_wrap; then
    hrmath codex "$@"
    return $?
  fi
  command codex "$@"
}
