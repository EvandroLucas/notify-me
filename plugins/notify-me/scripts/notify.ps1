<#
  notify.ps1 - dispara uma notificacao toast do Windows para o Claude Code.
  A mensagem e resolvida pelo idioma: NOTIFY_ME_LANG (override) -> idioma do Windows -> ingles.
  As traducoes ficam em messages.json (ao lado deste script).
  Le o JSON do hook no stdin para obter a pasta (cwd) e a sessao (para o resumo do prompt).
#>
param(
  [Parameter(Mandatory)][ValidateSet('finished', 'error', 'attention', 'question')][string]$Kind
)
$ErrorActionPreference = 'Stop'

# Em PowerShell Core fora do Windows (ex.: macOS/Linux com pwsh instalado) este script nao
# se aplica - notify.sh cuida dessas plataformas. Sair cedo evita erros de WinRT e, quando as
# duas entradas do hook disparam, garante uma unica notificacao.
if ($PSVersionTable.PSEdition -eq 'Core' -and $PSVersionTable.Platform -and $PSVersionTable.Platform -ne 'Win32NT') { exit 0 }

# As APIs de toast usadas abaixo (WinRT via type accelerator) so existem no Windows PowerShell 5.1
# (Desktop). Quando o hook roda sob PowerShell 7+ (Core) - por ex. na extensao do VS Code - o
# carregamento desses tipos falha ("Unable to find type [Windows.UI.Notifications...]") e nenhum
# toast aparece. Nesse caso, reexecuta este mesmo script sob o powershell.exe 5.1, repassando o
# stdin (JSON do hook) e o -Kind.
if ($PSVersionTable.PSEdition -eq 'Core') {
  $ps51 = Join-Path $Env:SystemRoot 'System32\WindowsPowerShell\v1.0\powershell.exe'
  if (Test-Path $ps51) {
    $stdinData = ''
    if ([Console]::IsInputRedirected) { $stdinData = (New-Object System.IO.StreamReader([Console]::OpenStandardInput(), [System.Text.Encoding]::UTF8)).ReadToEnd() }
    # Garante que o stdin repassado ao 5.1 saia em UTF-8 (o 5.1 o le como UTF-8 abaixo).
    $OutputEncoding = [System.Text.Encoding]::UTF8
    $stdinData | & $ps51 -NoProfile -ExecutionPolicy Bypass -File $PSCommandPath -Kind $Kind
    exit $LASTEXITCODE
  }
}

# --- stdin do hook (JSON): cwd + session_id ---
# Le o stdin como UTF-8 cru (nao [Console]::In, que usa a codepage OEM e corromperia acentos
# em cwd, p.ex. uma pasta chamada "café").
$cwd = $null; $sid = $null
if ([Console]::IsInputRedirected) {
  $raw = (New-Object System.IO.StreamReader([Console]::OpenStandardInput(), [System.Text.Encoding]::UTF8)).ReadToEnd()
  if ($raw) { try { $j = $raw | ConvertFrom-Json; $cwd = $j.cwd; $sid = $j.session_id } catch { } }
}

# --- raiz do plugin / icone de status ---
$root = $Env:CLAUDE_PLUGIN_ROOT
if (-not $root) { $root = Split-Path -Parent $PSScriptRoot }
$scriptsDir = $PSScriptRoot
if (-not $scriptsDir) { $scriptsDir = Join-Path $root 'scripts' }
$icons = Join-Path $root 'icons'

$iconByKind = @{
  finished  = 'claude_code_success.png'
  error     = 'claude_code_error.png'
  attention = 'claude_code_question.png'
  question  = 'claude_code_question.png'
}
# Espacos no caminho (ex.: "Evandro Lucas") precisam de %20 no URI file:/// ou a imagem
# silenciosamente nao carrega no toast.
$iconPath = (Join-Path $icons $iconByKind[$Kind]) -replace '\\', '/' -replace ' ', '%20'
$src = "file:///$iconPath"

# --- resolver idioma: override -> Windows -> ingles ---
function Resolve-Lang {
  $ov = $Env:NOTIFY_ME_LANG
  if ($ov) { return (($ov.Trim().ToLower()) -split '[-_]')[0] }
  try {
    $c = [System.Globalization.CultureInfo]::CurrentUICulture.TwoLetterISOLanguageName
    if ($c) { return $c.ToLower() }
  } catch { }
  return 'en'
}
$lang = Resolve-Lang

# --- carregar mensagens traduzidas (UTF-8) ---
$messages = $null
$msgFile = Join-Path $scriptsDir 'messages.json'
try { $messages = [System.IO.File]::ReadAllText($msgFile, [System.Text.Encoding]::UTF8) | ConvertFrom-Json } catch { }

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
$message = Get-LocalizedMessage $messages $lang $Kind

# --- nome da pasta ---
$folder = ''
if ($cwd) { $folder = Split-Path $cwd -Leaf }
if ($folder.Length -gt 40) { $folder = $folder.Substring(0, 40).TrimEnd() + '...' }

# --- resumo do prompt salvo no UserPromptSubmit ---
$summary = ''
if ($sid) {
  $pf = Join-Path (Join-Path $Env:TEMP 'claude-toast-prompts') ($sid + '.txt')
  if (Test-Path $pf) { $summary = [System.IO.File]::ReadAllText($pf, [System.Text.Encoding]::UTF8) }
}
$summary = ($summary -replace '\s+', ' ').Trim()
if ($summary.Length -gt 60) { $summary = $summary.Substring(0, 60).TrimEnd() + '...' }

# --- montar texto: status / "pasta:" / resumo ---
function ConvertTo-XmlSafe([string]$s) { $s -replace '&', '&amp;' -replace '<', '&lt;' -replace '>', '&gt;' }

$texts = "<text>$(ConvertTo-XmlSafe $message)</text>"
if ($folder) {
  $label = if ($summary) { $folder + ':' } else { $folder }
  $texts += "<text>$(ConvertTo-XmlSafe $label)</text>"
}
if ($summary) { $texts += "<text>$(ConvertTo-XmlSafe $summary)</text>" }

$null = [Windows.UI.Notifications.ToastNotificationManager, Windows.UI.Notifications, ContentType = WindowsRuntime]
$null = [Windows.Data.Xml.Dom.XmlDocument, Windows.Data, ContentType = WindowsRuntime]
$doc = [Windows.Data.Xml.Dom.XmlDocument]::new()
$xml = "<toast><visual><binding template='ToastGeneric'>$texts<image placement='appLogoOverride' src='$src'/></binding></visual></toast>"
$doc.LoadXml($xml)
$toast = [Windows.UI.Notifications.ToastNotification]::new($doc)
$notifier = [Windows.UI.Notifications.ToastNotificationManager]::CreateToastNotifier('ClaudeCode.NotifyMe.v3')
$notifier.Show($toast)

# Show() apenas AGENDA o toast: a entrega ocorre de forma assincrona, via um servico COM
# out-of-process da plataforma de notificacoes do Windows. Como cada hook roda em um processo
# proprio que encerra imediatamente apos esta linha, a entrega as vezes e cancelada antes de
# completar - e por isso o toast aparecia "so algumas vezes". Aguardar um curto intervalo da
# tempo para a plataforma receber o toast antes do processo morrer.
Start-Sleep -Milliseconds 400
