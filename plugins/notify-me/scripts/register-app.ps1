<#
  register-app.ps1 - registers the "Claude Code" app in Windows (HKCU) so the logo
  shows up in the notification header. Runs on SessionStart; idempotent and silent.
  Does not require administrator privileges.

  Important detail: Windows CACHES the header icon by AppUserModelID and does NOT
  re-read it when the IconUri path changes. Claude Code installs the plugin into a cache
  whose path includes the VERSION (.../cache/notify-me/notify-me/<version>/...), so pointing
  IconUri straight at the plugin's icons would make the logo "disappear" on every update
  (new path + cached AUMID). To avoid that, we copy the logo to a STABLE path under
  %LOCALAPPDATA% and register that path - so IconUri never changes between versions, and the
  logo keeps showing after updates.
#>
$ErrorActionPreference = 'SilentlyContinue'

# AppUserModelID registration is Windows-only; nothing to do on macOS/Linux.
if ($PSVersionTable.PSEdition -eq 'Core' -and $PSVersionTable.Platform -and $PSVersionTable.Platform -ne 'Win32NT') { return }

# $root: the plugin's install root. Claude Code exports CLAUDE_PLUGIN_ROOT when running hooks;
# if it's absent (e.g. running the script by hand), fall back to the parent of this script's
# folder (this file lives in <root>/scripts, so the parent of $PSScriptRoot is <root>).
$root = $Env:CLAUDE_PLUGIN_ROOT
if (-not $root) { $root = Split-Path -Parent $PSScriptRoot }

# $srcLogo: absolute path to the logo shipped with the plugin (<root>/icons/claude_logo_256.png).
# This is the SOURCE we copy from; its path changes on every plugin update (see header).
$srcLogo = Join-Path (Join-Path $root 'icons') 'claude_logo_256.png'

# $stableDir: a version-independent destination folder under %LOCALAPPDATA% that survives plugin
# updates. Created on first run if it doesn't exist yet.
$stableDir = Join-Path $Env:LOCALAPPDATA 'ClaudeCode-NotifyMe'
if (-not (Test-Path $stableDir)) { New-Item -ItemType Directory -Force -Path $stableDir | Out-Null }

# $logo: the STABLE copy of the logo inside $stableDir. This is the path we register as IconUri,
# and it never changes between versions.
$logo = Join-Path $stableDir 'claude_logo_256.png'

# $srcInfo / $dstInfo: FileInfo objects for the source and the stable copy (or $null if missing).
# We compare them to copy only when needed - i.e. when the destination is absent or its size
# differs from the source (a cheap change check that avoids copying on every session).
$srcInfo = Get-Item $srcLogo -ErrorAction SilentlyContinue
$dstInfo = Get-Item $logo -ErrorAction SilentlyContinue
if ($srcInfo -and (-not $dstInfo -or $dstInfo.Length -ne $srcInfo.Length)) {
  Copy-Item -Path $srcLogo -Destination $logo -Force
}

# $key: the registry path of our dedicated, versioned AppUserModelID under HKCU. The ".v3" suffix
# must stay in sync with notify.ps1 (CreateToastNotifier). Created if it doesn't exist yet.
$key = 'HKCU:\SOFTWARE\Classes\AppUserModelId\ClaudeCode.NotifyMe.v3'
if (-not (Test-Path $key)) { New-Item -Path $key -Force | Out-Null }

# $cur: the current property values already stored under $key (or $null on first run). We read them
# once so the writes below only fire when a value actually changed, avoiding registry I/O every session.
$cur = Get-ItemProperty -Path $key -ErrorAction SilentlyContinue
if ($cur.DisplayName -ne 'Claude Code') {
  New-ItemProperty -Path $key -Name 'DisplayName' -Value 'Claude Code' -PropertyType String -Force | Out-Null
}
if ($cur.IconUri -ne $logo) {
  New-ItemProperty -Path $key -Name 'IconUri' -Value $logo -PropertyType String -Force | Out-Null
}
if ($cur.IconBackgroundColor -ne '0') {
  New-ItemProperty -Path $key -Name 'IconBackgroundColor' -Value '0' -PropertyType String -Force | Out-Null
}
