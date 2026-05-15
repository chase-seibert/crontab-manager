import AppKit
import SwiftUI

struct JobDetailView: View {
    @ObservedObject var store: CrontabStore
    var job: CronJob
    @State private var isConfirmingDelete = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                header
                jobSummary
                statusPanel
                manualRunPanel
                deletePanel
            }
            .padding(20)
            .frame(maxWidth: 920, alignment: .leading)
        }
        .navigationTitle(job.title)
        .confirmationDialog(
            "Delete this job?",
            isPresented: $isConfirmingDelete,
            titleVisibility: .visible
        ) {
            Button("Delete Job", role: .destructive) {
                Task { await store.removeJob(jobID: job.id) }
            }

            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This will remove \(job.title) from your crontab.")
        }
    }

    private var header: some View {
        HStack(alignment: .center) {
            VStack(alignment: .leading, spacing: 4) {
                Text(job.title)
                    .font(.largeTitle.weight(.semibold))
                    .lineLimit(1)

                Text(job.rawLine)
                    .font(.caption.monospaced())
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                    .textSelection(.enabled)
            }

            Spacer()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var jobSummary: some View {
        GroupBox("Job") {
            Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 12) {
                GridRow {
                    Text("Schedule")
                        .foregroundStyle(.secondary)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(job.scheduleDescription)
                        Text(job.scheduleExpression)
                            .font(.caption.monospaced())
                            .foregroundStyle(.secondary)
                    }
                }

                GridRow {
                    Text("Enabled")
                        .foregroundStyle(.secondary)

                    Toggle("Enabled", isOn: enabledBinding)
                        .toggleStyle(.switch)
                        .labelsHidden()
                }

                GridRow {
                    Text("Command")
                        .foregroundStyle(.secondary)

                    HStack(alignment: .top, spacing: 8) {
                        Text(commandText)
                            .font(.system(.body, design: .monospaced))
                            .textSelection(.enabled)
                            .lineLimit(4)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(8)
                            .background(.quaternary, in: RoundedRectangle(cornerRadius: 6))

                        Button {
                            copyCommand()
                        } label: {
                            Label("Copy Command", systemImage: "doc.on.doc")
                        }
                        .labelStyle(.iconOnly)
                        .help("Copy command")
                    }
                }

                GridRow {
                    Text("Log Files")
                        .foregroundStyle(.secondary)

                    LogFilesInlineView(logPaths: job.logPaths) {
                        Task { await store.refresh() }
                    }
                }
            }
            .padding(.vertical, 4)
        }
    }

    private var statusPanel: some View {
        let status = store.statuses[job.id]
        let isLoading = store.statusLoadingJobIDs.contains(job.id)

        return GroupBox("Status") {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 12) {
                    if isLoading, status == nil {
                        HStack(spacing: 8) {
                            ProgressView()
                                .controlSize(.small)
                            Text("Checking log files")
                                .foregroundStyle(.secondary)
                        }
                    } else {
                        Label(lastSuccessText(status), systemImage: "clock")
                    }

                    Spacer()

                    if isLoading, status != nil {
                        HStack(spacing: 6) {
                            ProgressView()
                                .controlSize(.small)
                            Text("Refreshing")
                                .foregroundStyle(.secondary)
                        }
                    } else {
                        Label(errorSummary(status), systemImage: status?.hasRecentError == true ? "exclamationmark.triangle.fill" : "checkmark.seal")
                            .foregroundStyle(status?.hasRecentError == true ? .red : .secondary)
                    }
                }

                if let excerpt = status?.recentErrorExcerpt {
                    Divider()
                    VStack(alignment: .leading, spacing: 4) {
                        Text(excerpt.text)
                            .font(.caption.monospaced())
                            .textSelection(.enabled)
                            .lineLimit(24)

                        Text("\(excerpt.filePath), line \(excerpt.startLineNumber)")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }
            }
            .padding(.vertical, 4)
        }
    }

    private var manualRunPanel: some View {
        GroupBox("Manual Run") {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Spacer()

                    Button {
                        Task { await store.runNow(jobID: job.id) }
                    } label: {
                        Label("Run Now", systemImage: "play.fill")
                    }
                    .disabled(store.runningJobIDs.contains(job.id))
                }

                manualRunContent
            }
            .padding(.vertical, 4)
        }
    }

    @ViewBuilder
    private var manualRunContent: some View {
        if store.runningJobIDs.contains(job.id) {
            HStack {
                ProgressView()
                Text("Running")
            }
        } else if let result = store.runResults[job.id] {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Label("Opened in Terminal", systemImage: "terminal")
                        .foregroundStyle(.green)
                    Spacer()
                    Text("Manual run")
                        .foregroundStyle(.secondary)
                }

                Text("Launched \(DisplayFormatters.dateTime.string(from: result.launchedAt)) without cron log redirection")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                OutputSnippet(title: "terminal command", text: result.command)
            }
        } else {
            Text("No manual run this session")
                .foregroundStyle(.secondary)
        }
    }

    private var deletePanel: some View {
        HStack {
            Spacer()

            Button {
                isConfirmingDelete = true
            } label: {
                Label("Delete Job", systemImage: "trash")
                    .foregroundStyle(.red)
            }
            .buttonStyle(.bordered)

            Spacer()
        }
        .padding(.top, 4)
    }

    private var commandText: String {
        CommandRedirection.parse(job.command)
            .baseCommand
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func copyCommand() {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(commandText, forType: .string)
    }

    private var enabledBinding: Binding<Bool> {
        Binding(
            get: { job.isEnabled },
            set: { enabled in
                Task { await store.setEnabled(jobID: job.id, enabled: enabled) }
            }
        )
    }

    private func lastSuccessText(_ status: JobStatus?) -> String {
        guard let date = status?.lastSuccessfulRun else { return "Last success unavailable" }
        return "Last success \(DisplayFormatters.dateTime.string(from: date))"
    }

    private func errorSummary(_ status: JobStatus?) -> String {
        guard let status else { return "Status pending" }
        return status.hasRecentError ? "Recent error" : "No recent errors"
    }
}

private struct OutputSnippet: View {
    var title: String
    var text: String

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            Text(text)
                .font(.caption.monospaced())
                .textSelection(.enabled)
                .lineLimit(8)
                .padding(8)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(.quaternary, in: RoundedRectangle(cornerRadius: 6))
        }
    }
}
