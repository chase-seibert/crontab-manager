# Crontab Manager

A small macOS app for viewing and managing the current user's crontab.

The app intentionally treats `crontab -l` as the only source of truth for scheduled jobs. It does not maintain a separate job database. For run context and status, it reads the log files referenced by each cron command.

## Features

- List scheduled cron jobs for the current user.
- Show human-readable schedule descriptions alongside raw cron expressions.
- Enable or disable jobs by commenting or uncommenting their crontab line.
- Open and clear referenced log files.
- Surface recent log errors and last successful log writes in the list/detail views.
- Run a job manually in Terminal without cron log redirection.
- Copy the parsed command from the detail panel.
- Resize the window between list-only and list-plus-detail layouts.

## Requirements

- macOS 14 or newer.
- Swift toolchain compatible with SwiftPM and Swift 6 package manifests.
- Access to `/usr/bin/crontab`.

## Build, Test, And Run

From the repository root:

```sh
swift test
./script/build_and_run.sh --verify
```

Launch the app:

```sh
./script/build_and_run.sh
```

The run script builds the SwiftPM executable, stages `dist/CrontabManager.app`, copies the app icon if present, and opens the app bundle.

Additional modes:

```sh
./script/build_and_run.sh --logs
./script/build_and_run.sh --telemetry
./script/build_and_run.sh --debug
```

## How It Works

`CrontabService` loads jobs with:

```sh
crontab -l
```

When the app changes a job, `CrontabDocument` renders the full crontab back out and `CrontabService` installs it with:

```sh
crontab -
```

The parser preserves blank lines, comments, environment assignments, unsupported lines, and non-selected jobs. Disabled jobs are represented as commented cron lines that still parse as jobs.

Log state comes from redirection in the command, such as `>> path 2>&1`. The app reads log tails to infer recent errors and successful runs; it does not write a separate status file.

## Source Layout

- `Sources/CrontabManager/App`: app entry point.
- `Sources/CrontabManager/Views`: SwiftUI views.
- `Sources/CrontabManager/Models`: crontab, job, draft, and status models.
- `Sources/CrontabManager/Stores`: observable app state.
- `Sources/CrontabManager/Services`: crontab, shell, log, and file services.
- `Sources/CrontabManager/Support`: formatters and parsing helpers.
- `Tests/CrontabManagerTests`: parser and service tests.

## Notes

This app edits the current user's real crontab. Review changes carefully when working on parsing or rendering behavior.
