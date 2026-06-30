<#
  register-app.ps1 - registra o app "Claude Code" no Windows (HKCU) para que a logo
  apareca no cabecalho das notificacoes. Roda no SessionStart; idempotente e silencioso.
  Nao requer privilegios de administrador.

  Detalhe importante: o Windows faz CACHE do icone do cabecalho por AppUserModelID e NAO o
  rele quando o caminho do IconUri muda. O Claude Code instala o plugin num cache cujo caminho
  inclui a VERSAO (.../cache/notify-me/notify-me/<versao>/...), entao apontar o IconUri direto
  para os icones do plugin faria a logo "sumir" a cada atualizacao (caminho novo + AUMID cacheado).
  Para evitar isso, copiamos a logo para um caminho ESTAVEL em %LOCALAPPDATA% e registramos esse
  caminho - assim o IconUri nunca muda entre versoes, e a logo continua aparecendo apos updates.
#>
$ErrorActionPreference = 'SilentlyContinue'

# Registro de AppUserModelID e exclusivo do Windows; nada a fazer no macOS/Linux.
if ($PSVersionTable.PSEdition -eq 'Core' -and $PSVersionTable.Platform -and $PSVersionTable.Platform -ne 'Win32NT') { return }

$root = $Env:CLAUDE_PLUGIN_ROOT
if (-not $root) { $root = Split-Path -Parent $PSScriptRoot }
$srcLogo = Join-Path (Join-Path $root 'icons') 'claude_logo_256.png'

# Copia a logo para um local estavel (independente da versao/local do plugin).
$stableDir = Join-Path $Env:LOCALAPPDATA 'ClaudeCode-NotifyMe'
if (-not (Test-Path $stableDir)) { New-Item -ItemType Directory -Force -Path $stableDir | Out-Null }
$logo = Join-Path $stableDir 'claude_logo_256.png'
$srcInfo = Get-Item $srcLogo -ErrorAction SilentlyContinue
$dstInfo = Get-Item $logo -ErrorAction SilentlyContinue
if ($srcInfo -and (-not $dstInfo -or $dstInfo.Length -ne $srcInfo.Length)) {
  Copy-Item -Path $srcLogo -Destination $logo -Force
}

# AUMID dedicado e versionado. Mantenha em sincronia com notify.ps1 (CreateToastNotifier).
$key = 'HKCU:\SOFTWARE\Classes\AppUserModelId\ClaudeCode.NotifyMe.v3'
if (-not (Test-Path $key)) { New-Item -Path $key -Force | Out-Null }

# Escreve apenas quando algo mudou (evita I/O a cada sessao)
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
