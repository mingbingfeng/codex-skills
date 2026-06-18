---
name: computer-use-repair
description: Repair Codex App Windows Computer Use after app updates reset bundled marketplace or plugin configuration, especially errors like "native pipe path is unavailable", "Windows Computer Use helper paths are unavailable", or missing computer-use skills/tools.
---

# Computer Use Repair

Use this skill when Windows Computer Use stops working after a Codex App update, or when logs mention:

- `native pipe path is unavailable`
- `Windows Computer Use helper paths are unavailable`
- `computer-use native pipe startup failed`
- `reason=missing-helper-path`

## Workflow

1. Run the bundled repair script:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "$env:USERPROFILE\.codex\skills\computer-use-repair\scripts\repair-computer-use.ps1"
```

2. If the user wants the repair to survive future Codex App updates, install the per-user self-healing scheduled task:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "$env:USERPROFILE\.codex\skills\computer-use-repair\scripts\repair-computer-use.ps1" -InstallScheduledTask
```

This does not patch the signed Codex App package. It first tries to register a user-level `CodexComputerUseRepair` scheduled task that reruns the idempotent repair script at logon. If Windows denies Task Scheduler access, it falls back to a Startup-folder shortcut with the same command.

3. Verify the current desktop logs:

```powershell
$logDir = "$env:LOCALAPPDATA\Packages\OpenAI.Codex_2p2nqsd0c76g0\LocalCache\Local\Codex\Logs"
Get-ChildItem -LiteralPath $logDir -Recurse -File -Filter "*.log" |
  Sort-Object LastWriteTime -Descending |
  Select-Object -First 4 |
  ForEach-Object {
    "FILE=$($_.FullName)"
    rg -n "computer-use-native-pipe|missing-helper-path|native pipe startup ready|Windows Computer Use helper paths" $_.FullName
  }
```

4. If the current process already has a Computer Use pipe, test with the official client module from the stable local marketplace:

```js
if (!globalThis.sky) {
  const { setupComputerUseRuntime } = await import("file:///C:/Users/zjxqm/.codex/local-marketplaces/openai-bundled/plugins/computer-use/scripts/computer-use-client.mjs");
  await setupComputerUseRuntime({ globals: globalThis });
}
globalThis.apps = await sky.list_apps();
nodeRepl.write(JSON.stringify({ count: apps.length }, null, 2));
```

## What The Script Repairs

- Ensures `~\.codex\local-marketplaces\openai-bundled\plugins\computer-use` exists.
- Restores it from the plugin cache when possible.
- Points `[marketplaces.openai-bundled]` at the stable local marketplace.
- Ensures `[plugins."computer-use@openai-bundled"] enabled = true`.
- Copies the `computer-use` plugin into the `.tmp\bundled-marketplaces` mirror when that temporary marketplace exists but lacks the plugin.
- Backs up `config.toml` only when it needs to change.
- With `-InstallScheduledTask`, installs a per-user autostart repair entry to rerun the repair at logon. It prefers Task Scheduler and falls back to a Startup-folder shortcut when Task Scheduler is denied.
- With `-UninstallScheduledTask`, removes both supported autostart repair entries.

## Limits

This does not patch the installed Codex App package. App updates can replace signed package contents, so the durable fix is a user-level self-healing autostart entry rather than an app binary patch. If the helper executable itself is missing from both the local marketplace and plugin cache, reinstall or repair the bundled Computer Use plugin first.
