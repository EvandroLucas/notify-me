<#
  register-app.ps1 - registra o app "Claude Code" no Windows (HKCU) para que a logo
  apareca no cabecalho das notificacoes. Roda no SessionStart; idempotente e silencioso.
  Nao requer privilegios de administrador.

  Usa um AppUserModelID dedicado (ClaudeCode.NotifyMe) e uma logo de 256px. O AUMID dedicado
  evita o cache de icone do Windows associado a ids genericos, garantindo que o icone do
  cabecalho seja sempre exibido.
#>
$ErrorActionPreference = 'SilentlyContinue'

# Registro de AppUserModelID e exclusivo do Windows; nada a fazer no macOS/Linux.
if ($PSVersionTable.PSEdition -eq 'Core' -and $PSVersionTable.Platform -and $PSVersionTable.Platform -ne 'Win32NT') { return }

$root = $Env:CLAUDE_PLUGIN_ROOT
if (-not $root) { $root = Split-Path -Parent $PSScriptRoot }
$logo = Join-Path (Join-Path $root 'icons') 'claude_logo_256.png'

$key = 'HKCU:\SOFTWARE\Classes\AppUserModelId\ClaudeCode.NotifyMe'
if (-not (Test-Path $key)) { New-Item -Path $key -Force | Out-Null }

# Escreve apenas quando algo mudou (evita I/O a cada sessao)
$cur = Get-ItemProperty -Path $key -ErrorAction SilentlyContinue
if ($cur.DisplayName -ne 'Claude Code') {
  New-ItemProperty -Path $key -Name 'DisplayName' -Value 'Claude Code' -PropertyType String -Force | Out-Null
}
if ($cur.IconUri -ne $logo) {
  New-ItemProperty -Path $key -Name 'IconUri' -Value $logo -PropertyType String -Force | Out-Null
}
