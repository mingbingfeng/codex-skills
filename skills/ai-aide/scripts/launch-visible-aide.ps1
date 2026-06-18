[CmdletBinding()]
param(
    [Parameter(Mandatory)]
    [string]$RepoRoot,

    [Parameter(Mandatory)]
    [string]$PromptPath,

    [Parameter(Mandatory)]
    [string]$TaskId,

    [ValidateSet('auto', 'wt', 'pwsh', 'powershell')]
    [string]$Terminal = 'auto',

    [string]$AideCommand = 'claude --dangerously-skip-permissions',

    [switch]$NoClipboard,

    [switch]$AllowAutoSubmit,

    [switch]$AllowParallelVisibleSessions,

    [int]$SubmitDelaySeconds = 8,

    [int]$SubmitRetries = 3,

    [int]$InitialLaunchProbeSeconds = 6,

    [int]$TaskSignalTimeoutSeconds = 45,

    [switch]$DryRun
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Quote-Single {
    param([Parameter(Mandatory)][string]$Value)
    $Value.Replace("'", "''")
}

function Resolve-AideCommand {
    param([Parameter(Mandatory)][string]$CommandLine)

    $trimmed = $CommandLine.Trim()
    if ($trimmed -notmatch '^(claude(?:\.exe)?)(?=\s|$)') {
        return $trimmed
    }

    $suffix = $trimmed.Substring($matches[1].Length)

    $nativeClaude = Get-Command claude.exe -ErrorAction SilentlyContinue
    if ($nativeClaude) {
        return ('"{0}"{1}' -f $nativeClaude.Source, $suffix)
    }

    $claudeShim = Get-Command claude -ErrorAction SilentlyContinue
    if ($claudeShim -and $claudeShim.Source -like '*.ps1') {
        $shimDir = Split-Path -Parent $claudeShim.Source
        $candidate = Join-Path $shimDir 'node_modules\@anthropic-ai\claude-code\bin\claude.exe'
        if (Test-Path -LiteralPath $candidate) {
            return ('"{0}"{1}' -f $candidate, $suffix)
        }
    }

    return $trimmed
}

function New-LaunchSpec {
    param(
        [Parameter(Mandatory)][string]$Candidate,
        [Parameter(Mandatory)][string]$WorkingDirectory,
        [Parameter(Mandatory)][string]$BootstrapPath
    )

    switch ($Candidate) {
        'wt' {
            $cmd = Get-Command wt.exe -ErrorAction SilentlyContinue
            if (-not $cmd) { return $null }
            return [pscustomobject]@{
                Terminal  = 'wt'
                FilePath  = $cmd.Source
                Arguments = @(
                    '-d', $WorkingDirectory,
                    'powershell.exe',
                    '-NoExit',
                    '-ExecutionPolicy', 'Bypass',
                    '-File', $BootstrapPath
                )
            }
        }
        'pwsh' {
            $cmd = Get-Command pwsh.exe -ErrorAction SilentlyContinue
            if (-not $cmd) { return $null }
            return [pscustomobject]@{
                Terminal  = 'pwsh'
                FilePath  = $cmd.Source
                Arguments = @(
                    '-NoExit',
                    '-ExecutionPolicy', 'Bypass',
                    '-File', $BootstrapPath
                )
            }
        }
        'powershell' {
            $cmd = Get-Command powershell.exe -ErrorAction SilentlyContinue
            if (-not $cmd) { return $null }
            return [pscustomobject]@{
                Terminal  = 'powershell'
                FilePath  = $cmd.Source
                Arguments = @(
                    '-NoExit',
                    '-ExecutionPolicy', 'Bypass',
                    '-File', $BootstrapPath
                )
            }
        }
        default {
            throw "Unsupported terminal candidate: $Candidate"
        }
    }
}

function Get-TargetWindow {
    param(
        [Parameter(Mandatory)][string]$PreferredTerminal,
        [int]$PreferredProcessId = 0
    )

    if ($PreferredProcessId -gt 0) {
        $exact = Get-Process -Id $PreferredProcessId -ErrorAction SilentlyContinue
        if ($exact -and $exact.MainWindowTitle) {
            return $exact
        }
    }

    $candidates = @()

    if ($PreferredTerminal -eq 'wt') {
        $candidates += Get-Process -Name WindowsTerminal -ErrorAction SilentlyContinue |
            Where-Object { $_.MainWindowTitle -and $_.MainWindowTitle -match 'Claude Code|Claude' }
    }

    $candidates += Get-Process -Name powershell,pwsh -ErrorAction SilentlyContinue |
        Where-Object { $_.MainWindowTitle -and ($_.MainWindowTitle -match 'Claude Code|Claude|AI Aide') }

    $target = $candidates |
        Sort-Object StartTime -Descending |
        Select-Object -First 1

    if ($target) { return $target }

    return $null
}

function Get-ForegroundProcessId {
    Add-Type -TypeDefinition @'
using System;
using System.Runtime.InteropServices;

public static class ForegroundWindowNative
{
    [DllImport("user32.dll")]
    public static extern IntPtr GetForegroundWindow();

    [DllImport("user32.dll")]
    public static extern uint GetWindowThreadProcessId(IntPtr hWnd, out uint lpdwProcessId);
}
'@ -ErrorAction SilentlyContinue | Out-Null

    $handle = [ForegroundWindowNative]::GetForegroundWindow()
    if ($handle -eq [IntPtr]::Zero) {
        return 0
    }

    $pid = 0
    [void][ForegroundWindowNative]::GetWindowThreadProcessId($handle, [ref]$pid)
    return [int]$pid
}

function Get-ExistingAideWindows {
    $terminals = Get-Process -Name powershell,pwsh,WindowsTerminal -ErrorAction SilentlyContinue
    $terminals | Where-Object {
        $_.MainWindowTitle -and $_.MainWindowTitle -like 'AI Aide -*'
    }
}

function Get-ClaudeProcessesStartedAfter {
    param([Parameter(Mandatory)][datetime]$StartedAfter)

    Get-Process -Name claude -ErrorAction SilentlyContinue |
        Where-Object {
            $_.StartTime -ge $StartedAfter.AddSeconds(-2)
        }
}

function Wait-ForTaskSignal {
    param(
        [Parameter(Mandatory)][string]$StatePath,
        [Parameter(Mandatory)][string]$ReportPath,
        [Parameter(Mandatory)][datetime]$StartedAt,
        [Parameter(Mandatory)][int]$TimeoutSeconds
    )

    $deadline = (Get-Date).AddSeconds($TimeoutSeconds)
    while ((Get-Date) -lt $deadline) {
        $stateItem = Get-Item -LiteralPath $StatePath -ErrorAction SilentlyContinue
        if ($stateItem -and $stateItem.LastWriteTime -ge $StartedAt) {
            return [pscustomobject]@{
                Kind      = 'state'
                Path      = $StatePath
                Timestamp = $stateItem.LastWriteTime
            }
        }

        $reportItem = Get-Item -LiteralPath $ReportPath -ErrorAction SilentlyContinue
        if ($reportItem -and $reportItem.LastWriteTime -ge $StartedAt) {
            return [pscustomobject]@{
                Kind      = 'report'
                Path      = $ReportPath
                Timestamp = $reportItem.LastWriteTime
            }
        }

        Start-Sleep -Seconds 1
    }

    return $null
}

$blockedPatterns = @(
    '(?:^|\s)-p(?:\s|$)',
    '(?:^|\s)--print(?:\s|$)',
    '(?:^|\s)--output-format(?:\s|$)',
    'stream-json',
    'include-partial-messages',
    'include-hook-events'
)

foreach ($pattern in $blockedPatterns) {
    if ($AideCommand -match $pattern) {
        throw "AideCommand switches back to a hidden/background mode. Use a visible TUI command instead: $AideCommand"
    }
}

$AideCommand = Resolve-AideCommand -CommandLine $AideCommand

$resolvedRepoRoot = (Resolve-Path -LiteralPath $RepoRoot).Path
$resolvedPromptPath = (Resolve-Path -LiteralPath $PromptPath).Path
$promptText = Get-Content -Raw -LiteralPath $resolvedPromptPath

$delegateRoot = Join-Path $resolvedRepoRoot '.codex_delegate'
$logsDir = Join-Path $delegateRoot 'logs'
New-Item -ItemType Directory -Force $logsDir | Out-Null
$statePath = Join-Path $delegateRoot "state\$TaskId.json"
$reportPath = Join-Path $delegateRoot "reports\$TaskId.md"
$preExistingClaudeProcesses = @(Get-Process -Name claude -ErrorAction SilentlyContinue)
$preExistingAideWindows = @(Get-ExistingAideWindows)

if (-not $AllowParallelVisibleSessions -and $preExistingAideWindows.Count -gt 0) {
    $titles = $preExistingAideWindows | Select-Object -ExpandProperty MainWindowTitle
    throw ("Another visible AI aide session is already open: " + ($titles -join '; ') + ". Close it first or relaunch with -AllowParallelVisibleSessions.")
}

$bootstrapPath = Join-Path $logsDir "$TaskId-visible-launch.ps1"
$repoLiteral = Quote-Single $resolvedRepoRoot
$promptLiteral = Quote-Single $resolvedPromptPath
$commandLiteral = Quote-Single $AideCommand
$taskLiteral = Quote-Single $TaskId
$launchInstruction = "Read the task file at $resolvedPromptPath from disk and follow it exactly. Reply in Chinese."
$launchInstructionEscaped = $launchInstruction.Replace('"', '\"')

$bootstrap = @"
Set-Location -LiteralPath '$repoLiteral'
try { [Console]::OutputEncoding = [System.Text.Encoding]::UTF8 } catch {}
try { `$Host.UI.RawUI.WindowTitle = 'AI Aide - $taskLiteral' } catch {}
Write-Host '[AI Aide] Prompt file: $promptLiteral' -ForegroundColor Cyan
Write-Host '[AI Aide] Claude will auto-start from the on-disk task file without global paste keystrokes.' -ForegroundColor Cyan
`$commandWithPrompt = '& ' + '$commandLiteral' + ' "' + '$launchInstructionEscaped' + '"'
Invoke-Expression `$commandWithPrompt
"@

Set-Content -LiteralPath $bootstrapPath -Value $bootstrap -Encoding UTF8

$launchOrder = if ($Terminal -eq 'auto') {
    @('powershell', 'pwsh', 'wt')
} else {
    @($Terminal)
}

$launchSpec = $null
$launchSpecs = @()
foreach ($candidate in $launchOrder) {
    $candidateSpec = New-LaunchSpec -Candidate $candidate -WorkingDirectory $resolvedRepoRoot -BootstrapPath $bootstrapPath
    if ($candidateSpec) {
        $launchSpecs += $candidateSpec
    }
}

if (-not $launchSpecs) {
    throw 'Could not find a visible terminal launcher. Expected wt.exe, pwsh.exe, or powershell.exe.'
}

$clipboardCopied = $false
if (-not $NoClipboard) {
    try {
        Set-Clipboard -Value $promptText
        $clipboardCopied = $true
    } catch {
        $clipboardCopied = $false
    }
}

$launchInfo = [pscustomobject]@{
    mode            = 'visible-terminal'
    terminal        = $null
    repoRoot        = $resolvedRepoRoot
    promptPath      = $resolvedPromptPath
    bootstrapPath   = $bootstrapPath
    launchInstruction = $launchInstruction
    aideCommand     = $AideCommand
    statePath       = $statePath
    reportPath      = $reportPath
    preExistingClaudeProcessIds = @($preExistingClaudeProcesses | Select-Object -ExpandProperty Id)
    preExistingAideWindowTitles = @($preExistingAideWindows | Select-Object -ExpandProperty MainWindowTitle)
    clipboardCopied = $clipboardCopied
    launchProgram   = $null
    launchArguments = $null
    launchedProcessId = $null
    automaticTaskStartMode = 'cli-prompt-argument'
    autoSubmitAttempted = $true
    autoSubmitSucceeded = $false
    autoSubmitEnabled   = [bool]$AllowAutoSubmit
    autoSubmitSkippedReason = $null
    targetWindowTitle   = $null
    launchAttempts      = @()
    verificationSignalKind = $null
    verificationSignalPath = $null
    verificationSignalTime = $null
    manualConfirmationRequired = $false
}

$launchLogPath = Join-Path $logsDir "$TaskId-launch.json"
$launchedProcess = $null
$launchSpec = $launchSpecs | Select-Object -First 1
$fatalLaunchError = $null

try {
    if (-not $DryRun) {
        $attemptStartedAt = Get-Date
        $attempt = [ordered]@{
            terminal = $launchSpec.Terminal
            launchProgram = $launchSpec.FilePath
            launchArguments = $launchSpec.Arguments
            startedAt = $attemptStartedAt
            launchedProcessId = $null
            targetWindowTitle = $null
            claudeProcessCount = 0
            verificationSignal = $null
            result = 'unknown'
        }

        $launchedProcess = Start-Process -FilePath $launchSpec.FilePath -ArgumentList $launchSpec.Arguments -PassThru
        if ($launchedProcess) {
            $attempt.launchedProcessId = $launchedProcess.Id
        }

        $launchInfo.terminal = $launchSpec.Terminal
        $launchInfo.launchProgram = $launchSpec.FilePath
        $launchInfo.launchArguments = $launchSpec.Arguments
        $launchInfo.launchedProcessId = $attempt.launchedProcessId

        Start-Sleep -Seconds $InitialLaunchProbeSeconds

        $targetWindow = Get-TargetWindow -PreferredTerminal $launchSpec.Terminal -PreferredProcessId $launchedProcess.Id
        if ($targetWindow) {
            $attempt.targetWindowTitle = $targetWindow.MainWindowTitle
            $launchInfo.targetWindowTitle = $attempt.targetWindowTitle
        }

        $claudeProcesses = @(Get-ClaudeProcessesStartedAfter -StartedAfter $attemptStartedAt)
        $attempt.claudeProcessCount = $claudeProcesses.Count

        if (($launchedProcess -and $launchedProcess.HasExited) -or $claudeProcesses.Count -eq 0) {
            $attempt.result = 'launch-missing-claude-process'
            $launchInfo.launchAttempts += [pscustomobject]$attempt
            $fatalLaunchError = 'Visible terminal launched, but Claude Code did not appear to start. No claude process or task signal was observed.'
        }
        else {
            $taskSignal = Wait-ForTaskSignal -StatePath $statePath -ReportPath $reportPath -StartedAt $attemptStartedAt -TimeoutSeconds $TaskSignalTimeoutSeconds
            if ($taskSignal) {
                $attempt.verificationSignal = $taskSignal
                $attempt.result = 'verified'
                $launchInfo.launchAttempts += [pscustomobject]$attempt
                $launchInfo.autoSubmitSucceeded = $true
                $launchInfo.verificationSignalKind = $taskSignal.Kind
                $launchInfo.verificationSignalPath = $taskSignal.Path
                $launchInfo.verificationSignalTime = $taskSignal.Timestamp
                if ($AllowAutoSubmit) {
                    $launchInfo.autoSubmitSkippedReason = 'replaced-by-cli-prompt-argument'
                }
                else {
                    $launchInfo.autoSubmitSkippedReason = 'not-needed-when-cli-prompt-argument-works'
                }
            }
            else {
                $attempt.result = 'launched-but-unverified'
                $launchInfo.launchAttempts += [pscustomobject]$attempt
                $launchInfo.manualConfirmationRequired = $true
                $launchInfo.autoSubmitSkippedReason = 'no-task-signal-observed'
            }
        }
    }
    else {
        $launchInfo.terminal = $launchSpec.Terminal
        $launchInfo.launchProgram = $launchSpec.FilePath
        $launchInfo.launchArguments = $launchSpec.Arguments
    }
}
finally {
    $launchInfo | ConvertTo-Json -Depth 6 | Set-Content -LiteralPath $launchLogPath -Encoding UTF8
}

if ($fatalLaunchError) {
    throw $fatalLaunchError
}

$launchInfo
