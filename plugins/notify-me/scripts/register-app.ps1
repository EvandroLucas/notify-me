<#
  register-app.ps1 - registra o app "Claude Code" no Windows (HKCU) para que a logo
  apareca no cabecalho das notificacoes. Roda no SessionStart; idempotente e silencioso.
  Nao requer privilegios de administrador.

  Usa um AppUserModelID dedicado e uma logo de 256px. O Windows faz CACHE do icone por AUMID e
  nao o rele dentro da mesma sessao quando o caminho do IconUri muda - entao, se a logo trocar de
  lugar (ex.: o plugin foi renomeado/movido), versionamos o AUMID (...NotifyMe.v2) para forcar uma
  leitura fresca. Um id novo nunca tem cache, garantindo que o icone do cabecalho seja exibido.
#>
$ErrorActionPreference = 'SilentlyContinue'

# Registro de AppUserModelID e exclusivo do Windows; nada a fazer no macOS/Linux.
if ($PSVersionTable.PSEdition -eq 'Core' -and $PSVersionTable.Platform -and $PSVersionTable.Platform -ne 'Win32NT') { return }

$root = $Env:CLAUDE_PLUGIN_ROOT
if (-not $root) { $root = Split-Path -Parent $PSScriptRoot }
$logo = Join-Path (Join-Path $root 'icons') 'claude_logo_256.png'

# Mantenha este AUMID em sincronia com o usado em notify.ps1 (CreateToastNotifier).
$key = 'HKCU:\SOFTWARE\Classes\AppUserModelId\ClaudeCode.NotifyMe.v2'
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
