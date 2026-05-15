# Agent Notes

This repository contains a SwiftPM macOS app named `CrontabManager`.

## Core Invariants

- The current user's `crontab -l` output is the source of truth for jobs.
- Do not add sidecar job databases, preferences, caches, or metadata files for job state.
- Read log files directly for status context. Log-derived status may be approximate.
- Enable/disable should comment or uncomment the cron line, preserving the rest of the line.
- Do not hardcode the user's job names, paths, or command formats. Derive labels from parsed commands.
- "Run Now" should launch the job command in Terminal after stripping cron log redirection.
- Opening a log file should use normal macOS external opening, not Terminal or `less`.

## Project Layout

- `Sources/CrontabManager/App`: app entry point and app delegate.
- `Sources/CrontabManager/Views`: SwiftUI surfaces.
- `Sources/CrontabManager/Models`: parsed crontab/job/status models.
- `Sources/CrontabManager/Stores`: app state and async operations.
- `Sources/CrontabManager/Services`: crontab, shell, log file, and log analysis services.
- `Sources/CrontabManager/Support`: parsing, formatting, command redirection, and Terminal helpers.
- `Tests/CrontabManagerTests`: focused parser/service tests.
- `script/build_and_run.sh`: builds, stages, and launches the app bundle.

## Build And Verification

Use these from the repository root:

```sh
swift test
./script/build_and_run.sh --verify
```

For normal local launch:

```sh
./script/build_and_run.sh
```

Useful script modes:

```sh
./script/build_and_run.sh --logs
./script/build_and_run.sh --telemetry
./script/build_and_run.sh --debug
```

## Implementation Guidance

- Prefer the existing parsing helpers over ad hoc string edits:
  - `CrontabDocument`
  - `CronJob`
  - `CronSchedule`
  - `CommandRedirection`
  - `JobTitleFormatter`
- Keep mutations flowing through `CrontabDocument.renderedContent()` and `CrontabService.install(_:)`.
- Preserve environment assignments, comments, blank lines, and unsupported lines when rendering crontab content.
- Keep log analysis non-blocking from the UI. Slow file reads belong off the main actor.
- Add or update tests when changing cron parsing, command redirection, job titles, log analysis, or document rendering.
- The app is macOS-only SwiftUI/AppKit interop. Prefer SwiftUI first, with small AppKit bridges only for window or platform behavior SwiftUI cannot express cleanly.

## Safety Notes

- Be careful with `crontab` commands. Loading uses `crontab -l`; installing uses `crontab -` with the rendered document.
- Do not run destructive git commands or reset user changes.
- If a change affects live crontab editing behavior, verify with tests before launching the app.
