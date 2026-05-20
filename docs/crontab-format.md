# Crontab Format And Parser Expectations

This document describes the crontab shapes that `CrontabManager` should parse for display, manual runs, and log-file status. The current user's `crontab -l` output remains the source of truth; this app does not keep a sidecar job database.

## Line Kinds

- Blank lines are preserved as blank lines.
- Whole-line comments are preserved as comments.
- Environment assignments such as `SHELL=/bin/zsh`, `PATH=...`, `MAILTO=...`, and `CRON_TZ=...` are preserved as environment lines.
- User crontab jobs are parsed as either a five-field cron schedule plus command or a supported nickname schedule plus command.
- Disabled jobs are parsed when the line is a commented cron job, for example `# 0 * * * * /usr/bin/true`.
- Unsupported lines should be preserved without being treated as editable jobs.

System crontab lines that include a user field after the schedule, such as `0 2 * * * root /usr/local/bin/job`, are not part of the app's primary source of truth. They are useful as parser-gap examples because they are common in `/etc/crontab` and `/etc/cron.d`.

## Schedules

Supported job schedules include:

- Standard five-field schedules: `* * * * *`, `*/15 * * * *`, `0 9 * * 1-5`.
- Lists, ranges, and steps inside fields: `5,35 * * * *`, `0 8-18/2 * * 1-5`.
- Named months and weekdays where cron accepts them: `0 12 * JAN,MAR,SEP MON-FRI`.
- Nicknames: `@reboot`, `@hourly`, `@daily`, `@midnight`, `@weekly`, `@monthly`, `@yearly`, and `@annually`.

The parser should keep the raw schedule expression for editing and use best-effort human descriptions for common schedules.

## Job Names

Job names are derived from the command, not from stored metadata.

The intended name should be the most useful stable label for the work being run:

- Prefer script filenames for interpreter jobs: `python3 /opt/example/jobs/import.py daily` becomes `import.py daily`.
- Prefer project names for `cd ... && make ...` jobs: `cd /srv/example/site && make run` becomes `site`.
- Include meaningful positional arguments when they identify the job: `/opt/example/bin/sync tenant-a` becomes `sync tenant-a`.
- Ignore setup commands such as `source`, `.`, `export`, and `set` when a later command performs the actual job.
- Unwrap simple shell inline commands such as `bash -lc '/opt/example/bin/report daily'`.
- Unwrap common cron launch wrappers when deriving a display name, while keeping the wrapper in the runnable command. Supported wrappers include `flock`, `timeout`, `nice`, `sudo`, `run-one`, `chronic`, `cronic`, `lockrun`, `daemonize`, `envdir`, `s6-setuidgid`, `docker exec`, `docker compose run`, and `kubectl exec`.
- Strip cron log redirection before deriving the name.

Known useful future improvements include interpreting full shell control flow, remote command wrappers, dynamic log path variables, and process substitution.

## Commands

The displayed command and the command used by "Run Now" should be the job command after cron log redirection is removed.

Examples:

```cron
0 * * * * /opt/example/bin/sync tenant-a >> /var/log/example/sync.log 2>&1
```

Expected command:

```sh
/opt/example/bin/sync tenant-a
```

```cron
0 * * * * (cd /srv/example/site && make refresh) >> /var/log/example/site.log 2>&1
```

Expected command:

```sh
(cd /srv/example/site && make refresh)
```

Redirection embedded inside nested shell strings, such as `bash -lc 'exec >> /var/log/example/job.log 2>&1; run-job'`, is tracked as a parser gap.

## Log Files

Log files are extracted from shell redirection in the command. The app reads these files directly for status context.

Supported forms include:

- `> file`
- `>> file`
- `1> file`
- `1>> file`
- `2> file`
- `2>> file`
- `&> file`
- `&>> file`
- Attached forms such as `>>/var/log/example/job.log`
- Quoted paths such as `>> '/var/log/example/job output.log'`
- Combined stdout and stderr such as `>> file 2>&1`
- Split stdout and stderr such as `1>> out.log 2>> err.log`
- `tee` pipelines such as `command 2>&1 | tee -a file`, where the pipeline remains part of the runnable command and the `tee` target is added as a log file.

When stdout and stderr point at separate files, the expected order is stdout first, then stderr. When stderr is redirected to stdout, only the stdout file should appear once.

Known log extraction gaps include:

- Redirection inside quoted shell commands.
- Process substitution such as `> >(logger -t example)`.
- Syslog-only sinks such as `logger -t name`.
- Dynamic shell variables or command substitutions in log paths when the app would need to evaluate shell code to resolve the final file.
- Wrapper-specific log flags that are not shell redirection.

## Corpus Fixture

`Tests/CrontabManagerTests/Fixtures/generic-crontab-1000.cron` contains 1000 synthetic jobs. The examples are generated from generic cron patterns and generic paths such as `/opt/example`, `/srv/example`, `/var/log/example`, and `~/Library/Logs/example`. The current corpus keeps 900 strict passing examples and 100 tracked gaps.

Each row ends with test-only metadata:

```cron
0 * * * * /opt/example/bin/sync tenant-a >> /var/log/example/sync.log 2>&1 # EXPECT {"status":"✅","name":"sync tenant-a","command":"/opt/example/bin/sync tenant-a","logfiles":["/var/log/example/sync.log"]}
```

The `# EXPECT ...` suffix is not production crontab syntax for the app. The corpus test strips it before calling the parser.

Emoji status meanings:

- `✅`: the current parser is expected to produce the documented `name`, `command`, and `logfiles`.
- `❌`: the row documents an intended behavior that is currently a known parser gap. These rows stay in the fixture so improvements can flip them to `✅` when they start passing.

The tracked gap rows currently emphasize harder moderate parsing cases: nested shell scripts with internal redirection, process substitution, syslog pipes, shell control flow, remote commands, `find -exec` and `xargs` inner commands, background jobs, transient service wrappers, dynamic log variables, command substitution in log paths, and advanced file-descriptor choreography.

The corpus must remain generic. Do not add real user job names, private paths, local usernames, production hostnames, tokens, or organization-specific commands.
