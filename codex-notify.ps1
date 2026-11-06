# agent-voice wrapper for Codex `notify`: runs the notify command you had before (if any), then speaks.
# Codex appends the event JSON as the last argument.
$payload = if ($args.Count) { [string]$args[-1] } else { '' }

function Quote-Arg([string]$a) {
    if ($a.Length -and $a -notmatch '[\s"]') { return $a }
    $out = '"'; $bs = 0
    foreach ($c in $a.ToCharArray()) {
        if ($c -eq '\') { $bs++; continue }
        if ($c -eq '"') { $out += ('\' * ($bs * 2 + 1)) + '"' } else { $out += ('\' * $bs) + $c }
        $bs = 0
    }
    return $out + ('\' * ($bs * 2)) + '"'
}

# Previous notify argv, saved by install.ps1 as a JSON array.
$proc = $null
$previousPath = Join-Path $PSScriptRoot 'codex-previous-notify.json'
if (Test-Path -LiteralPath $previousPath) {
    try {
        $previous = @(Get-Content -LiteralPath $previousPath -Raw -Encoding UTF8 | ConvertFrom-Json | ForEach-Object { $_ })
        if ($previous.Count) {
            $psi = New-Object System.Diagnostics.ProcessStartInfo
            $psi.FileName = [string]$previous[0]
            $psi.Arguments = (@($previous | Select-Object -Skip 1) + @($args) | ForEach-Object { Quote-Arg ([string]$_) }) -join ' '
            $psi.UseShellExecute = $false
            $psi.CreateNoWindow = $true
            $proc = [System.Diagnostics.Process]::Start($psi)
        }
    } catch {}
}

$data = $null
try { $data = $payload | ConvertFrom-Json } catch {}
$voice = Join-Path $PSScriptRoot 'agent-voice.ps1'
if ($data.type -match 'approval|permission|input|elicit') {
    & $voice -Event action
} elseif ($data.type -match 'error|fail') {
    & $voice -Event error
} else {
    $last = [string]$data.'last-assistant-message'
    & $voice -Event stop -Message $(if ($last) { $last } else { ' ' })
}

if ($proc) { [void]$proc.WaitForExit(15000) }
exit 0
