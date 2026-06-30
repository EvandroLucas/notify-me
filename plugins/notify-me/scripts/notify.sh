#!/usr/bin/env bash
# notify.sh - dispara uma notificacao nativa no macOS e Linux para o Claude Code.
#   macOS: terminal-notifier (se instalado, mostra a logo) -> fallback osascript nativo.
#   Linux: notify-send (libnotify).
# O Windows e tratado por notify.ps1; este script NAO faz nada sob Git Bash/MSYS/Cygwin,
# evitando notificacao duplicada quando ambas as entradas do hook disparam.
# A mensagem e resolvida pelo idioma: NOTIFY_ME_LANG -> locale do sistema -> ingles,
# usando o mesmo messages.json do plugin. Le o JSON do hook no stdin (cwd + session_id).
set -u

KIND="${1:-finished}"

case "$(uname -s 2>/dev/null || echo unknown)" in
  Darwin) PLATFORM=mac ;;
  Linux)  PLATFORM=linux ;;
  *)      exit 0 ;;   # MINGW/MSYS/CYGWIN (Windows) -> notify.ps1 cuida disso
esac

# --- raiz do plugin / icones ---
ROOT="${CLAUDE_PLUGIN_ROOT:-}"
if [ -z "$ROOT" ]; then
  SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
  ROOT="$(dirname "$SCRIPT_DIR")"
fi
SCRIPTS_DIR="$ROOT/scripts"
ICONS="$ROOT/icons"
MSG_FILE="$SCRIPTS_DIR/messages.json"

case "$KIND" in
  error)              ICON="$ICONS/claude_code_error.png" ;;
  attention|question) ICON="$ICONS/claude_code_question.png" ;;
  *)                  ICON="$ICONS/claude_code_success.png" ;;
esac

# --- stdin do hook (JSON): cwd + session_id ---
RAW=""
[ -t 0 ] || RAW="$(cat)"

# Extrai um valor string de chave de topo do JSON do hook. Best-effort e tolerante:
# tenta python3 (lida com escapes/unicode) -> jq -> sed, caindo para o proximo metodo
# sempre que o resultado vier vazio (cobre, p.ex., shims de python3 que nao funcionam).
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
CWD="$(json_get cwd)"
SID="$(json_get session_id)"

# --- resolver idioma: override -> idioma do macOS / locale -> en ---
# No macOS, LANG/LC_* raramente chegam aos subprocessos de hook, entao lemos o idioma
# preferido da UI via `defaults read -g AppleLanguages` antes de cair no locale.
if [ -n "${NOTIFY_ME_LANG:-}" ]; then
  LANG_CODE="$(printf '%s' "$NOTIFY_ME_LANG" | tr '[:upper:]' '[:lower:]' | sed 's/[._-].*//')"
else
  LANG_CODE=""
  if [ "$PLATFORM" = mac ] && command -v defaults >/dev/null 2>&1; then
    LANG_CODE="$(defaults read -g AppleLanguages 2>/dev/null | grep -oE '[a-zA-Z]{2}' | head -n1 | tr '[:upper:]' '[:lower:]')"
  fi
  if [ -z "$LANG_CODE" ]; then
    SYS="${LC_ALL:-${LC_MESSAGES:-${LANG:-}}}"
    LANG_CODE="$(printf '%s' "$SYS" | tr '[:upper:]' '[:lower:]' | sed 's/[._-].*//')"
  fi
fi
[ -z "$LANG_CODE" ] && LANG_CODE=en

# --- mensagem traduzida (messages.json), com fallback en e hardcoded ---
get_msg() {
  [ -f "$MSG_FILE" ] || return 0
  awk -v lang="$1" -v kind="$2" '
    $0 ~ ("\"" lang "\"") && /[{][ \t]*$/ {inblk=1; next}
    inblk && /[}]/ {inblk=0; next}
    inblk && $0 ~ ("\"" kind "\"[ \t]*:") {
      line=$0
      sub(/^[^:]*:[ \t]*"/,"",line)
      sub(/"[ \t]*,?[ \t]*$/,"",line)
      print line
      exit
    }
  ' "$MSG_FILE"
}
MSG="$(get_msg "$LANG_CODE" "$KIND")"
[ -z "$MSG" ] && MSG="$(get_msg en "$KIND")"
if [ -z "$MSG" ]; then
  case "$KIND" in
    error)     MSG="An error occurred" ;;
    attention) MSG="Claude needs your attention" ;;
    question)  MSG="Claude asked a question" ;;
    *)         MSG="Prompt finished!" ;;
  esac
fi

# --- pasta (basename do cwd, max 40) ---
FOLDER=""
[ -n "$CWD" ] && FOLDER="$(basename "$CWD")"
if [ "${#FOLDER}" -gt 40 ]; then FOLDER="${FOLDER:0:40}..."; fi

# --- resumo do prompt salvo no UserPromptSubmit (max 60) ---
SUMMARY=""
if [ -n "$SID" ]; then
  PF="${TMPDIR:-/tmp}/claude-toast-prompts/$SID.txt"
  [ -f "$PF" ] && SUMMARY="$(cat "$PF" 2>/dev/null)"
fi
SUMMARY="$(printf '%s' "$SUMMARY" | tr '\n\t' '  ' | sed 's/  */ /g; s/^ //; s/ *$//')"
if [ "${#SUMMARY}" -gt 60 ]; then SUMMARY="${SUMMARY:0:60}..."; fi

# Localiza um executavel: PATH primeiro, depois caminhos conhecidos. Hooks podem rodar com
# um PATH minimo que omite o Homebrew (/opt/homebrew/bin, /usr/local/bin), entao nao basta
# confiar em `command -v`.
find_bin() {
  if command -v "$1" >/dev/null 2>&1; then command -v "$1"; return 0; fi
  name="$1"; shift
  for c in "$@"; do [ -x "$c" ] && { printf '%s' "$c"; return 0; }; done
  return 1
}

# Rotulo da pasta: acrescenta ":" quando ha resumo, espelhando o toast do Windows.
SUBTITLE="$FOLDER"
[ -n "$FOLDER" ] && [ -n "$SUMMARY" ] && SUBTITLE="$FOLDER:"

# --- disparar por plataforma ---
if [ "$PLATFORM" = mac ]; then
  LOGO="$ICONS/claude_logo_256.png"
  BODY="$SUMMARY"; [ -z "$BODY" ] && BODY="$FOLDER"; [ -z "$BODY" ] && BODY=" "
  TN="$(find_bin terminal-notifier /opt/homebrew/bin/terminal-notifier /usr/local/bin/terminal-notifier)"
  if [ -n "$TN" ]; then
    # logo como icone do app (esquerda) + icone de status como imagem (direita), como no Windows
    "$TN" -title "$MSG" -subtitle "$SUBTITLE" -message "$BODY" \
      -appIcon "$LOGO" -contentImage "$ICON" -group "ClaudeCode.NotifyMe" >/dev/null 2>&1
  else
    esc() { printf '%s' "$1" | sed 's/\\/\\\\/g; s/"/\\"/g'; }
    osascript -e "display notification \"$(esc "$BODY")\" with title \"$(esc "$MSG")\" subtitle \"$(esc "$SUBTITLE")\"" >/dev/null 2>&1
  fi
  exit 0
fi

if [ "$PLATFORM" = linux ]; then
  SEND="$(find_bin notify-send /usr/bin/notify-send /usr/local/bin/notify-send)"
  [ -n "$SEND" ] || exit 0
  URG=normal; [ "$KIND" = error ] && URG=critical
  BODY="$FOLDER"
  if [ -n "$SUMMARY" ]; then
    if [ -n "$BODY" ]; then BODY="$BODY
$SUMMARY"; else BODY="$SUMMARY"; fi
  fi
  "$SEND" -a "Claude Code" -u "$URG" -i "$ICON" "$MSG" "$BODY" >/dev/null 2>&1
  exit 0
fi
