# notify-me

**Native desktop notifications for [Claude Code](https://www.claude.com/product/claude-code) on Windows and macOS.**
Know the moment a prompt finishes, Claude asks you something, or something goes wrong — without babysitting the terminal.

When Claude is working on a long task you usually switch to something else. `notify-me` pops a native
notification — a Windows toast or a macOS Notification Center alert — the instant Claude needs you or
finishes, showing **which project** it is and a **short summary of your prompt**, so you can tell
sessions apart at a glance.

---

## What you get

| When it fires | Hook event | Status icon |
|---|---|---|
| A prompt finishes | `Stop` | ✅ green check |
| Claude asks you a question | `PreToolUse` / `AskUserQuestion` | ❓ yellow question |
| Claude needs permission or goes idle | `Notification` | ❓ yellow question |
| A turn is aborted by an API error | `StopFailure` | ❌ red cross |

Each notification shows the Claude logo, the status icon, and two lines of context —
the folder and a short prompt summary:

```
●  Claude Code
   Prompt finished!
   my-project:
   fix the login bug and add tests
```

On Windows the Claude logo sits in the toast header and the status icon appears inside the toast. On
macOS the Claude logo is the alert icon and the status icon is shown as the content thumbnail.

> **Messages are localized automatically** to your system display language. See
> **[Language](#language)** for the supported languages and how to override the choice.

---

## Requirements

- **Claude Code** (which provides the bundled `node` runtime the hooks dispatch through)

**On Windows:**

- **Windows 10 or 11**
- Windows notifications enabled (*Settings → System → Notifications*)

**On macOS:**

- **macOS 10.15+**
- Notifications allowed for the notifier (*System Settings → Notifications*)
- **[terminal-notifier](https://github.com/julienXX/terminal-notifier)** (optional but recommended)
  for the Claude logo and status icon — `brew install terminal-notifier`. Without it, notifications
  still work via the built-in `osascript`, just without the custom icons.

---

## Install

In Claude Code, add this repository as a plugin marketplace and install the plugin:

```
/plugin marketplace add EvandroLucas/notify-me
/plugin install windows-toast-notify@notify-me
```

Then **restart Claude Code** (or start a new session). The hooks begin firing automatically — no
per-session approval. On macOS, run `brew install terminal-notifier` first if you want the Claude
logo and status icons (see [Requirements](#requirements)).

Check it is enabled with:

```
/plugin list
```

---

## How it works

It's a **pure plugin** — it does **not** touch your `settings.json`. Everything ships inside the plugin.

Every hook in `hooks/hooks.json` runs the same cross-platform entry point, `scripts/dispatch.mjs`,
through the `node` runtime that ships with Claude Code. The dispatcher reads the hook's JSON from
stdin (current folder, session id, prompt) and routes by operating system:

- **On Windows**, it forwards to the PowerShell scripts, which build a native toast via the WinRT
  notification APIs:
  - **`SessionStart` → `register-app.ps1`** registers a Windows App User Model ID
    (`HKCU\Software\Classes\AppUserModelId\ClaudeCode.NotifyMe`) so the Claude logo appears in the
    toast header. Per-user, idempotent, no administrator rights.
  - **`UserPromptSubmit` → `capture-prompt.ps1`** saves your prompt for the session.
  - **`notify.ps1`** builds and shows each toast.
- **On macOS**, the dispatcher shows the alert itself — via
  [`terminal-notifier`](https://github.com/julienXX/terminal-notifier) when installed (Claude logo as
  the app icon, status icon as the content image), falling back to the built-in `osascript` otherwise.
  `SessionStart` is a no-op (macOS needs no app registration), and `UserPromptSubmit` saves the prompt
  summary the same way.

The prompt summary is cached per session under your temp directory (`%TEMP%\claude-toast-prompts` on
Windows, `$TMPDIR/claude-toast-prompts` on macOS).

Icons are bundled with the plugin and referenced through `${CLAUDE_PLUGIN_ROOT}`, so nothing is copied
into your profile.

---

## Language

The notification text is **localized automatically** based on your system display language — the
Windows UI culture (`CurrentUICulture`) on Windows, or the preferred `AppleLanguages` on macOS. If your
language isn't available, it falls back to **English**.

**Supported languages:**

English · Português (Brasil) · 中文 (Mandarin) · हिन्दी (Hindi) · Español · العربية (Arabic) ·
Français · বাংলা (Bengali) · Bahasa Indonesia · اردو (Urdu) · 日本語 (Japanese) · Deutsch ·
Русский (Russian) · Italiano · Nederlands · Polski · Türkçe · 한국어 (Korean)

### Force a specific language

Set the `NOTIFY_ME_LANG` environment variable to a two-letter code
(`en`, `pt`, `zh`, `hi`, `es`, `ar`, `fr`, `bn`, `id`, `ur`, `ja`, `de`, `ru`, `it`, `nl`, `pl`, `tr`, `ko`).
For example, to force Japanese:

```powershell
# Windows (PowerShell)
setx NOTIFY_ME_LANG ja
```

```bash
# macOS (zsh/bash) — add to ~/.zshrc or ~/.zprofile
export NOTIFY_ME_LANG=ja
```

Then restart Claude Code. Unset it to go back to auto-detection (`setx NOTIFY_ME_LANG ""` on Windows,
or remove the `export` line on macOS).

### Edit or add translations

All strings live in [`plugins/windows-toast-notify/scripts/messages.json`](plugins/windows-toast-notify/scripts/messages.json),
keyed by language code and then by message (`finished`, `error`, `attention`, `question`). Edit a value
to reword it, or add a new top-level language block to support another language. Save the file as
**UTF-8** and restart Claude Code.

---

## Uninstall

```
/plugin uninstall windows-toast-notify@notify-me
```

To also remove the Windows app registration (optional):

```powershell
Remove-Item 'HKCU:\SOFTWARE\Classes\AppUserModelId\ClaudeCode.NotifyMe' -Recurse
```

---

## Repository layout

```
notify-me/
├── .claude-plugin/
│   └── marketplace.json            # marketplace manifest (this repo)
├── plugins/
│   └── windows-toast-notify/
│       ├── .claude-plugin/
│       │   └── plugin.json          # plugin manifest
│       ├── hooks/
│       │   └── hooks.json           # the notification hooks
│       ├── scripts/
│       │   ├── dispatch.mjs         # cross-platform entry point (routes by OS)
│       │   ├── notify.ps1           # Windows: builds and shows the toast
│       │   ├── register-app.ps1     # Windows: registers the app id (SessionStart)
│       │   ├── capture-prompt.ps1   # Windows: saves the prompt (UserPromptSubmit)
│       │   └── messages.json        # localized strings
│       └── icons/                   # logo + status icons
└── README.md
```

---

## License

[MIT](LICENSE) © Evandro Teixeira
