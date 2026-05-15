import SwiftUI

struct JobListView: View {
    @ObservedObject var store: CrontabStore
    @AppStorage(AppTextSizing.storageKey) private var appTextFontSize = AppTextSizing.defaultSize

    var body: some View {
        List(selection: selectionBinding) {
            ForEach(store.jobs) { job in
                JobRow(
                    job: job,
                    status: store.statuses[job.id],
                    isStatusLoading: store.statusLoadingJobIDs.contains(job.id),
                    isRunning: store.runningJobIDs.contains(job.id),
                    appTextFontSize: appTextFontSize
                )
                .tag(job.id)
                .contextMenu {
                    Button("Run Now") {
                        Task { await store.runNow(jobID: job.id) }
                    }

                    Button(job.isEnabled ? "Disable" : "Enable") {
                        Task { await store.setEnabled(jobID: job.id, enabled: !job.isEnabled) }
                    }
                }
            }
        }
        .overlay {
            if store.isLoading && store.jobs.isEmpty {
                ProgressView()
            }
        }
        .listStyle(.sidebar)
    }

    private var selectionBinding: Binding<CronJob.ID?> {
        Binding(
            get: { store.selectedJobID },
            set: { store.selectedJobID = $0 }
        )
    }
}

private struct JobRow: View {
    var job: CronJob
    var status: JobStatus?
    var isStatusLoading: Bool
    var isRunning: Bool
    var appTextFontSize: Double

    var body: some View {
        HStack(alignment: .center, spacing: 10) {
            Image(systemName: statusIconName)
                .foregroundStyle(statusIconColor)
                .imageScale(.large)
                .accessibilityLabel(statusIconLabel)
                .frame(width: 18)

            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(job.title)
                        .font(AppTextSizing.body(appTextFontSize, weight: .medium))
                        .lineLimit(1)

                    if isRunning || isStatusLoading {
                        ProgressView()
                            .controlSize(.small)
                    }
                }

                Text(sidebarDetailText)
                    .font(AppTextSizing.caption(appTextFontSize))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer(minLength: 0)
        }
        .padding(.vertical, 5)
    }

    private var sidebarDetailText: String {
        "\(statusSummary) - \(job.scheduleDescription)"
    }

    private var statusSummary: String {
        if isRunning {
            return "Running"
        }

        if isStatusLoading, status == nil {
            return "Checking status"
        }

        if status?.hasRecentError == true {
            return "Recent error"
        }

        if let date = status?.lastSuccessfulRun {
            return "Last success \(DisplayFormatters.relativeString(for: date))"
        }

        if let note = status?.note {
            return note
        }

        return isStatusLoading ? "Refreshing status" : "Status pending"
    }

    private var statusIconName: String {
        if !job.isEnabled {
            return "pause.circle.fill"
        }

        guard let status, didRunRecently(status) else {
            return "questionmark.circle.fill"
        }

        return status.hasRecentError ? "xmark.circle.fill" : "checkmark.circle.fill"
    }

    private var statusIconColor: Color {
        if !job.isEnabled {
            return .orange
        }

        guard let status, didRunRecently(status) else {
            return .secondary
        }

        return status.hasRecentError ? .red : .green
    }

    private var statusIconLabel: String {
        if !job.isEnabled {
            return "Disabled"
        }

        guard let status, didRunRecently(status) else {
            return "Run status unknown"
        }

        return status.hasRecentError ? "Ran recently with errors" : "Ran recently without errors"
    }

    private func didRunRecently(_ status: JobStatus) -> Bool {
        status.logFiles.contains { summary in
            summary.exists && summary.modifiedAt != nil
        }
    }
}
