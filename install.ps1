# agent-voice installer for Windows.
#   Install:    irm https://raw.githubusercontent.com/kjw0716/agent-voice/main/install.ps1 | iex
#   Uninstall:  & ([scriptblock]::Create((irm https://raw.githubusercontent.com/kjw0716/agent-voice/main/install.ps1))) -Uninstall
# From a clone:  .\install.ps1 [-Uninstall] [-Only claude,codex,grok] [-NoTest]
param(
    [switch]$Uninstall,
    [ValidateSet('claude', 'codex', 'grok')][string[]]$Only = @('claude', 'codex', 'grok'),
    [switch]$NoTest,
    [string]$HomeDir = $env:USERPROFILE
)

$CallerErrorAction = $ErrorActionPreference
$ErrorActionPreference = 'Stop'
$RawBase = 'https://raw.githubusercontent.com/kjw0716/agent-voice/main'
$InstallDir = Join-Path $HomeDir '.agent-voice'
$VoiceScript = (Join-Path $InstallDir 'agent-voice.ps1') -replace '\\', '/'
$Stamp = Get-Date -Format 'yyyyMMdd-HHmmss'
$Utf8 = New-Object System.Text.UTF8Encoding $false

if ($PSVersionTable.PSEdition -eq 'Core' -and -not $IsWindows) { throw 'agent-voice uses Windows speech and only runs on Windows.' }

function Say([string]$msg, [string]$color = 'Gray') { Write-Host $msg -ForegroundColor $color }
function Read-Text($path) { if (Test-Path -LiteralPath $path) { [IO.File]::ReadAllText($path, $Utf8) } else { '' } }
function Write-Text($path, [string]$text) { [IO.File]::WriteAllText($path, $text, $Utf8) }
function Backup($path) {
    if (Test-Path -LiteralPath $path) { Copy-Item -LiteralPath $path "$path.agent-voice-backup-$Stamp" }
}
function Hook-Command([string]$event) {
    "powershell -NoProfile -ExecutionPolicy Bypass -File `"$VoiceScript`" -Event $event"
}

# Pretty-prints compact JSON with 2-space indentation (Windows PowerShell's own output is hard to read),
# and turns its <-style escapes for < > & ' back into the plain characters.
function Format-Json([string]$json) {
    $sb = New-Object System.Text.StringBuilder
    $depth = 0; $inString = $false; $escaped = $false
    $plain = @{}
    foreach ($pair in @(('3c', '<'), ('3e', '>'), ('26', '&'), ('27', "'"))) { $plain['\' + 'u00' + $pair[0]] = $pair[1] }
    for ($i = 0; $i -lt $json.Length; $i++) {
        $c = $json[$i]
        if ($inString) {
            if (-not $escaped -and $c -eq '\' -and $i + 6 -le $json.Length -and $plain.ContainsKey($json.Substring($i, 6))) {
                [void]$sb.Append($plain[$json.Substring($i, 6)]); $i += 5; continue
            }
            [void]$sb.Append($c)
            if ($escaped) { $escaped = $false } elseif ($c -eq '\') { $escaped = $true } elseif ($c -eq '"') { $inString = $false }
            continue
        }
        switch ($c) {
            '"' { $inString = $true; [void]$sb.Append($c) }
            { $_ -eq '{' -or $_ -eq '[' } {
                $close = if ($c -eq '{') { '}' } else { ']' }
                if ($i + 1 -lt $json.Length -and $json[$i + 1] -eq $close) { [void]$sb.Append("$c$close"); $i++; break }
                $depth++; [void]$sb.Append($c).Append("`n").Append('  ' * $depth)
            }
            { $_ -eq '}' -or $_ -eq ']' } { $depth--; [void]$sb.Append("`n").Append('  ' * $depth).Append($c) }
            ',' { [void]$sb.Append(",`n").Append('  ' * $depth) }
            ':' { [void]$sb.Append(': ') }
            default { [void]$sb.Append($c) }
        }
    }
    $sb.ToString() + "`n"
}

function Install-Files {
    New-Item -ItemType Directory -Force -Path $InstallDir | Out-Null
    foreach ($name in 'agent-voice.ps1', 'codex-notify.ps1') {
        $target = Join-Path $InstallDir $name
        $local = if ($PSScriptRoot) { Join-Path $PSScriptRoot $name }
        if ($local -and (Test-Path -LiteralPath $local)) {
            Copy-Item -LiteralPath $local $target -Force
        } else {
            [Net.ServicePointManager]::SecurityProtocol = [Net.ServicePointManager]::SecurityProtocol -bor [Net.SecurityProtocolType]::Tls12
            Invoke-WebRequest -UseBasicParsing "$RawBase/$name" -OutFile $target
        }
    }
    $config = Join-Path $InstallDir 'config.json'
    if (-not (Test-Path -LiteralPath $config)) {
        Write-Text $config (Format-Json (ConvertTo-Json -Compress -InputObject ([ordered]@{
            voice = 'Microsoft Zira Desktop'; rate = 0; volume = 100
            finished = 'Task finished'; question = 'Waiting for your reply'
            action = 'Action required'; error = 'Task failed'
        })))
    }
    Say "  Scripts in $InstallDir"
}

# ---------- Claude Code: ~/.claude/settings.json ----------
function Set-Claude {
    $dir = Join-Path $HomeDir '.claude'
    if (-not (Test-Path -LiteralPath $dir)) { Say '  Claude Code: not found, skipped'; return }
    $file = Join-Path $dir 'settings.json'
    $text = Read-Text $file
    $settings = if ($text.Trim()) { $text | ConvertFrom-Json } else { New-Object PSObject }
    if (-not $settings.hooks) {
        if ($Uninstall) { Say '  Claude Code: nothing to remove'; return }
        $settings | Add-Member -NotePropertyName hooks -NotePropertyValue (New-Object PSObject) -Force
    }
    $hooks = $settings.hooks

    # Drop any earlier agent-voice hooks, keeping everything else.
    foreach ($eventName in @($hooks.PSObject.Properties | ForEach-Object { $_.Name })) {
        $groups = @()
        foreach ($group in @($hooks.$eventName)) {
            $kept = @(@($group.hooks) | Where-Object { [string]$_.command -notlike '*agent-voice*' })
            if ($kept.Count -eq @($group.hooks).Count) { $groups += $group }
            elseif ($kept.Count) { $group.hooks = $kept; $groups += $group }
        }
        if ($groups.Count) { $hooks.$eventName = $groups } else { $hooks.PSObject.Properties.Remove($eventName) }
    }

    if (-not $Uninstall) {
        $add = [ordered]@{
            Stop         = @{ hooks = @(@{ type = 'command'; command = (Hook-Command 'stop'); timeout = 15 }) }
            PreToolUse   = @{ matcher = 'AskUserQuestion|ExitPlanMode'; hooks = @(@{ type = 'command'; command = (Hook-Command 'action'); timeout = 15 }) }
            Notification = @{ matcher = 'permission_prompt|elicitation_dialog'; hooks = @(@{ type = 'command'; command = (Hook-Command 'action'); timeout = 15 }) }
        }
        foreach ($eventName in $add.Keys) {
            $existing = if ($hooks.PSObject.Properties[$eventName]) { @($hooks.$eventName) } else { @() }
            $hooks | Add-Member -NotePropertyName $eventName -NotePropertyValue (@($existing) + @([pscustomobject]$add[$eventName])) -Force
        }
    }

    Backup $file
    Write-Text $file (Format-Json (ConvertTo-Json -Compress -Depth 100 -InputObject $settings))
    Say $(if ($Uninstall) { '  Claude Code: hooks removed' } else { '  Claude Code: Stop, question and permission hooks added' }) Green
}

# ---------- Codex: ~/.codex/config.toml `notify` ----------
function ConvertTo-TomlString([string]$s) {
    if ($s -notmatch "['\r\n]") { return "'$s'" }
    return (ConvertTo-Json -Compress -InputObject $s)
}
function ConvertFrom-TomlArray([string]$line) {
    # Read only up to the array's closing bracket, so quoted text in a trailing comment is ignored.
    $quote = $null; $end = $line.Length
    for ($i = 0; $i -lt $line.Length; $i++) {
        $c = $line[$i]
        if ($quote) {
            if ($quote -eq '"' -and $c -eq '\') { $i++ } elseif ($c -eq $quote) { $quote = $null }
        } elseif ($c -eq '"' -or $c -eq "'") { $quote = $c }
        elseif ($c -eq ']') { $end = $i; break }
    }
    $items = @()
    foreach ($m in [regex]::Matches($line.Substring(0, $end), "'([^']*)'|`"((?:[^`"\\]|\\.)*)`"")) {
        if ($m.Groups[1].Success) { $items += $m.Groups[1].Value }
        else { $items += ('"' + $m.Groups[2].Value + '"' | ConvertFrom-Json) }
    }
    $items  # callers wrap the result in @()
}

function Set-Codex {
    $dir = Join-Path $HomeDir '.codex'
    if (-not (Test-Path -LiteralPath $dir)) { Say '  Codex: not found, skipped'; return }
    $file = Join-Path $dir 'config.toml'
    $previousFile = Join-Path $InstallDir 'codex-previous-notify.json'
    $lines = [System.Collections.Generic.List[string]]@(((Read-Text $file) -replace "`r", '') -split "`n")
    if ($lines.Count -eq 1 -and $lines[0] -eq '') { $lines.Clear() }

    # `notify` is a top-level key, so it sits before the first [table].
    $index = -1
    for ($i = 0; $i -lt $lines.Count; $i++) {
        if ($lines[$i] -match '^\s*\[') { break }
        if ($lines[$i] -match '^\s*notify\s*=') { $index = $i; break }
    }
    if ($index -ge 0 -and $lines[$index] -notmatch '\]\s*(#.*)?$') {
        $script:Incomplete = $true
        Say '  Codex: your notify setting spans several lines; edit it by hand (see README)' Yellow
        return
    }
    $current = @(if ($index -ge 0) { ConvertFrom-TomlArray $lines[$index] })
    $ours = @('powershell.exe', '-NoProfile', '-ExecutionPolicy', 'Bypass', '-WindowStyle', 'Hidden', '-File', (Join-Path $InstallDir 'codex-notify.ps1'))
    $isOurs = { param($argv) @($argv | Where-Object { [string]$_ -like '*codex-notify.ps1' }).Count -gt 0 }
    $previous = @(if (Test-Path -LiteralPath $previousFile) { Get-Content -LiteralPath $previousFile -Raw | ConvertFrom-Json | ForEach-Object { $_ } })

    # Codex's computer-use plugin owns `notify` and calls the real notifier through --previous-notify <JSON argv>.
    # Put ourselves inside that slot instead of replacing the plugin (it would rewrite the line anyway).
    $wrapped = $current.Count -and ([string]$current[0] -like '*codex-computer-use.exe')
    $slot = [array]::IndexOf([string[]]$current, '--previous-notify')
    $inner = @(if ($wrapped -and $slot -ge 0 -and $slot + 1 -lt $current.Count) { [string]$current[$slot + 1] | ConvertFrom-Json | ForEach-Object { $_ } })
    $target = if ($wrapped) { $inner } else { $current }

    if ($Uninstall) {
        if (-not (& $isOurs $target)) { Say '  Codex: nothing to remove'; return }
        if ($wrapped) {
            if ($previous.Count) { $current[$slot + 1] = ConvertTo-Json -Compress -InputObject $previous }
            else { $current = @($current[0..($slot - 1)]) + @($current | Select-Object -Skip ($slot + 2)) }
            $lines[$index] = 'notify = [ ' + (($current | ForEach-Object { ConvertTo-TomlString $_ }) -join ', ') + ' ]'
        } elseif ($previous.Count) {
            $lines[$index] = 'notify = [ ' + (($previous | ForEach-Object { ConvertTo-TomlString $_ }) -join ', ') + ' ]'
        } else {
            $lines.RemoveAt($index)
        }
        Backup $file
        Write-Text $file (($lines -join "`n").TrimEnd("`n") + "`n")
        Say '  Codex: notify restored' Green
        return
    }

    New-Item -ItemType Directory -Force -Path $InstallDir | Out-Null
    if (-not (& $isOurs $target)) {
        if ($target.Count) { Write-Text $previousFile (ConvertTo-Json -Compress -InputObject @($target)) }
        elseif (Test-Path -LiteralPath $previousFile) { Remove-Item -LiteralPath $previousFile }
    }
    if ($wrapped) {
        $json = ConvertTo-Json -Compress -InputObject $ours
        if ($slot -ge 0) { $current[$slot + 1] = $json } else { $current = @($current) + @('--previous-notify', $json) }
        $argv = $current
    } else {
        $argv = $ours
    }
    $newLine = 'notify = [ ' + (($argv | ForEach-Object { ConvertTo-TomlString $_ }) -join ', ') + ' ]'
    if ($index -ge 0) { $lines[$index] = $newLine } else { $lines.Insert(0, $newLine) }
    Backup $file
    Write-Text $file (($lines -join "`n").TrimEnd("`n") + "`n")
    $note = if (-not (& $isOurs $target) -and $target.Count) { ' (your previous notify command still runs first)' } else { '' }
    Say "  Codex: notify set$note" Green
}

# ---------- Grok Build CLI: ~/.grok ----------
$GrokBegin = '# >>> agent-voice >>>'
$GrokEnd = '# <<< agent-voice <<<'

function Set-Grok {
    $dir = Join-Path $HomeDir '.grok'
    if (-not (Test-Path -LiteralPath $dir)) { Say '  Grok: not found, skipped'; return }
    $hookFile = Join-Path $dir 'hooks\agent-voice.json'
    $file = Join-Path $dir 'config.toml'
    $text = (Read-Text $file) -replace "`r", ''
    $stripped = [regex]::Replace($text, "(?s)\n*$([regex]::Escape($GrokBegin)).*?$([regex]::Escape($GrokEnd))\n?", "`n").TrimEnd("`n")

    if ($Uninstall) {
        if (Test-Path -LiteralPath $hookFile) { Remove-Item -LiteralPath $hookFile }
        if ($stripped -ne $text.TrimEnd("`n")) { Backup $file; Write-Text $file ($stripped + "`n") }
        Say '  Grok: hooks removed' Green
        return
    }

    New-Item -ItemType Directory -Force -Path (Split-Path $hookFile) | Out-Null
    $hook = { param($e) @{ hooks = @(@{ type = 'command'; command = (Hook-Command $e); timeout = 15 }) } }
    Write-Text $hookFile (Format-Json (ConvertTo-Json -Compress -Depth 10 -InputObject @{
        hooks = [ordered]@{ Stop = @(& $hook 'stop'); StopFailure = @(& $hook 'error') }
    }))

    # [ui.notifications], a dotted ui.notifications key, or notifications = / notifications.x under [ui].
    if ($stripped -match '(?m)^\s*(\[\s*ui\s*\.\s*notifications\s*\]|ui\s*\.\s*notifications\b|notifications\s*[.=])') {
        Say '  Grok: Stop/failure hooks added. You already have [ui.notifications] in config.toml,' Yellow
        Say '        so add method = "none" there yourself to silence Grok''s own bell (see README).' Yellow
        return
    }
    $block = @(
        $GrokBegin
        '[ui.notifications]'
        'method = "none"'
        'events = ["turn_complete", "approval_required"]'
        ''
        '[[ui.notifications.hooks]]'
        ("command = " + (ConvertTo-TomlString (Hook-Command 'action')))
        'events = ["approval_required"]'
        'only_unfocused = false'
        'timeout_secs = 15'
        ''
        '[[ui.notifications.hooks]]'
        ("command = " + (ConvertTo-TomlString (Hook-Command 'error')))
        'events = ["agent_error"]'
        'only_unfocused = false'
        'timeout_secs = 15'
        $GrokEnd
    ) -join "`n"
    Backup $file
    Write-Text $file (((@($stripped, $block) | Where-Object { $_ }) -join "`n`n") + "`n")
    Say '  Grok: Stop, approval and failure hooks added; built-in bell turned off' Green
}

# ---------- main ----------
try {
    Say ''
    Say $(if ($Uninstall) { 'Removing agent-voice...' } else { 'Installing agent-voice...' }) Cyan
    if (-not $Uninstall) { Install-Files }
    # A config that fails to parse is left untouched; the other tools still get set up.
    $script:Incomplete = $false
    foreach ($tool in 'claude', 'codex', 'grok') {
        if ($Only -notcontains $tool) { continue }
        try { & "Set-$tool" }
        catch {
            $script:Incomplete = $true
            Say "  ${tool}: skipped, could not update its config ($($_.Exception.Message))" Yellow
        }
    }

    if ($Uninstall) {
        # Keep the scripts while any tool may still call them.
        if ($script:Incomplete -or @($Only | Select-Object -Unique).Count -lt 3) {
            Say "Kept $InstallDir because some tools still use it. Run -Uninstall without -Only to remove everything." Yellow
        } elseif (Test-Path -LiteralPath $InstallDir) {
            Remove-Item -LiteralPath $InstallDir -Recurse -Force
        }
        Say 'Done. Restart Claude, Codex and Grok.' Cyan
    } else {
        Say ''
        Say 'Done. Restart Claude, Codex and Grok so they load the new settings.' Cyan
        Say "Change the voice or the words in $InstallDir\config.json"
        if (-not $NoTest) {
            Say 'Playing a test...'
            & powershell -NoProfile -ExecutionPolicy Bypass -File (Join-Path $InstallDir 'agent-voice.ps1') -Event stop -Message 'done'
        }
    }
} finally {
    # `irm | iex` runs this in the caller's own session: put back what we changed there.
    $ErrorActionPreference = $CallerErrorAction
    if (-not $PSScriptRoot) { Remove-Variable Uninstall, Only, NoTest, HomeDir -ErrorAction SilentlyContinue }
}
