#!/usr/bin/env bash
# notify.sh - fires a native notification on macOS and Linux for Claude Code.
#   macOS: terminal-notifier (if installed, shows the logo) -> native osascript fallback.
#   Linux: notify-send (libnotify).
# Windows is handled by notify.ps1; this script does NOTHING under Git Bash/MSYS/Cygwin,
# avoiding a duplicate notification when both hook entries fire.
# The message is resolved by language: NOTIFY_ME_LANG -> system locale -> English,
# using the plugin's own messages.json. Reads the hook JSON from stdin (cwd + session_id).
set -u

# KIND: the notification kind passed as the first argument (finished/error/attention/question);
# defaults to "finished" when no argument is given.
KIND="${1:-finished}"

# PLATFORM: which OS we're on, derived from `uname -s`. Only macOS (Darwin) and Linux are handled;
# anything else - notably MINGW/MSYS/CYGWIN on Windows - exits immediately (notify.ps1 covers it).
case "$(uname -s 2>/dev/null || echo unknown)" in
  Darwin) PLATFORM=mac ;;
  Linux)  PLATFORM=linux ;;
  *)      exit 0 ;;   # MINGW/MSYS/CYGWIN (Windows) -> notify.ps1 handles it
esac

# --- plugin root / icons ---
# ROOT: the plugin install root, from CLAUDE_PLUGIN_ROOT. If unset (e.g. run by hand), derive it as
# the parent of this script's directory (this file lives in <root>/scripts).
ROOT="${CLAUDE_PLUGIN_ROOT:-}"
if [ -z "$ROOT" ]; then
  # SCRIPT_DIR: the absolute directory of this script, resolved via cd+pwd.
  SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
  ROOT="$(dirname "$SCRIPT_DIR")"
fi
# SCRIPTS_DIR / ICONS / MSG_FILE: derived paths for the scripts folder, the icons folder, and the
# translations file, all relative to ROOT.
SCRIPTS_DIR="$ROOT/scripts"
ICONS="$ROOT/icons"
MSG_FILE="$SCRIPTS_DIR/messages.json"

# ICON: the status image for this notification, chosen by KIND (error / question / success default).
case "$KIND" in
  error)              ICON="$ICONS/claude_code_error.png" ;;
  attention|question) ICON="$ICONS/claude_code_question.png" ;;
  *)                  ICON="$ICONS/claude_code_success.png" ;;
esac

# --- hook stdin (JSON): cwd + session_id ---
# RAW: the raw hook JSON read from stdin. Left empty when stdin is a terminal (`-t 0` true), i.e.
# nothing was piped in.
RAW=""
[ -t 0 ] || RAW="$(cat)"

# json_get: extracts a top-level string value from the hook JSON. Best-effort and tolerant: tries
# python3 (handles escapes/unicode) -> jq -> sed, falling through to the next method whenever the
# result comes back empty (covers, e.g., python3 shims that don't actually work).
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
# CWD / SID: the working directory and session id pulled from the hook JSON via json_get.
CWD="$(json_get cwd)"
SID="$(json_get session_id)"

# --- resolve language: override -> macOS language / locale -> en ---
# On macOS, LANG/LC_* rarely reach hook subprocesses, so we read the preferred UI language via
# `defaults read -g AppleLanguages` before falling back to the locale.
# LANG_CODE: the two-letter language code used to pick a translation. Priority is the NOTIFY_ME_LANG
# override (lowercased, keeping the part before any '.'/'_'/'-'), then macOS AppleLanguages, then the
# system locale (LC_ALL/LC_MESSAGES/LANG), and finally 'en'.
if [ -n "${NOTIFY_ME_LANG:-}" ]; then
  LANG_CODE="$(printf '%s' "$NOTIFY_ME_LANG" | tr '[:upper:]' '[:lower:]' | sed 's/[._-].*//')"
else
  LANG_CODE=""
  if [ "$PLATFORM" = mac ] && command -v defaults >/dev/null 2>&1; then
    LANG_CODE="$(defaults read -g AppleLanguages 2>/dev/null | grep -oE '[a-zA-Z]{2}' | head -n1 | tr '[:upper:]' '[:lower:]')"
  fi
  if [ -z "$LANG_CODE" ]; then
    # SYS: the first non-empty system locale variable, checked in priority order.
    SYS="${LC_ALL:-${LC_MESSAGES:-${LANG:-}}}"
    LANG_CODE="$(printf '%s' "$SYS" | tr '[:upper:]' '[:lower:]' | sed 's/[._-].*//')"
  fi
fi
[ -z "$LANG_CODE" ] && LANG_CODE=en

# --- translated message (messages.json), with en and hardcoded fallbacks ---
# get_msg: prints the message string for (lang, kind) by scanning messages.json with awk - it enters
# the block for the matching language and prints the value of the matching kind key.
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
# MSG: the resolved headline text. Try the locale's language, fall back to English, and finally to a
# hardcoded default per kind if messages.json is missing or lacks the entry.
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

# --- folder (basename of cwd, max 40) ---
# FOLDER: the leaf name of CWD, shown as a subtitle. Empty when there's no cwd; truncated to 40 chars.
FOLDER=""
[ -n "$CWD" ] && FOLDER="$(basename "$CWD")"
if [ "${#FOLDER}" -gt 40 ]; then FOLDER="${FOLDER:0:40}..."; fi

# --- prompt summary saved on UserPromptSubmit (max 60) ---
# SUMMARY: the short prompt line stored by capture-prompt.sh for this session. PF is that file's path;
# we read it if present, then collapse whitespace, trim, and cap at 60 chars.
SUMMARY=""
if [ -n "$SID" ]; then
  PF="${TMPDIR:-/tmp}/claude-toast-prompts/$SID.txt"
  [ -f "$PF" ] && SUMMARY="$(cat "$PF" 2>/dev/null)"
fi
SUMMARY="$(printf '%s' "$SUMMARY" | tr '\n\t' '  ' | sed 's/  */ /g; s/^ //; s/ *$//')"
if [ "${#SUMMARY}" -gt 60 ]; then SUMMARY="${SUMMARY:0:60}..."; fi

# find_bin: locates an executable - PATH first, then known fallback paths. Hooks may run with a
# minimal PATH that omits Homebrew (/opt/homebrew/bin, /usr/local/bin), so `command -v` alone isn't
# enough.
find_bin() {
  if command -v "$1" >/dev/null 2>&1; then command -v "$1"; return 0; fi
  name="$1"; shift
  for c in "$@"; do [ -x "$c" ] && { printf '%s' "$c"; return 0; }; done
  return 1
}

# SUBTITLE: the folder label - append ":" when there's a summary, mirroring the Windows toast.
SUBTITLE="$FOLDER"
[ -n "$FOLDER" ] && [ -n "$SUMMARY" ] && SUBTITLE="$FOLDER:"

# --- fire per platform ---
if [ "$PLATFORM" = mac ]; then
  # LOGO: the app logo shown on the left of the macOS notification.
  LOGO="$ICONS/claude_logo_256.png"
  # BODY: the notification body - the summary if present, else the folder, else a single space (an
  # empty body would be rejected by some notifiers).
  BODY="$SUMMARY"; [ -z "$BODY" ] && BODY="$FOLDER"; [ -z "$BODY" ] && BODY=" "
  # TN: the terminal-notifier binary if found (via PATH or Homebrew paths); empty otherwise.
  TN="$(find_bin terminal-notifier /opt/homebrew/bin/terminal-notifier /usr/local/bin/terminal-notifier)"
  if [ -n "$TN" ]; then
    # logo as the app icon (left) + status icon as the content image (right), like on Windows
    "$TN" -title "$MSG" -subtitle "$SUBTITLE" -message "$BODY" \
      -appIcon "$LOGO" -contentImage "$ICON" -group "ClaudeCode.NotifyMe" >/dev/null 2>&1
  else
    # esc: escapes backslashes and double quotes so the strings are safe inside the AppleScript literal.
    esc() { printf '%s' "$1" | sed 's/\\/\\\\/g; s/"/\\"/g'; }
    osascript -e "display notification \"$(esc "$BODY")\" with title \"$(esc "$MSG")\" subtitle \"$(esc "$SUBTITLE")\"" >/dev/null 2>&1
  fi
  exit 0
fi

if [ "$PLATFORM" = linux ]; then
  # SEND: the notify-send binary if found (via PATH or common paths); exit if unavailable.
  SEND="$(find_bin notify-send /usr/bin/notify-send /usr/local/bin/notify-send)"
  [ -n "$SEND" ] || exit 0
  # URG: notification urgency - "critical" for errors, "normal" otherwise.
  URG=normal; [ "$KIND" = error ] && URG=critical
  # BODY: the notification body - the folder, with the summary appended on a new line when present.
  BODY="$FOLDER"
  if [ -n "$SUMMARY" ]; then
    if [ -n "$BODY" ]; then BODY="$BODY
$SUMMARY"; else BODY="$SUMMARY"; fi
  fi
  "$SEND" -a "Claude Code" -u "$URG" -i "$ICON" "$MSG" "$BODY" >/dev/null 2>&1
  exit 0
fi
