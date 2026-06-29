<#
  capture-prompt.ps1 - roda no UserPromptSubmit. Le o JSON do hook no stdin, extrai o prompt
  e a sessao, e grava uma linha curta em %TEMP%\claude-toast-prompts\<session_id>.txt para o
  notify.ps1 montar o resumo. Silencioso e tolerante a falhas.
#>
$ErrorActionPreference = 'SilentlyContinue'

if (-not [Console]::IsInputRedirected) { return }
$raw = [Console]::In.ReadToEnd()
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
