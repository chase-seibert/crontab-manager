import AppKit
import SwiftUI

struct JobDetailView: View {
    @ObservedObject var store: CrontabStore
    var job: CronJob
    @State private var isConfirmingDelete = false
    @State private var isErrorPreviewExpanded = false
    @AppStorage(AppTextSizing.storageKey) private var appTextFontSize = AppTextSizing.defaultSize

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                header
                jobSummary
                statusPanel
                manualRunPanel
                deletePanel
            }
            .padding(24)
            .frame(maxWidth: 760, alignment: .leading)
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
        HStack(alignment: .top, spacing: 16) {
            VStack(alignment: .leading, spacing: 4) {
                Text(job.title)
                    .font(AppTextSizing.title3(appTextFontSize, weight: .semibold))
                    .lineLimit(2)

                Text(job.rawLine)
                    .font(AppTextSizing.caption(appTextFontSize, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                    .textSelection(.enabled)
            }

            Spacer()

            runNowButton
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var runNowButton: some View {
        Button {
            Task { await store.runNow(jobID: job.id) }
        } label: {
            Label(store.runningJobIDs.contains(job.id) ? "Running" : "Run Now", systemImage: "play.fill")
                .font(AppTextSizing.body(appTextFontSize))
        }
        .buttonStyle(.borderedProminent)
        .controlSize(.regular)
        .disabled(store.runningJobIDs.contains(job.id))
        .help("Run this job in Terminal")
    }

    private var jobSummary: some View {
        GroupBox {
            VStack(spacing: 0) {
                DetailRow("Schedule") {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(job.scheduleDescription)
                        Text(job.scheduleExpression)
                            .font(AppTextSizing.caption(appTextFontSize, design: .monospaced))
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
        } label: {
            Text("Job")
                .font(AppTextSizing.caption(appTextFontSize, weight: .semibold))
        }
    }

    private var commandRow: some View {
        HStack(alignment: .top, spacing: 8) {
            Text(commandText)
                .font(commandTextFont)
                .textSelection(.enabled)
                .lineLimit(3)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 8)
                .padding(.vertical, 6)
                .background(Color(nsColor: .textBackgroundColor), in: RoundedRectangle(cornerRadius: 6))
                .overlay {
                    RoundedRectangle(cornerRadius: 6)
                        .strokeBorder(Color(nsColor: .separatorColor).opacity(0.35), lineWidth: 1)
                }

            Button {
                copyCommand()
            } label: {
                Label("Copy Command", systemImage: "doc.on.doc")
            }
            .labelStyle(.iconOnly)
            .controlSize(.small)
            .help("Copy command")
        }
    }

    private var statusPanel: some View {
        let status = store.statuses[job.id]
        let isLoading = store.statusLoadingJobIDs.contains(job.id)

        return GroupBox {
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
                                .font(commandTextFont)
                                .textSelection(.enabled)
                                .lineLimit(24)

                            Text("\(excerpt.filePath), line \(excerpt.startLineNumber)")
                                .font(AppTextSizing.caption2(appTextFontSize))
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }
                        .padding(.top, 8)
                    } label: {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Error Preview")
                                .font(AppTextSizing.body(appTextFontSize))
                            Text(excerpt.text)
                                .font(commandTextFont)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                                .truncationMode(.tail)
                        }
                    }
                    .padding(.vertical, 8)
                }
            }
            .padding(.vertical, 2)
        } label: {
            Text("Status")
                .font(AppTextSizing.caption(appTextFontSize, weight: .semibold))
        }
    }

    private var manualRunPanel: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 8) {
                manualRunContent
            }
            .font(AppTextSizing.body(appTextFontSize))
            .padding(.vertical, 4)
        } label: {
            Text("Manual Run")
                .font(AppTextSizing.caption(appTextFontSize, weight: .semibold))
        }
    }

    @ViewBuilder
    private var manualRunContent: some View {
        if store.runningJobIDs.contains(job.id) {
            HStack(spacing: 8) {
                ProgressView()
                    .controlSize(.small)
                Text("Opening in Terminal")
                    .foregroundStyle(.secondary)
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
                    .font(AppTextSizing.caption(appTextFontSize))
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

            Button(role: .destructive) {
                isConfirmingDelete = true
            } label: {
                Label("Delete Job", systemImage: "trash")
                    .font(AppTextSizing.body(appTextFontSize))
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

    private var commandTextFont: Font {
        AppTextSizing.code(appTextFontSize)
    }
}

private struct DetailRow<Content: View>: View {
    var title: String
    var content: Content
    @AppStorage(AppTextSizing.storageKey) private var appTextFontSize = AppTextSizing.defaultSize

    init(_ title: String, @ViewBuilder content: () -> Content) {
        self.title = title
        self.content = content()
    }

    var body: some View {
        HStack(alignment: .top, spacing: DetailLayout.rowHorizontalSpacing) {
            Text(title)
                .font(AppTextSizing.body(appTextFontSize))
                .foregroundStyle(.secondary)
                .frame(width: DetailLayout.labelColumnWidth, alignment: .leading)

            content
                .font(AppTextSizing.body(appTextFontSize))
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
    @AppStorage(AppTextSizing.storageKey) private var appTextFontSize = AppTextSizing.defaultSize

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
                .font(AppTextSizing.body(appTextFontSize))
                .lineLimit(1)

            Spacer()

            trailing
        }
        .padding(.vertical, 8)
    }
}

private struct DetailDivider: View {
    var leadingInset: CGFloat = DetailLayout.dividerLeadingInset

    var body: some View {
        Divider()
            .padding(.leading, leadingInset)
    }
}

private enum DetailLayout {
    static let labelColumnWidth: CGFloat = 88
    static let rowHorizontalSpacing: CGFloat = 14
    static let dividerLeadingInset = labelColumnWidth + rowHorizontalSpacing
}

private struct OutputSnippet: View {
    var title: String
    var text: String
    @AppStorage(AppTextSizing.storageKey) private var appTextFontSize = AppTextSizing.defaultSize

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(AppTextSizing.caption(appTextFontSize, weight: .semibold))
                .foregroundStyle(.secondary)
            Text(text)
                .font(AppTextSizing.code(appTextFontSize))
                .textSelection(.enabled)
                .lineLimit(8)
                .padding(8)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color(nsColor: .textBackgroundColor), in: RoundedRectangle(cornerRadius: 6))
                .overlay {
                    RoundedRectangle(cornerRadius: 6)
                        .strokeBorder(Color(nsColor: .separatorColor).opacity(0.35), lineWidth: 1)
                }
        }
    }
}
