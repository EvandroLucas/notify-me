<#
  capture-prompt.ps1 - runs on UserPromptSubmit. Reads the hook JSON from stdin, extracts the
  prompt and the session, and writes a short line to %TEMP%\claude-toast-prompts\<session_id>.txt
  for notify.ps1 to build the summary. Silent and fault-tolerant.
#>
$ErrorActionPreference = 'SilentlyContinue'

# On macOS/Linux (pwsh) this script does not apply - capture-prompt.sh handles those platforms.
if ($PSVersionTable.PSEdition -eq 'Core' -and $PSVersionTable.Platform -and $PSVersionTable.Platform -ne 'Win32NT') { return }

if (-not [Console]::IsInputRedirected) { return }

# $raw: the entire stdin read as raw bytes decoded as UTF-8. We must NOT use [Console]::In, which
# decodes with the console's OEM codepage (e.g. CP850) in the hook context and corrupts accents in
# the prompt (e.g. "ç" UTF-8 C3A7 would become "├º"). Claude Code's hook JSON always arrives as UTF-8.
$raw = (New-Object System.IO.StreamReader([Console]::OpenStandardInput(), [System.Text.Encoding]::UTF8)).ReadToEnd()
if (-not $raw) { return }

# $j: the parsed hook payload. ConvertFrom-Json turns the raw JSON into an object; if parsing fails
# (malformed input) we bail out quietly rather than throwing.
try { $j = $raw | ConvertFrom-Json } catch { return }

# $sid: the session id from the payload - used as the per-session filename so notify.ps1 can find
# this prompt later. $prompt: the raw prompt text the user submitted. If either is missing, stop.
$sid = $j.session_id
$prompt = $j.prompt
if (-not $sid -or -not $prompt) { return }

# $dir: the shared temp folder where per-session prompt files live. Created if it doesn't exist yet.
$dir = Join-Path $Env:TEMP 'claude-toast-prompts'
if (-not (Test-Path $dir)) { New-Item -ItemType Directory -Force -Path $dir | Out-Null }

# $line: the prompt collapsed to a single line (runs of whitespace -> one space) and trimmed, then
# capped at 200 chars so the stored summary stays short.
$line = ($prompt -replace '\s+', ' ').Trim()
if ($line.Length -gt 200) { $line = $line.Substring(0, 200) }

# $file: the destination path for this session's summary line, <session_id>.txt inside $dir.
# Written as UTF-8 WITHOUT a BOM so notify.ps1 reads the accents back correctly.
$file = Join-Path $dir ($sid + '.txt')
[System.IO.File]::WriteAllText($file, $line, (New-Object System.Text.UTF8Encoding($false)))
