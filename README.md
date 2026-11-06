# agent-voice

**Hear what your AI coding agent needs, without watching the screen.**

When Claude Code, Codex or Grok Build CLI stops, a voice tells you why: the task is finished, it is asking you something, it needs your approval, or it failed. Windows only, no extra software, one command to install.

[中文说明](#中文说明)

## What you'll hear

| You hear | When | Claude Code | Codex | Grok Build CLI |
|---|---|:---:|:---:|:---:|
| **"Task finished"** | The agent finished its turn | ✓ | ✓ | ✓ |
| **"Waiting for your reply"** | The turn ended on a question (last line ends with `?` or `？`) | ✓ | ✓ | ✓ |
| **"Action required"** | It wants you to pick an option, approve a plan or allow a tool | ✓ | | ✓ |
| **"Task failed"** | The turn stopped on an error | | | ✓ |

Codex only reports the end of a turn, so it can't announce approvals or errors.

## Install

Open **PowerShell** (not as administrator) and run:

```powershell
irm https://raw.githubusercontent.com/kjw0716/agent-voice/main/install.ps1 | iex
```

You'll hear "Task finished" as a test. Then **restart Claude, Codex and Grok** so they load the new settings.

The installer only sets up the tools it finds on your computer. Run it again any time, for example after installing another tool. It won't add anything twice.

**Requirements:** Windows 10 or 11, plus at least one of the tools. Windows PowerShell and the voices come with Windows.

<details>
<summary>Install from a clone instead</summary>

```powershell
git clone https://github.com/kjw0716/agent-voice.git
cd agent-voice
powershell -ExecutionPolicy Bypass -File .\install.ps1
```

Options: `-Only claude,codex,grok` sets up only the tools you list, and `-NoTest` skips the test voice.
</details>

## What the installer changes

Before it edits a config file, it saves a copy next to it named `<file>.agent-voice-backup-<date>-<time>`.

| Tool | File | Change |
|---|---|---|
| All | `%USERPROFILE%\.agent-voice\` | The scripts, plus `config.json` for your settings |
| Claude Code | `~\.claude\settings.json` | Adds a `Stop` hook, a `PreToolUse` hook for questions and plan approval, and a `Notification` hook for permission prompts. Your other hooks stay. |
| Codex | `~\.codex\config.toml` | Points `notify` at agent-voice. A notifier you already had still runs first. If the Codex computer-use plugin owns `notify`, agent-voice goes into the plugin's `--previous-notify` slot instead of replacing it. |
| Grok Build CLI | `~\.grok\hooks\agent-voice.json` and `~\.grok\config.toml` | Adds `Stop` and `StopFailure` hooks, turns off Grok's own notification bell, and announces approvals and errors |

## Change the voice or the words

Edit `%USERPROFILE%\.agent-voice\config.json`. Changes apply to the next announcement, with no restart needed.

```json
{
  "voice": "Microsoft Zira Desktop",
  "rate": 0,
  "volume": 100,
  "finished": "Task finished",
  "question": "Waiting for your reply",
  "action": "Action required",
  "error": "Task failed"
}
```

- `rate` goes from `-10` (slow) to `10` (fast). `volume` goes from `0` to `100`.
- Set a phrase to `""` to keep that event silent.
- If the voice you name isn't installed, Windows uses its default voice.

List the voices on your computer:

```powershell
Add-Type -AssemblyName System.Speech; (New-Object System.Speech.Synthesis.SpeechSynthesizer).GetInstalledVoices().VoiceInfo.Name
```

For example, to use Chinese, set `"voice": "Microsoft Huihui Desktop"` and write the phrases in Chinese, such as `"finished": "任务完成"`. You can add more voices in **Windows Settings → Time & language → Speech**.

Try it at any time:

```powershell
powershell -ExecutionPolicy Bypass -File "$env:USERPROFILE\.agent-voice\agent-voice.ps1" -Event action
```

## Uninstall

```powershell
& ([scriptblock]::Create((irm https://raw.githubusercontent.com/kjw0716/agent-voice/main/install.ps1))) -Uninstall
```

This removes the hooks and restores Codex's previous `notify` setting. It also deletes `%USERPROFILE%\.agent-voice`, including your `config.json`. The backup copies of your config files stay.

## Troubleshooting

**No voice at all.** Restart the app or CLI first, because they read their settings at startup. Then run the test command above. If the test is silent too, check the volume and the output device in Windows.

**Grok is silent in a project folder.** Grok runs your own hooks only in folders you trust. Run `/hooks-trust` in that folder once. Your home folder is always trusted.

**Grok still plays its own bell.** You already had a `[ui.notifications]` section in `~\.grok\config.toml`, so the installer left it alone. Add `method = "none"` to that section yourself.

**You hear a line twice.** Grok also runs Claude Code's hooks, so agent-voice says each phrase at most once every 3 seconds. If you still hear doubles, open an issue and say which tool you were using.

**Codex is silent after a Codex update.** The computer-use plugin can rewrite `notify`. Run the installer again.

**"Waiting for your reply" didn't play for a question.** It only checks whether the last line ends with a question mark. A question phrased as "Let me know which one you want." counts as finished.

## How it works

`agent-voice.ps1` reads the event that the tool sends, picks a phrase, and speaks it with the speech engine built into Windows (`System.Speech`). Claude Code and Grok call it as a hook. Codex calls `codex-notify.ps1` through its `notify` setting, and that script chains to the notifier you had before. Nothing is sent over the network.

## License

[MIT](LICENSE)

---

## 中文说明

**不用盯着屏幕，也能知道 AI 编程助手在等你做什么。**

Claude Code、Codex、Grok Build CLI 停下来时，会用语音告诉你原因：任务完成、在问你问题、需要你批准，或者出错了。只支持 Windows，不用装别的软件，一条命令就能装好。

### 会说什么

| 语音 | 什么时候 | Claude Code | Codex | Grok |
|---|---|:---:|:---:|:---:|
| **"Task finished"** | 任务完成 | ✓ | ✓ | ✓ |
| **"Waiting for your reply"** | 最后一句是问题（以 `?` 或 `？` 结尾） | ✓ | ✓ | ✓ |
| **"Action required"** | 要你选选项、批准计划或允许使用工具 | ✓ | | ✓ |
| **"Task failed"** | 出错停止 | | | ✓ |

### 安装

打开 **PowerShell**（不需要管理员权限），运行：

```powershell
irm https://raw.githubusercontent.com/kjw0716/agent-voice/main/install.ps1 | iex
```

装好后会播放一次 "Task finished" 作为测试。然后**重启 Claude、Codex、Grok**，让它们读到新设置。只会设置电脑上已经装了的工具，重复运行也不会重复添加。改配置前，会在原文件旁边保存一份备份。

### 改声音或改说的话

编辑 `%USERPROFILE%\.agent-voice\config.json`，保存后下次提示就生效，不用重启。想用中文，可以把 `voice` 改成 `"Microsoft Huihui Desktop"`，再把各句话改成中文，比如 `"finished": "任务完成"`、`"action": "需要你操作"`。把某句改成 `""` 就不会播放那一句。

### 卸载

```powershell
& ([scriptblock]::Create((irm https://raw.githubusercontent.com/kjw0716/agent-voice/main/install.ps1))) -Uninstall
```

卸载会删掉 `%USERPROFILE%\.agent-voice` 文件夹，包括你的 `config.json`。

### 常见问题

- **完全没声音**：先重启对应软件，再运行上面 "Try it at any time" 里的测试命令。
- **Grok 在某个项目里没声音**：在那个文件夹里运行一次 `/hooks-trust`。
- **Grok 还在响自己的提示音**：你原来的 `~\.grok\config.toml` 里已经有 `[ui.notifications]`，在那一节里加上 `method = "none"`。
- **Codex 更新后没声音了**：重新运行一次安装命令。
