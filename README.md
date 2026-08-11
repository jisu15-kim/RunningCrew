# RunningCrew

<img src="RunningCrew/Assets.xcassets/AppIcon.appiconset/icon_256.png" width="96" alt="RunningCrew icon" />

**A macOS menu bar app for managing GitHub self-hosted runners.**

Running multiple self-hosted runners on one Mac means juggling `svc.sh`, `launchctl`, and scattered log files. RunningCrew replaces all of that with a single menu bar app: it discovers the runners installed on your machine, runs them as managed processes, and shows you at a glance whether each one is online, idle, or busy with a job — so starting, stopping, and trusting your runners takes zero thought.

## Features

- **Auto-discovery** — finds runners from LaunchAgents, running processes, and your home directory
- **Direct process management** — graceful stops (waits for the running job if you want), auto-restart, orphan recovery
- **One-click migration** from `svc.sh` system services to app management
- **Live status from GitHub** — online/offline, busy, and the exact workflow currently running
- **Real-time logs** per runner, persisted across app restarts
- **Auto-updates** via Sparkle · English / Korean

## Install

```sh
brew install --cask jisu15-kim/tap/runningcrew
```

Or download the DMG from [Releases](https://github.com/jisu15-kim/RunningCrew/releases).

## Build

Open `RunningCrew.xcodeproj` with Xcode 26+ and run. Releases are built with `scripts/release.sh`.
