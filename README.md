# notify-me

**Native Windows toast notifications for [Claude Code](https://www.claude.com/product/claude-code).**
Know the moment a prompt finishes, Claude asks you something, or something goes wrong — without babysitting the terminal.

When Claude is working on a long task you usually switch to something else. `notify-me` pops a native
Windows notification the instant Claude needs you or finishes, showing **which project** it is and a
**short summary of your prompt**, so you can tell sessions apart at a glance.

---

## What you get

| When it fires | Hook event | Status icon |
|---|---|---|
| A prompt finishes | `Stop` | ✅ green check |
| Claude asks you a question | `PreToolUse` / `AskUserQuestion` | ❓ yellow question |
| Claude needs permission or goes idle | `Notification` | ❓ yellow question |
| A turn is aborted by an API error | `StopFailure` | ❌ red cross |

Each notification shows the Claude logo in the header, the status icon, and two lines of context —
the folder and a short prompt summary:

```
●  Claude Code
   Prompt finished!
   my-project:
   fix the login bug and add tests
```

> **Messages are localized automatically** to your Windows display language. See
> **[Language](#language)** for the supported languages and how to override the choice.

---

## Requirements

- **Windows 10 or 11**
- **Claude Code**
- Windows notifications enabled (*Settings → System → Notifications*)

---

## Install

In Claude Code, add this repository as a plugin marketplace and install the plugin:

```
/plugin marketplace add EvandroLucas/notify-me
/plugin install windows-toast-notify@notify-me
```

Then **restart Claude Code** (or start a new session). On the next session start the app is registered
and the hooks begin firing automatically — no per-session approval.

Check it is enabled with:

```
/plugin list
```

---

## How it works

It's a **pure plugin** — it does **not** touch your `settings.json`. Everything ships inside the plugin.

- **Hooks** (`hooks/hooks.json`) fire on `Stop`, `StopFailure`, `Notification`, and
  `PreToolUse`/`AskUserQuestion`.
- **`SessionStart` → `register-app.ps1`** registers a Windows App User Model ID
  (`HKCU\Software\Classes\AppUserModelId\ClaudeCode.NotifyMe`) so the Claude logo can appear in the
  notification header. It's per-user, idempotent, and needs no administrator rights.
- **`UserPromptSubmit` → `capture-prompt.ps1`** saves your prompt for the session so the notification
  can show a short summary.
- **`notify.ps1`** builds and shows each toast, reading the hook's JSON from stdin to get the current
  working folder.

Icons are bundled with the plugin and referenced through `${CLAUDE_PLUGIN_ROOT}`, so nothing is copied
into your profile.

---

## Language

The notification text is **localized automatically** based on your Windows display language
(`CurrentUICulture`). If your language isn't available, it falls back to **English**.

**Supported languages:**

English · Português (Brasil) · 中文 (Mandarin) · हिन्दी (Hindi) · Español · العربية (Arabic) ·
Français · বাংলা (Bengali) · Bahasa Indonesia · اردو (Urdu) · 日本語 (Japanese) · Deutsch ·
Русский (Russian) · Italiano · Nederlands · Polski · Türkçe · 한국어 (Korean)

### Force a specific language

Set the `NOTIFY_ME_LANG` environment variable to a two-letter code
(`en`, `pt`, `zh`, `hi`, `es`, `ar`, `fr`, `bn`, `id`, `ur`, `ja`, `de`, `ru`, `it`, `nl`, `pl`, `tr`, `ko`).
For example, to force Japanese:

```powershell
setx NOTIFY_ME_LANG ja
```

Then restart Claude Code. Unset it (`setx NOTIFY_ME_LANG ""`) to go back to auto-detection.

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
│       │   ├── notify.ps1           # builds and shows the toast
│       │   ├── register-app.ps1     # registers the app id (SessionStart)
│       │   └── capture-prompt.ps1   # saves the prompt (UserPromptSubmit)
│       └── icons/                   # logo + status icons
└── README.md
```

---

## License

[MIT](LICENSE) © Evandro Teixeira
