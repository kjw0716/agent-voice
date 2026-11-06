# agent-voice: speaks a short status line for AI coding agents (Claude Code, Codex, Grok Build CLI).
#   -Event stop    turn ended: "Task finished", or "Waiting for your reply" if the last message asks a question
#   -Event action  the agent needs a choice or an approval: "Action required"
#   -Event error   the turn failed: "Task failed"
# Hook event JSON on stdin is read for -Event stop when -Message is not given.
# Optional overrides live in config.json next to this script (see README).
param(
    [ValidateSet('stop', 'action', 'error')][string]$Event = 'stop',
    [string]$Message
)

$settings = @{
    voice    = 'Microsoft Zira Desktop'
    rate     = 0
    volume   = 100
    finished = 'Task finished'
    question = 'Waiting for your reply'
    action   = 'Action required'
    error    = 'Task failed'
}
$configPath = Join-Path $PSScriptRoot 'config.json'
if (Test-Path -LiteralPath $configPath) {
    try {
        $config = Get-Content -LiteralPath $configPath -Raw -Encoding UTF8 | ConvertFrom-Json
        foreach ($p in $config.PSObject.Properties) { $settings[$p.Name] = $p.Value }
    } catch {}
}

function Get-LastAssistantText($data) {
    foreach ($key in 'last_assistant_message', 'lastAssistantMessage', 'last-assistant-message') {
        if ($data.$key) { return [string]$data.$key }
    }
    $transcript = if ($data.transcript_path) { $data.transcript_path } else { $data.transcriptPath }
    if ($transcript -and (Test-Path -LiteralPath $transcript)) {
        $lines = Get-Content -LiteralPath $transcript -Tail 200 -Encoding UTF8
        for ($i = $lines.Count - 1; $i -ge 0; $i--) {
            try { $entry = $lines[$i] | ConvertFrom-Json } catch { continue }
            if ($entry.type -ne 'assistant') { continue }
            $text = @($entry.message.content | Where-Object { $_.type -eq 'text' } | ForEach-Object { $_.text }) -join "`n"
            if ($text.Trim()) { return $text }
        }
    }
    return ''
}

if ($Event -eq 'stop' -and -not $Message -and [Console]::IsInputRedirected) {
    try {
        [Console]::InputEncoding = [Text.Encoding]::UTF8
        $raw = [Console]::In.ReadToEnd()
        if ($raw.Trim()) { $Message = Get-LastAssistantText ($raw | ConvertFrom-Json) }
    } catch {}
}

$text = switch ($Event) {
    'action' { $settings.action }
    'error'  { $settings.error }
    default {
        $lastLine = @(([string]$Message).Trim() -split "`r?`n" | Where-Object { $_.Trim() })[-1]
        # ASCII or full-width question mark, optionally followed by markdown bold stars.
        if ($lastLine -and $lastLine.Trim() -match "[?$([char]0xFF1F)]\**$") { $settings.question } else { $settings.finished }
    }
}
if (-not $text) { exit 0 }

# Several hooks can fire for one event (Grok also runs Claude's hooks): say each line once per 3 seconds.
$stamp = Join-Path $PSScriptRoot ('.last-' + $Event + '-' + [Math]::Abs($text.GetHashCode()))
try {
    $age = (Get-Date) - (Get-Item -LiteralPath $stamp -ErrorAction Stop).LastWriteTime
    if ($age.TotalSeconds -lt 3) { exit 0 }
} catch {}
try { Set-Content -LiteralPath $stamp -Value '' -ErrorAction Stop } catch {}

Add-Type -AssemblyName System.Speech
$speaker = New-Object System.Speech.Synthesis.SpeechSynthesizer
try { $speaker.SelectVoice($settings.voice) } catch {}
$speaker.Rate = [int]$settings.rate
$speaker.Volume = [int]$settings.volume
$speaker.Speak($text)
$speaker.Dispose()
try { Set-Content -LiteralPath $stamp -Value '' -ErrorAction Stop } catch {}
exit 0
