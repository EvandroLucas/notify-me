<#
  capture-prompt.ps1 - roda no UserPromptSubmit. Le o JSON do hook no stdin, extrai o prompt
  e a sessao, e grava uma linha curta em %TEMP%\claude-toast-prompts\<session_id>.txt para o
  notify.ps1 montar o resumo. Silencioso e tolerante a falhas.
#>
$ErrorActionPreference = 'SilentlyContinue'

# No macOS/Linux (pwsh) este script nao se aplica - capture-prompt.sh cuida dessas plataformas.
if ($PSVersionTable.PSEdition -eq 'Core' -and $PSVersionTable.Platform -and $PSVersionTable.Platform -ne 'Win32NT') { return }

if (-not [Console]::IsInputRedirected) { return }
# Le o stdin como bytes crus decodificados em UTF-8. NAO usar [Console]::In, que decodifica com
# a codepage OEM do console (ex.: CP850) no contexto do hook e corrompe acentos do prompt
# (ex.: "ç" UTF-8 C3A7 viraria "├º"). O JSON do hook do Claude Code sempre vem em UTF-8.
$raw = (New-Object System.IO.StreamReader([Console]::OpenStandardInput(), [System.Text.Encoding]::UTF8)).ReadToEnd()
if (-not $raw) { return }
try { $j = $raw | ConvertFrom-Json } catch { return }

$sid = $j.session_id
$prompt = $j.prompt
if (-not $sid -or -not $prompt) { return }

$dir = Join-Path $Env:TEMP 'claude-toast-prompts'
if (-not (Test-Path $dir)) { New-Item -ItemType Directory -Force -Path $dir | Out-Null }

$line = ($prompt -replace '\s+', ' ').Trim()
if ($line.Length -gt 200) { $line = $line.Substring(0, 200) }

$file = Join-Path $dir ($sid + '.txt')
[System.IO.File]::WriteAllText($file, $line, (New-Object System.Text.UTF8Encoding($false)))
