import AppKit
import SwiftUI

struct JobDetailView: View {
    @ObservedObject var store: CrontabStore
    var job: CronJob
    @State private var isConfirmingDelete = false
    @State private var isErrorPreviewExpanded = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
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
                    .font(.title2.weight(.semibold))
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
            VStack(spacing: 0) {
                DetailRow("Schedule") {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(job.scheduleDescription)
                        Text(job.scheduleExpression)
                            .font(.caption.monospaced())
                            .foregroundStyle(.secondary)
                    }
                }

                DetailDivider()

                DetailRow("Enabled") {
                    Toggle("Enabled", isOn: enabledBinding)
                        .toggleStyle(.switch)
                        .labelsHidden()
                }

                DetailDivider()

                DetailRow("Command") {
                    commandRow
                }

                DetailDivider()

                DetailRow("Log Files") {
                    LogFilesInlineView(logPaths: job.logPaths, isEmbeddedInDetailRow: true) {
                        Task { await store.refresh() }
                    }
                }
            }
            .padding(.vertical, 2)
        }
    }

    private var commandRow: some View {
        HStack(alignment: .top, spacing: 8) {
            Text(commandText)
                .font(.system(.body, design: .monospaced))
                .textSelection(.enabled)
                .lineLimit(3)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(7)
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

    private var statusPanel: some View {
        let status = store.statuses[job.id]
        let isLoading = store.statusLoadingJobIDs.contains(job.id)

        return GroupBox("Status") {
            VStack(spacing: 0) {
                StatusLine(systemImage: "clock", title: lastSuccessText(status)) {
                    if isLoading {
                        ProgressView()
                            .controlSize(.small)
                    }
                }

                DetailDivider(leadingInset: 0)

                StatusLine(
                    systemImage: status?.hasRecentError == true ? "exclamationmark.triangle.fill" : "checkmark.seal",
                    title: errorSummary(status),
                    tint: status?.hasRecentError == true ? .red : .secondary
                ) {
                    if isLoading, status != nil {
                        ProgressView()
                            .controlSize(.small)
                    }
                }

                if let excerpt = status?.recentErrorExcerpt {
                    DetailDivider(leadingInset: 0)

                    DisclosureGroup(isExpanded: $isErrorPreviewExpanded) {
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
                        .padding(.top, 8)
                    } label: {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Error Preview")
                            Text(excerpt.text)
                                .font(.caption.monospaced())
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                                .truncationMode(.tail)
                        }
                    }
                    .padding(.vertical, 8)
                }
            }
            .padding(.vertical, 2)
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

private struct DetailRow<Content: View>: View {
    var title: String
    var content: Content

    init(_ title: String, @ViewBuilder content: () -> Content) {
        self.title = title
        self.content = content()
    }

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Text(title)
                .foregroundStyle(.secondary)
                .frame(width: 82, alignment: .leading)

            content
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.vertical, 8)
    }
}

private struct StatusLine<Trailing: View>: View {
    var systemImage: String
    var title: String
    var tint: Color
    var trailing: Trailing

    init(
        systemImage: String,
        title: String,
        tint: Color = .secondary,
        @ViewBuilder trailing: () -> Trailing
    ) {
        self.systemImage = systemImage
        self.title = title
        self.tint = tint
        self.trailing = trailing()
    }

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: systemImage)
                .foregroundStyle(tint)
                .frame(width: 16)

            Text(title)
                .lineLimit(1)

            Spacer()

            trailing
        }
        .padding(.vertical, 8)
    }
}

private struct DetailDivider: View {
    var leadingInset: CGFloat = 94

    var body: some View {
        Divider()
            .padding(.leading, leadingInset)
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
