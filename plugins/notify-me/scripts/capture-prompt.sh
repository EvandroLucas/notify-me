#!/usr/bin/env bash
# capture-prompt.sh - roda no UserPromptSubmit no macOS/Linux. Le o JSON do hook no stdin,
# extrai prompt + session_id e grava uma linha curta em
# ${TMPDIR:-/tmp}/claude-toast-prompts/<session_id>.txt para o notify.sh montar o resumo.
# Silencioso e tolerante a falhas. No Windows (Git Bash/MSYS) nao faz nada - capture-prompt.ps1 cuida.
set -u

case "$(uname -s 2>/dev/null || echo unknown)" in
  Darwin|Linux) ;;
  *) exit 0 ;;
esac

[ -t 0 ] && exit 0
RAW="$(cat)"
[ -z "$RAW" ] && exit 0

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

SID="$(json_get session_id)"
PROMPT="$(json_get prompt)"
[ -z "$SID" ] && exit 0
[ -z "$PROMPT" ] && exit 0

DIR="${TMPDIR:-/tmp}/claude-toast-prompts"
mkdir -p "$DIR" 2>/dev/null || exit 0

LINE="$(printf '%s' "$PROMPT" | tr '\n\t' '  ' | sed 's/  */ /g; s/^ //; s/ *$//')"
[ "${#LINE}" -gt 200 ] && LINE="${LINE:0:200}"

printf '%s' "$LINE" > "$DIR/$SID.txt" 2>/dev/null
