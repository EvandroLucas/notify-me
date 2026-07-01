#!/usr/bin/env bash
# capture-prompt.sh - runs on UserPromptSubmit on macOS/Linux. Reads the hook JSON from stdin,
# extracts prompt + session_id and writes a short line to
# ${TMPDIR:-/tmp}/claude-toast-prompts/<session_id>.txt for notify.sh to build the summary.
# Silent and fault-tolerant. On Windows (Git Bash/MSYS) it does nothing - capture-prompt.ps1 handles it.
set -u

# Only macOS and Linux are handled; anything else (e.g. Windows shells) exits immediately.
case "$(uname -s 2>/dev/null || echo unknown)" in
  Darwin|Linux) ;;
  *) exit 0 ;;
esac

# Exit if stdin is a terminal (nothing piped in).
[ -t 0 ] && exit 0
# RAW: the raw hook JSON read from stdin; exit if empty.
RAW="$(cat)"
[ -z "$RAW" ] && exit 0

# json_get: extracts a top-level string value from the hook JSON. Best-effort and tolerant: tries
# python3 (handles escapes/unicode) -> jq -> sed, falling through whenever the result is empty.
json_get() {
  local v=""
  if command -v python3 >/dev/null 2>&1; then
    v="$(printf '%s' "$RAW" | python3 -c 'import sys,json
try:
    print(json.load(sys.stdin).get(sys.argv[1],"") or "")
except Exception:
    pass' "$1" 2>/dev/null)"
  fi
  if [ -z "$v" ] && command -v jq >/dev/null 2>&1; then
    v="$(printf '%s' "$RAW" | jq -r --arg k "$1" '.[$k] // ""' 2>/dev/null)"
  fi
  if [ -z "$v" ]; then
    v="$(printf '%s' "$RAW" | sed -n "s/.*\"$1\"[[:space:]]*:[[:space:]]*\"\([^\"]*\)\".*/\1/p" | head -n1)"
  fi
  printf '%s' "$v"
}

# SID / PROMPT: the session id and prompt text pulled from the hook JSON. Both are required; exit if
# either is missing.
SID="$(json_get session_id)"
PROMPT="$(json_get prompt)"
[ -z "$SID" ] && exit 0
[ -z "$PROMPT" ] && exit 0

# DIR: the shared temp folder for per-session prompt files; created if needed (exit if that fails).
DIR="${TMPDIR:-/tmp}/claude-toast-prompts"
mkdir -p "$DIR" 2>/dev/null || exit 0

# LINE: the prompt collapsed to a single line (whitespace runs -> one space, trimmed) and capped at
# 200 chars so the stored summary stays short.
LINE="$(printf '%s' "$PROMPT" | tr '\n\t' '  ' | sed 's/  */ /g; s/^ //; s/ *$//')"
[ "${#LINE}" -gt 200 ] && LINE="${LINE:0:200}"

# Write the summary line to this session's file (<session_id>.txt) for notify.sh to read later.
printf '%s' "$LINE" > "$DIR/$SID.txt" 2>/dev/null
