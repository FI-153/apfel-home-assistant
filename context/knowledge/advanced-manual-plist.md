# Advanced: Manual launchd plist

Escape hatch for setups that `brew services` can't express — complex flag combinations, multiple MCP servers, custom logging paths, or co-running several apfel instances on different ports.

Upstream reference: [`apfel/docs/background-service.md#manual-plist-advanced`](../../../apfel/docs/background-service.md).

## When to prefer this over `brew services`

- You need CLI flags not exposed via `APFEL_*` env vars.
- You're running two apfel instances on different ports.
- You want logs in a non-default location.
- You want to start apfel under a specific user that isn't the current shell user.

## Template

```bash
cat > ~/Library/LaunchAgents/com.arthurficial.apfel.plist << 'EOF'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN"
  "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>Label</key>
    <string>com.arthurficial.apfel</string>
    <key>ProgramArguments</key>
    <array>
        <string>/opt/homebrew/opt/apfel/bin/apfel</string>
        <string>--serve</string>
        <string>--port</string>
        <string>11434</string>
        <string>--mcp</string>
        <string>/absolute/path/to/server.py</string>
    </array>
    <key>RunAtLoad</key>
    <true/>
    <key>KeepAlive</key>
    <true/>
    <key>StandardOutPath</key>
    <string>/tmp/apfel.log</string>
    <key>StandardErrorPath</key>
    <string>/tmp/apfel.log</string>
    <key>EnvironmentVariables</key>
    <dict>
        <key>HOME</key>
        <string>/Users/YOUR_USERNAME</string>
        <key>APFEL_TOKEN</key>
        <string>YOUR_TOKEN</string>
    </dict>
</dict>
</plist>
EOF
```

## Lifecycle

```bash
# Load
launchctl bootstrap gui/$(id -u) ~/Library/LaunchAgents/com.arthurficial.apfel.plist

# Unload
launchctl bootout gui/$(id -u)/com.arthurficial.apfel

# Inspect
launchctl print gui/$(id -u)/com.arthurficial.apfel
```

## Gotchas

- **Use the `opt` path**, not the Cellar path. `/opt/homebrew/opt/apfel/bin/apfel` is a symlink that survives `brew upgrade`; the Cellar path bakes in a version number that breaks on upgrade.
- **On Intel Homebrew**, the prefix is `/usr/local/opt/apfel/bin/apfel` instead.
- **`HOME` must be set** in `EnvironmentVariables` — launchd doesn't inherit the shell user's environment.
- **Conflicts with `brew services`.** Don't run both; unload one before starting the other (`brew services stop apfel` before bootstrapping the manual plist).
- **Log rotation** isn't automatic. If you keep apfel running for months, rotate `/tmp/apfel.log` (or the path you chose) via `newsyslog.d` or a periodic script.

## When `apfel-home-assistant` might ship its own plist

If the Homebrew formula for `apfel-home-assistant` needs apfel configured with a specific MCP server bundled alongside (e.g. a Home-Assistant-API MCP bridge), generating a dedicated plist — rather than mutating apfel's own service — keeps the two installations independent. That decision is deferred until the architecture lands.
