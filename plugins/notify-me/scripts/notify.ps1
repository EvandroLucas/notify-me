<#
  notify.ps1 - fires a Windows toast notification for Claude Code.
  The message is resolved by language: NOTIFY_ME_LANG (override) -> Windows language -> English.
  The translations live in messages.json (next to this script).
  Reads the hook JSON from stdin to get the folder (cwd) and the session (for the prompt summary).
#>
param(
  [Parameter(Mandatory)][ValidateSet('finished', 'error', 'attention', 'question')][string]$Kind
)
$ErrorActionPreference = 'Stop'

# On PowerShell Core outside Windows (e.g. macOS/Linux with pwsh installed) this script does not
# apply - notify.sh handles those platforms. Exiting early avoids WinRT errors and, when both hook
# entries fire, guarantees a single notification.
if ($PSVersionTable.PSEdition -eq 'Core' -and $PSVersionTable.Platform -and $PSVersionTable.Platform -ne 'Win32NT') { exit 0 }

# The toast APIs used below (WinRT via type accelerators) only exist in Windows PowerShell 5.1
# (Desktop). When the hook runs under PowerShell 7+ (Core) - e.g. in the VS Code extension - loading
# those types fails ("Unable to find type [Windows.UI.Notifications...]") and no toast appears. In
# that case, re-run this same script under powershell.exe 5.1, forwarding stdin (hook JSON) and -Kind.
if ($PSVersionTable.PSEdition -eq 'Core') {
  # $ps51: full path to the Windows PowerShell 5.1 executable under %SystemRoot%. If present, we
  # relaunch ourselves through it.
  $ps51 = Join-Path $Env:SystemRoot 'System32\WindowsPowerShell\v1.0\powershell.exe'
  if (Test-Path $ps51) {
    # $stdinData: the current process's stdin captured as UTF-8 so we can pipe it into the 5.1
    # child (which re-reads it as UTF-8 below). Empty string when stdin isn't redirected.
    $stdinData = ''
    if ([Console]::IsInputRedirected) { $stdinData = (New-Object System.IO.StreamReader([Console]::OpenStandardInput(), [System.Text.Encoding]::UTF8)).ReadToEnd() }
    # $OutputEncoding: controls how PowerShell encodes text piped to native executables; forcing
    # UTF-8 ensures the forwarded stdin isn't mangled when handed to the 5.1 child.
    $OutputEncoding = [System.Text.Encoding]::UTF8
    $stdinData | & $ps51 -NoProfile -ExecutionPolicy Bypass -File $PSCommandPath -Kind $Kind
    exit $LASTEXITCODE
  }
}

# --- hook stdin (JSON): cwd + session_id ---
# $cwd / $sid: the working directory and session id from the hook payload; start as $null and are
# filled in only if stdin is redirected and parses. We read stdin as raw UTF-8 (not [Console]::In,
# which uses the OEM codepage and would corrupt accents in cwd, e.g. a folder named "café").
$cwd = $null; $sid = $null
if ([Console]::IsInputRedirected) {
  # $raw: the whole stdin decoded as UTF-8. $j: the parsed payload from which we pull cwd/session_id.
  $raw = (New-Object System.IO.StreamReader([Console]::OpenStandardInput(), [System.Text.Encoding]::UTF8)).ReadToEnd()
  if ($raw) { try { $j = $raw | ConvertFrom-Json; $cwd = $j.cwd; $sid = $j.session_id } catch { } }
}

# --- plugin root / status icon ---
# $root: the plugin install root, from CLAUDE_PLUGIN_ROOT or, as a fallback, the parent of this
# script's folder (this file lives in <root>/scripts).
$root = $Env:CLAUDE_PLUGIN_ROOT
if (-not $root) { $root = Split-Path -Parent $PSScriptRoot }

# $scriptsDir: the folder containing this script (used to locate messages.json). $PSScriptRoot is
# empty in some invocation contexts, so fall back to <root>/scripts.
$scriptsDir = $PSScriptRoot
if (-not $scriptsDir) { $scriptsDir = Join-Path $root 'scripts' }

# $icons: the folder holding the notification images (<root>/icons).
$icons = Join-Path $root 'icons'

# $iconByKind: maps each notification kind to its status icon filename. "attention" and "question"
# intentionally share the same image.
$iconByKind = @{
  finished  = 'claude_code_success.png'
  error     = 'claude_code_error.png'
  attention = 'claude_code_question.png'
  question  = 'claude_code_question.png'
}

# $iconPath: absolute path to the chosen icon, with backslashes turned into forward slashes and
# spaces percent-encoded. Spaces in the path (e.g. "Evandro Lucas") need %20 in the file:/// URI or
# the image silently fails to load in the toast.
$iconPath = (Join-Path $icons $iconByKind[$Kind]) -replace '\\', '/' -replace ' ', '%20'

# $src: the file:/// URI used as the toast image source, built from $iconPath.
$src = "file:///$iconPath"

# --- resolve language: override -> Windows -> English ---
# Resolve-Lang returns a two-letter language code. It prefers the NOTIFY_ME_LANG override (taking the
# part before any '-'/'_', e.g. "pt-BR" -> "pt"), then the Windows UI culture, and finally 'en'.
function Resolve-Lang {
  $ov = $Env:NOTIFY_ME_LANG
  if ($ov) { return (($ov.Trim().ToLower()) -split '[-_]')[0] }
  try {
    $c = [System.Globalization.CultureInfo]::CurrentUICulture.TwoLetterISOLanguageName
    if ($c) { return $c.ToLower() }
  } catch { }
  return 'en'
}
# $lang: the resolved two-letter language code used to pick a translation below.
$lang = Resolve-Lang

# --- load translated messages (UTF-8) ---
# $messages: the parsed contents of messages.json (or $null if it can't be read/parsed). $msgFile is
# its path next to this script. Read explicitly as UTF-8 so translated accents survive.
$messages = $null
$msgFile = Join-Path $scriptsDir 'messages.json'
try { $messages = [System.IO.File]::ReadAllText($msgFile, [System.Text.Encoding]::UTF8) | ConvertFrom-Json } catch { }

# Get-LocalizedMessage picks the message string for ($lang, $kind), falling back to English and then
# to a hardcoded default when a translation is missing.
function Get-LocalizedMessage($msgs, $lang, $kind) {
  if ($msgs -and $msgs.PSObject.Properties[$lang] -and $msgs.$lang.PSObject.Properties[$kind]) {
    return $msgs.$lang.$kind
  }
  if ($msgs -and $msgs.PSObject.Properties['en'] -and $msgs.en.PSObject.Properties[$kind]) {
    return $msgs.en.$kind
  }
  $fb = @{ finished = 'Prompt finished!'; error = 'An error occurred'; attention = 'Claude needs your attention'; question = 'Claude asked a question' }
  return $fb[$kind]
}
# $message: the final, localized headline text for this notification.
$message = Get-LocalizedMessage $messages $lang $Kind

# --- folder name ---
# $folder: the leaf name of the working directory (e.g. "notify-me" out of a full path), shown as a
# subtitle. Empty when there's no cwd; capped at 40 chars with an ellipsis.
$folder = ''
if ($cwd) { $folder = Split-Path $cwd -Leaf }
if ($folder.Length -gt 40) { $folder = $folder.Substring(0, 40).TrimEnd() + '...' }

# --- prompt summary saved on UserPromptSubmit ---
# $summary: the short prompt line that capture-prompt.ps1 stored for this session. $pf is that file's
# path (<TEMP>/claude-toast-prompts/<session_id>.txt); we read it as UTF-8 if it exists.
$summary = ''
if ($sid) {
  $pf = Join-Path (Join-Path $Env:TEMP 'claude-toast-prompts') ($sid + '.txt')
  if (Test-Path $pf) { $summary = [System.IO.File]::ReadAllText($pf, [System.Text.Encoding]::UTF8) }
}
# Collapse whitespace to single spaces, trim, and cap at 60 chars so it fits on the toast.
$summary = ($summary -replace '\s+', ' ').Trim()
if ($summary.Length -gt 60) { $summary = $summary.Substring(0, 60).TrimEnd() + '...' }

# --- build text: status / "folder:" / summary ---
# ConvertTo-XmlSafe escapes the XML-significant characters so arbitrary text can be embedded safely
# in the toast XML below.
function ConvertTo-XmlSafe([string]$s) { $s -replace '&', '&amp;' -replace '<', '&lt;' -replace '>', '&gt;' }

# $texts: the accumulated <text> nodes for the toast body. Always starts with the localized headline;
# then appends the folder (suffixed with ':' when a summary follows) and the summary itself.
$texts = "<text>$(ConvertTo-XmlSafe $message)</text>"
if ($folder) {
  # $label: the folder line - "folder:" when a summary comes next, otherwise just the folder name.
  $label = if ($summary) { $folder + ':' } else { $folder }
  $texts += "<text>$(ConvertTo-XmlSafe $label)</text>"
}
if ($summary) { $texts += "<text>$(ConvertTo-XmlSafe $summary)</text>" }

$null = [Windows.UI.Notifications.ToastNotificationManager, Windows.UI.Notifications, ContentType = WindowsRuntime]
$null = [Windows.Data.Xml.Dom.XmlDocument, Windows.Data, ContentType = WindowsRuntime]

# $doc: an empty WinRT XML document that we load the toast markup into.
$doc = [Windows.Data.Xml.Dom.XmlDocument]::new()

# $xml: the full ToastGeneric markup - the accumulated $texts plus an appLogoOverride image ($src).
$xml = "<toast><visual><binding template='ToastGeneric'>$texts<image placement='appLogoOverride' src='$src'/></binding></visual></toast>"
$doc.LoadXml($xml)

# $toast: the toast notification object built from the loaded document.
$toast = [Windows.UI.Notifications.ToastNotification]::new($doc)

# $notifier: the notifier bound to our versioned AUMID (must match register-app.ps1's ".v3" key) -
# this is what ties the toast to the "Claude Code" identity and its header logo.
$notifier = [Windows.UI.Notifications.ToastNotificationManager]::CreateToastNotifier('ClaudeCode.NotifyMe.v3')
$notifier.Show($toast)

# Show() only SCHEDULES the toast: delivery happens asynchronously, via an out-of-process COM service
# of the Windows notification platform. Since each hook runs in its own process that exits immediately
# after this line, delivery is sometimes cancelled before it completes - which is why the toast used
# to appear "only sometimes". A short sleep gives the platform time to receive the toast before the
# process dies.
Start-Sleep -Milliseconds 400
