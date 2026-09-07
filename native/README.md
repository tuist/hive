# Hive native applications

Hive's native applications connect shared product context to local and remote
execution:

- macOS hosts local projects, worktrees, and agent sessions. It reconciles
  those records with sessions stored by Hive.
- iPhone is a remote client. Its Work tab shows server-backed workspaces and
  running Macs discovered on the local network, while the other tabs retain
  Hive's Forage, specifications, drops, and account experience.
- Apple Watch is a remote companion for nearby Macs and server-backed sessions.
- Android continues to use the focused server client core and does not link the
  desktop execution core.

The Rust code is intentionally split between `mobile/shared`, which owns the
Hive server client used by the existing mobile applications, and `native/rust`,
which owns project operations, inference accounts, session reconciliation, and
the local agent runtime. Once targets select only the required core for each
platform.

Build and test the native applications with:

```sh
mise run mobile:test
mise run mobile:build:ios
mise run mobile:build:android
mise run mobile:build:watch
mise run native:build:macos
```
