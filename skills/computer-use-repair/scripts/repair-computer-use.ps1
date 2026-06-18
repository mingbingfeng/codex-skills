param(
  [switch]$Quiet,
  [switch]$InstallScheduledTask,
  [switch]$UninstallScheduledTask,
  [string]$TaskName = 'CodexComputerUseRepair',
  [string]$CodexHome
)

$ErrorActionPreference = 'Stop'

function Write-RepairLog {
  param([string]$Message)
  if (-not $Quiet) {
    Write-Output $Message
  }
}

function Convert-ToTomlBasicString {
  param([string]$Value)
  '"' + ($Value -replace '\\', '\\' -replace '"', '\"') + '"'
}

function Find-ComputerUsePluginFromCache {
  param([string]$CodexHome)

  $cacheRoot = Join-Path $CodexHome 'plugins\cache\openai-bundled\computer-use'
  if (-not (Test-Path -LiteralPath $cacheRoot)) {
    return $null
  }

  $candidates = Get-ChildItem -LiteralPath $cacheRoot -Directory -ErrorAction SilentlyContinue |
    Sort-Object LastWriteTime -Descending

  foreach ($candidate in $candidates) {
    $client = Join-Path $candidate.FullName 'scripts\computer-use-client.mjs'
    $helper = Join-Path $candidate.FullName 'node_modules\@oai\sky\bin\windows\codex-computer-use.exe'
    if ((Test-Path -LiteralPath $client) -and (Test-Path -LiteralPath $helper)) {
      return $candidate.FullName
    }
  }

  return $null
}

function Ensure-Directory {
  param([string]$Path)
  if (-not (Test-Path -LiteralPath $Path)) {
    New-Item -ItemType Directory -Force -Path $Path | Out-Null
  }
}

function Ensure-StableMarketplace {
  param([string]$CodexHome)

  $stableRoot = Join-Path $CodexHome 'local-marketplaces\openai-bundled'
  $stablePlugin = Join-Path $stableRoot 'plugins\computer-use'
  $stableClient = Join-Path $stablePlugin 'scripts\computer-use-client.mjs'
  $stableHelper = Join-Path $stablePlugin 'node_modules\@oai\sky\bin\windows\codex-computer-use.exe'

  if ((Test-Path -LiteralPath $stableClient) -and (Test-Path -LiteralPath $stableHelper)) {
    return $stableRoot
  }

  $cachePlugin = Find-ComputerUsePluginFromCache -CodexHome $CodexHome
  if (-not $cachePlugin) {
    throw "Could not find a usable computer-use plugin in local marketplace or plugin cache."
  }

  Ensure-Directory -Path (Split-Path -Parent $stablePlugin)
  if (-not (Test-Path -LiteralPath $stablePlugin)) {
    Copy-Item -LiteralPath $cachePlugin -Destination $stablePlugin -Recurse -Force
    Write-RepairLog "Restored computer-use plugin from cache: $cachePlugin"
  }

  $agentsDir = Join-Path $stableRoot '.agents\plugins'
  Ensure-Directory -Path $agentsDir
  $marketplaceJson = Join-Path $agentsDir 'marketplace.json'
  if (-not (Test-Path -LiteralPath $marketplaceJson)) {
    @'
{
  "name": "openai-bundled",
  "interface": {
    "displayName": "OpenAI Bundled"
  },
  "plugins": [
    {
      "name": "computer-use",
      "source": {
        "source": "local",
        "path": "./plugins/computer-use"
      },
      "policy": {
        "installation": "INSTALLED_BY_DEFAULT",
        "authentication": "ON_USE"
      },
      "category": "Productivity"
    }
  ]
}
'@ | Set-Content -LiteralPath $marketplaceJson -Encoding UTF8
  }

  if (-not ((Test-Path -LiteralPath $stableClient) -and (Test-Path -LiteralPath $stableHelper))) {
    throw "Stable computer-use plugin still lacks required files after restore."
  }

  return $stableRoot
}

function Ensure-TempMarketplaceMirror {
  param(
    [string]$CodexHome,
    [string]$StableRoot
  )

  $tmpRoot = Join-Path $CodexHome '.tmp\bundled-marketplaces\openai-bundled'
  $tmpPlugin = Join-Path $tmpRoot 'plugins\computer-use'
  $stablePlugin = Join-Path $StableRoot 'plugins\computer-use'

  Ensure-Directory -Path (Join-Path $tmpRoot 'plugins')
  if (-not (Test-Path -LiteralPath $tmpPlugin)) {
    Copy-Item -LiteralPath $stablePlugin -Destination $tmpPlugin -Recurse -Force
    Write-RepairLog "Copied computer-use plugin into temporary marketplace mirror."
  }

  $stableAgents = Join-Path $StableRoot '.agents'
  $tmpAgents = Join-Path $tmpRoot '.agents'
  if ((Test-Path -LiteralPath $stableAgents) -and (-not (Test-Path -LiteralPath $tmpAgents))) {
    Copy-Item -LiteralPath $stableAgents -Destination $tmpAgents -Recurse -Force
    Write-RepairLog "Copied marketplace metadata into temporary marketplace mirror."
  }
}

function Set-TomlKeyInSection {
  param(
    [string[]]$Lines,
    [string]$Section,
    [string]$Key,
    [string]$Value
  )

  $sectionHeader = "[$Section]"
  $start = -1
  for ($i = 0; $i -lt $Lines.Count; $i++) {
    if ($Lines[$i].Trim() -eq $sectionHeader) {
      $start = $i
      break
    }
  }

  if ($start -lt 0) {
    $newLines = New-Object System.Collections.Generic.List[string]
    $newLines.AddRange([string[]]$Lines)
    if ($newLines.Count -gt 0 -and $newLines[$newLines.Count - 1].Trim() -ne '') {
      $newLines.Add('')
    }
    $newLines.Add($sectionHeader)
    $newLines.Add("$Key = $Value")
    return ,$newLines.ToArray()
  }

  $end = $Lines.Count
  for ($i = $start + 1; $i -lt $Lines.Count; $i++) {
    if ($Lines[$i] -match '^\s*\[') {
      $end = $i
      break
    }
  }

  for ($i = $start + 1; $i -lt $end; $i++) {
    if ($Lines[$i] -match "^\s*$([regex]::Escape($Key))\s*=") {
      if ($Lines[$i] -eq "$Key = $Value") {
        return ,$Lines
      }
      $updated = [string[]]$Lines.Clone()
      $updated[$i] = "$Key = $Value"
      return ,$updated
    }
  }

  $list = New-Object System.Collections.Generic.List[string]
  for ($i = 0; $i -lt $Lines.Count; $i++) {
    if ($i -eq $end) {
      $list.Add("$Key = $Value")
    }
    $list.Add($Lines[$i])
  }
  if ($end -eq $Lines.Count) {
    $list.Add("$Key = $Value")
  }
  return ,$list.ToArray()
}

function Set-TopLevelNotifyIfMissingHelper {
  param(
    [string[]]$Lines,
    [string]$HelperPath
  )

  $notifyIndex = -1
  $currentHelper = $null
  for ($i = 0; $i -lt $Lines.Count; $i++) {
    if ($Lines[$i] -match '^\s*\[') {
      break
    }
    if ($Lines[$i] -match '^\s*notify\s*=\s*\[\s*"([^"]+)"') {
      $notifyIndex = $i
      $currentHelper = $Matches[1]
      break
    }
  }

  if ($notifyIndex -ge 0 -and $currentHelper -and (Test-Path -LiteralPath $currentHelper)) {
    return ,$Lines
  }

  if (-not (Test-Path -LiteralPath $HelperPath)) {
    return ,$Lines
  }

  $value = '[ ' + (Convert-ToTomlBasicString $HelperPath) + ', "turn-ended" ]'
  if ($notifyIndex -ge 0) {
    $updated = [string[]]$Lines.Clone()
    $updated[$notifyIndex] = "notify = $value"
    return ,$updated
  }

  $list = New-Object System.Collections.Generic.List[string]
  $inserted = $false
  for ($i = 0; $i -lt $Lines.Count; $i++) {
    if (-not $inserted -and $Lines[$i] -match '^\s*\[') {
      $list.Add("notify = $value")
      $inserted = $true
    }
    $list.Add($Lines[$i])
  }
  if (-not $inserted) {
    $list.Add("notify = $value")
  }
  return ,$list.ToArray()
}

function Repair-Config {
  param(
    [string]$CodexHome,
    [string]$StableRoot
  )

  $configPath = Join-Path $CodexHome 'config.toml'
  if (-not (Test-Path -LiteralPath $configPath)) {
    throw "Missing config.toml at $configPath"
  }

  $original = Get-Content -LiteralPath $configPath -Raw
  $lines = $original -split "`r?`n", -1
  if ($lines.Count -gt 0 -and $lines[$lines.Count - 1] -eq '') {
    $lines = $lines[0..($lines.Count - 2)]
  }

  $stableSource = '\\?\' + $StableRoot
  $lines = Set-TomlKeyInSection -Lines $lines -Section 'marketplaces.openai-bundled' -Key 'source_type' -Value '"local"'
  $lines = Set-TomlKeyInSection -Lines $lines -Section 'marketplaces.openai-bundled' -Key 'source' -Value (Convert-ToTomlBasicString $stableSource)
  $lines = Set-TomlKeyInSection -Lines $lines -Section 'plugins."computer-use@openai-bundled"' -Key 'enabled' -Value 'true'

  $stableHelper = Join-Path $StableRoot 'plugins\computer-use\node_modules\@oai\sky\bin\windows\codex-computer-use.exe'
  $lines = Set-TopLevelNotifyIfMissingHelper -Lines $lines -HelperPath $stableHelper

  $updated = ($lines -join [Environment]::NewLine) + [Environment]::NewLine
  if ($updated -ne $original) {
    $backupDir = Join-Path $CodexHome 'backups'
    Ensure-Directory -Path $backupDir
    $stamp = Get-Date -Format 'yyyyMMdd-HHmmss'
    $backupPath = Join-Path $backupDir "config.toml.$stamp.computer-use-repair.bak"
    Copy-Item -LiteralPath $configPath -Destination $backupPath -Force
    Set-Content -LiteralPath $configPath -Value $updated -Encoding UTF8
    Write-RepairLog "Updated config.toml. Backup: $backupPath"
  } else {
    Write-RepairLog "config.toml already contains the required Computer Use settings."
  }
}

function Quote-TaskArgument {
  param([string]$Value)
  '"' + ($Value -replace '"', '\"') + '"'
}

function Install-RepairScheduledTask {
  param(
    [string]$Name,
    [string]$ScriptPath,
    [string]$CodexHome
  )

  if (-not $ScriptPath) {
    throw 'Cannot install scheduled task because the repair script path is unavailable.'
  }

  $powershell = (Get-Command powershell.exe -ErrorAction Stop).Source
  $arguments = @(
    '-NoProfile',
    '-ExecutionPolicy Bypass',
    '-WindowStyle Hidden',
    '-File ' + (Quote-TaskArgument $ScriptPath),
    '-Quiet',
    '-CodexHome ' + (Quote-TaskArgument $CodexHome)
  ) -join ' '

  $action = New-ScheduledTaskAction -Execute $powershell -Argument $arguments
  $trigger = New-ScheduledTaskTrigger -AtLogOn
  $settings = New-ScheduledTaskSettingsSet `
    -ExecutionTimeLimit (New-TimeSpan -Minutes 5) `
    -MultipleInstances IgnoreNew `
    -StartWhenAvailable

  Register-ScheduledTask `
    -TaskName $Name `
    -Action $action `
    -Trigger $trigger `
    -Settings $settings `
    -Description 'Repairs Codex App Computer Use plugin configuration after app updates reset it.' `
    -Force | Out-Null

  Write-RepairLog "Installed scheduled task: $Name"
}

function Get-RepairStartupShortcutPath {
  param([string]$Name)

  $startup = [Environment]::GetFolderPath('Startup')
  if (-not $startup) {
    $startup = Join-Path $env:APPDATA 'Microsoft\Windows\Start Menu\Programs\Startup'
  }

  Ensure-Directory -Path $startup
  return Join-Path $startup "$Name.lnk"
}

function Install-RepairStartupShortcut {
  param(
    [string]$Name,
    [string]$ScriptPath,
    [string]$CodexHome
  )

  if (-not $ScriptPath) {
    throw 'Cannot install startup shortcut because the repair script path is unavailable.'
  }

  $powershell = (Get-Command powershell.exe -ErrorAction Stop).Source
  $arguments = @(
    '-NoProfile',
    '-ExecutionPolicy Bypass',
    '-WindowStyle Hidden',
    '-File ' + (Quote-TaskArgument $ScriptPath),
    '-Quiet',
    '-CodexHome ' + (Quote-TaskArgument $CodexHome)
  ) -join ' '

  $shortcutPath = Get-RepairStartupShortcutPath -Name $Name
  $shell = New-Object -ComObject WScript.Shell
  $shortcut = $shell.CreateShortcut($shortcutPath)
  $shortcut.TargetPath = $powershell
  $shortcut.Arguments = $arguments
  $shortcut.WorkingDirectory = Split-Path -Parent $ScriptPath
  $shortcut.WindowStyle = 7
  $shortcut.Description = 'Repairs Codex App Computer Use plugin configuration after app updates reset it.'
  $shortcut.Save()

  Write-RepairLog "Installed startup shortcut: $shortcutPath"
}

function Install-RepairAutostart {
  param(
    [string]$Name,
    [string]$ScriptPath,
    [string]$CodexHome
  )

  try {
    Install-RepairScheduledTask -Name $Name -ScriptPath $ScriptPath -CodexHome $CodexHome
  } catch {
    Write-RepairLog "Could not install scheduled task; installing startup shortcut instead. Reason: $($_.Exception.Message)"
    Install-RepairStartupShortcut -Name $Name -ScriptPath $ScriptPath -CodexHome $CodexHome
  }
}

function Uninstall-RepairStartupShortcut {
  param([string]$Name)

  $shortcutPath = Get-RepairStartupShortcutPath -Name $Name
  if (Test-Path -LiteralPath $shortcutPath) {
    Remove-Item -LiteralPath $shortcutPath -Force
    Write-RepairLog "Removed startup shortcut: $shortcutPath"
  } else {
    Write-RepairLog "Startup shortcut is not installed: $shortcutPath"
  }
}

function Uninstall-RepairScheduledTask {
  param([string]$Name)

  $task = $null
  try {
    $task = Get-ScheduledTask -TaskName $Name -ErrorAction SilentlyContinue
  } catch {
    Write-RepairLog "Could not query scheduled task: $($_.Exception.Message)"
  }

  if ($task) {
    try {
      Unregister-ScheduledTask -TaskName $Name -Confirm:$false
      Write-RepairLog "Uninstalled scheduled task: $Name"
    } catch {
      Write-RepairLog "Could not uninstall scheduled task: $($_.Exception.Message)"
    }
  } else {
    Write-RepairLog "Scheduled task is not installed: $Name"
  }
}

$codexHome = if ($CodexHome) { $CodexHome } elseif ($env:CODEX_HOME) { $env:CODEX_HOME } else { Join-Path $env:USERPROFILE '.codex' }
$codexHome = [System.IO.Path]::GetFullPath($codexHome)

if ($UninstallScheduledTask) {
  Uninstall-RepairScheduledTask -Name $TaskName
  Uninstall-RepairStartupShortcut -Name $TaskName
  if (-not $InstallScheduledTask) {
    return
  }
}

$stableRoot = Ensure-StableMarketplace -CodexHome $codexHome
Ensure-TempMarketplaceMirror -CodexHome $codexHome -StableRoot $stableRoot
Repair-Config -CodexHome $codexHome -StableRoot $stableRoot

if ($InstallScheduledTask) {
  Install-RepairAutostart -Name $TaskName -ScriptPath $PSCommandPath -CodexHome $codexHome
}

$client = Join-Path $stableRoot 'plugins\computer-use\scripts\computer-use-client.mjs'
$helper = Join-Path $stableRoot 'plugins\computer-use\node_modules\@oai\sky\bin\windows\codex-computer-use.exe'
Write-RepairLog "Computer Use repair complete."
Write-RepairLog "Client: $client"
Write-RepairLog "Helper: $helper"
