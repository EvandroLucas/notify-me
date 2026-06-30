#!/usr/bin/env node
import { readFileSync, existsSync, mkdirSync, writeFileSync } from 'node:fs';
import { fileURLToPath } from 'node:url';
import { dirname, join, basename } from 'node:path';
import { tmpdir, platform } from 'node:os';
import { spawnSync } from 'node:child_process';

const scriptsDir = dirname(fileURLToPath(import.meta.url));
const pluginRoot = dirname(scriptsDir);
const iconsDir = join(pluginRoot, 'icons');

const [action, kind] = process.argv.slice(2);

const stdinRaw = readStdin();
const hook = parseJson(stdinRaw);

const os = platform();
if (os === 'win32') {
  delegateToPowerShell();
} else if (os === 'darwin') {
  runUnix({ mac: true });
} else {
  runUnix({ mac: false });
}

function readStdin() {
  try {
    return readFileSync(0, 'utf8');
  } catch {
    return '';
  }
}

function parseJson(raw) {
  if (!raw) return {};
  try {
    return JSON.parse(raw);
  } catch {
    return {};
  }
}

// On Windows the existing PowerShell scripts own the behavior (WinRT toast APIs, registry
// app registration). We just forward stdin and the right arguments to them so the Windows
// experience is unchanged. Use Windows PowerShell 5.1 directly — the WinRT type accelerators
// only load there, not under PowerShell 7+.
function delegateToPowerShell() {
  const scripts = {
    register: ['register-app.ps1'],
    capture: ['capture-prompt.ps1'],
    notify: ['notify.ps1', '-Kind', kind],
  };
  const spec = scripts[action];
  if (!spec) return;
  const [file, ...rest] = spec;
  const scriptPath = join(scriptsDir, file);

  const winPs = process.env.SystemRoot
    ? join(process.env.SystemRoot, 'System32', 'WindowsPowerShell', 'v1.0', 'powershell.exe')
    : null;
  const exe = winPs && existsSync(winPs) ? winPs : 'powershell.exe';

  spawnSync(exe, ['-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', scriptPath, ...rest], {
    input: stdinRaw,
    stdio: ['pipe', 'inherit', 'inherit'],
  });
}

function runUnix({ mac }) {
  if (action === 'register') return;
  if (action === 'capture') return capturePrompt();
  if (action === 'notify') return notify({ mac });
}

function capturePrompt() {
  const sid = hook.session_id;
  const prompt = hook.prompt;
  if (!sid || !prompt) return;

  let line = String(prompt).replace(/\s+/g, ' ').trim();
  if (line.length > 200) line = line.slice(0, 200);

  const dir = join(tmpdir(), 'claude-toast-prompts');
  try {
    mkdirSync(dir, { recursive: true });
    writeFileSync(join(dir, `${sid}.txt`), line, 'utf8');
  } catch {
    /* best-effort, never block the turn */
  }
}

function notify({ mac }) {
  const lang = resolveLang({ mac });
  const message = localizedMessage(lang, kind);

  let folder = hook.cwd ? basename(hook.cwd) : '';
  if (folder.length > 40) folder = `${folder.slice(0, 40).trimEnd()}...`;

  let summary = readSummary(hook.session_id);
  summary = summary.replace(/\s+/g, ' ').trim();
  if (summary.length > 60) summary = `${summary.slice(0, 60).trimEnd()}...`;

  const title = message;
  const subtitle = folder && summary ? `${folder}:` : folder;
  const body = summary;

  if (mac) {
    showMac({ title, subtitle, body });
  } else {
    showLinux({ title, subtitle, body });
  }
}

function readSummary(sid) {
  if (!sid) return '';
  const file = join(tmpdir(), 'claude-toast-prompts', `${sid}.txt`);
  try {
    return existsSync(file) ? readFileSync(file, 'utf8') : '';
  } catch {
    return '';
  }
}

function resolveLang({ mac }) {
  const override = process.env.NOTIFY_ME_LANG;
  if (override) return override.trim().toLowerCase().split(/[-_]/)[0];

  if (mac) {
    const ui = macUILanguage();
    if (ui) return ui;
  }

  const env = process.env.LC_ALL || process.env.LC_MESSAGES || process.env.LANG || '';
  const code = env.split(/[._-]/)[0].trim().toLowerCase();
  return code || 'en';
}

function macUILanguage() {
  try {
    const out = spawnSync('defaults', ['read', '-g', 'AppleLanguages'], { encoding: 'utf8' });
    const match = (out.stdout || '').match(/"?([a-zA-Z]{2})(?:[-_][a-zA-Z]+)*"?/);
    return match ? match[1].toLowerCase() : '';
  } catch {
    return '';
  }
}

function localizedMessage(lang, msgKind) {
  const fallback = {
    finished: 'Prompt finished!',
    error: 'An error occurred',
    attention: 'Claude needs your attention',
    question: 'Claude asked a question',
  };
  let messages;
  try {
    messages = JSON.parse(readFileSync(join(scriptsDir, 'messages.json'), 'utf8'));
  } catch {
    return fallback[msgKind];
  }
  return messages?.[lang]?.[msgKind] ?? messages?.en?.[msgKind] ?? fallback[msgKind];
}

function iconFor(msgKind, name) {
  const statusIcon = {
    finished: 'claude_code_success.png',
    error: 'claude_code_error.png',
    attention: 'claude_code_question.png',
    question: 'claude_code_question.png',
  };
  const file = name === 'status' ? statusIcon[msgKind] : 'claude_logo_256.png';
  return join(iconsDir, file);
}

function showMac({ title, subtitle, body }) {
  const tn = findTerminalNotifier();
  if (tn) {
    const args = ['-title', title];
    if (subtitle) args.push('-subtitle', subtitle);
    args.push('-message', body || ' ');
    args.push('-appIcon', iconFor(kind, 'logo'));
    args.push('-contentImage', iconFor(kind, 'status'));
    args.push('-group', 'ClaudeCode.NotifyMe');
    spawnSync(tn, args, { stdio: 'ignore' });
    return;
  }
  // osascript ships with macOS but cannot show a custom icon.
  const note = [body, subtitle].filter(Boolean).join(' — ') || ' ';
  const script = `display notification ${appleStr(note)} with title ${appleStr(title)}${
    subtitle ? ` subtitle ${appleStr(subtitle)}` : ''
  }`;
  spawnSync('osascript', ['-e', script], { stdio: 'ignore' });
}

function showLinux({ title, subtitle, body }) {
  const send = findOnPath('notify-send', ['/usr/bin/notify-send', '/usr/local/bin/notify-send']);
  if (!send) return;
  const heading = [title, subtitle].filter(Boolean).join(' — ');
  const args = ['-i', iconFor(kind, 'status'), heading, body || ''];
  spawnSync(send, args, { stdio: 'ignore' });
}

function findTerminalNotifier() {
  return findOnPath('terminal-notifier', [
    '/opt/homebrew/bin/terminal-notifier',
    '/usr/local/bin/terminal-notifier',
  ]);
}

// Hook subprocesses can inherit a minimal PATH that omits Homebrew, so check well-known
// locations in addition to `which`.
function findOnPath(name, candidates) {
  try {
    const which = spawnSync('/usr/bin/which', [name], { encoding: 'utf8' });
    if (which.status === 0 && which.stdout.trim()) return which.stdout.trim();
  } catch {
    /* fall through to explicit candidates */
  }
  return candidates.find((c) => existsSync(c)) || null;
}

function appleStr(s) {
  return `"${String(s).replace(/\\/g, '\\\\').replace(/"/g, '\\"')}"`;
}
