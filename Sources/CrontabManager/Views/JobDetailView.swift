import AppKit
import SwiftUI

struct JobDetailView: View {
    @ObservedObject var store: CrontabStore
    var job: CronJob
    @State private var isConfirmingDelete = false
    @State private var isErrorPreviewExpanded = true
    @AppStorage(AppTextSizing.storageKey) private var appTextFontSize = AppTextSizing.defaultSize

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                header
                jobFields
                statusPanel
                manualRunPanel
                deletePanel
            }
            .padding(24)
            .frame(maxWidth: 620, alignment: .leading)
        }
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
        VStack(alignment: .leading, spacing: 4) {
            Text(job.title)
                .font(AppTextSizing.title3(appTextFontSize, weight: .semibold))
                .lineLimit(2)

            Text(headerSubtitle)
                .font(AppTextSizing.caption(appTextFontSize))
                .foregroundStyle(.secondary)
                .lineLimit(1)
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
        .buttonStyle(.bordered)
        .controlSize(.small)
        .disabled(store.runningJobIDs.contains(job.id))
        .help("Run this job in Terminal")
    }

    private var jobFields: some View {
        VStack(alignment: .leading, spacing: 14) {
            DetailField("Job") {
                Text(job.title)
                    .font(AppTextSizing.body(appTextFontSize))
                    .lineLimit(2)
            }

            DetailField("Schedule") {
                VStack(alignment: .leading, spacing: 2) {
                    Text(job.scheduleDescription)
                        .font(AppTextSizing.body(appTextFontSize))
                    Text(job.scheduleExpression)
                        .font(AppTextSizing.caption(appTextFontSize, design: .monospaced))
                        .foregroundStyle(.secondary)
                }
            }

            DetailField("Enabled") {
                Toggle("Enabled", isOn: enabledBinding)
                    .toggleStyle(.switch)
                    .labelsHidden()
            }

            DetailField("Command") {
                commandRow
            }

            DetailField("Log Files") {
                LogFilesInlineView(logPaths: job.logPaths, isEmbeddedInDetailRow: true) {
                    Task { await store.refresh() }
                }
            }
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

        return DetailField("Status") {
            VStack(alignment: .leading, spacing: 9) {
                StatusBulletLine(title: lastSuccessText(status), tint: .secondary) {
                    if isLoading { ProgressView().controlSize(.small) }
                }

                StatusBulletLine(
                    title: errorSummary(status),
                    tint: status?.hasRecentError == true ? .red : .secondary
                ) {
                    if isLoading, status != nil { ProgressView().controlSize(.small) }
                }

                if let excerpt = status?.recentErrorExcerpt {
                    DisclosureGroup(isExpanded: $isErrorPreviewExpanded) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(excerpt.text)
                                .font(errorPreviewFont)
                                .textSelection(.enabled)
                                .lineLimit(24)

                            Text("\(excerpt.filePath), line \(excerpt.startLineNumber)")
                                .font(AppTextSizing.caption2(appTextFontSize))
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }
                        .padding(.top, 8)
                    } label: {
                        Text("Error Preview")
                            .font(AppTextSizing.body(appTextFontSize))
                    }
                }
            }
        }
    }

    private var manualRunPanel: some View {
        DetailField("Manual Run") {
            HStack(alignment: .top, spacing: 16) {
                manualRunContent

                Spacer(minLength: 12)

                VStack(alignment: .trailing, spacing: 6) {
                    runNowButton
                    Text("Manual run")
                        .font(AppTextSizing.caption(appTextFontSize))
                        .foregroundStyle(.secondary)
                }
            }
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
                HStack(spacing: 8) {
                    Label("Opened in Terminal", systemImage: "terminal")
                        .foregroundStyle(.green)
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

    private var headerSubtitle: String {
        "\(lastRunSummary) - \(job.isEnabled ? "Enabled" : "Disabled")"
    }

    private var lastRunSummary: String {
        guard let status = store.statuses[job.id], let date = status.lastSuccessfulRun else {
            return "Last run unavailable"
        }

        return "Last run \(DisplayFormatters.relativeString(for: date))"
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

    private var errorPreviewFont: Font {
        AppTextSizing.caption(appTextFontSize, design: .monospaced)
    }
}

private struct DetailField<Content: View>: View {
    var label: String
    var content: Content
    @AppStorage(AppTextSizing.storageKey) private var appTextFontSize = AppTextSizing.defaultSize

    init(_ label: String, @ViewBuilder content: () -> Content) {
        self.label = label
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(label.uppercased())
                .font(AppTextSizing.caption(appTextFontSize))
                .foregroundStyle(.secondary)
                .lineLimit(1)

            content
                .font(AppTextSizing.body(appTextFontSize))
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct StatusBulletLine<Trailing: View>: View {
    var title: String
    var tint: Color
    var trailing: Trailing
    @AppStorage(AppTextSizing.storageKey) private var appTextFontSize = AppTextSizing.defaultSize

    init(
        title: String,
        tint: Color = .secondary,
        @ViewBuilder trailing: () -> Trailing
    ) {
        self.title = title
        self.tint = tint
        self.trailing = trailing()
    }

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "circle.fill")
                .font(.system(size: 6))
                .foregroundStyle(tint)
                .frame(width: 10)

            Text(title)
                .font(AppTextSizing.body(appTextFontSize))
                .lineLimit(1)

            Spacer()

            trailing
        }
    }
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
