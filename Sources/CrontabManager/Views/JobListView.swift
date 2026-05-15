import SwiftUI

struct JobListView: View {
    @ObservedObject var store: CrontabStore

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                Text("Crontab")
                    .font(.headline)

                Spacer()

                if store.isLoading && !store.jobs.isEmpty {
                    ProgressView()
                        .controlSize(.small)
                }

                Button {
                    Task { await store.refresh() }
                } label: {
                    Label("Refresh", systemImage: "arrow.clockwise")
                }
                .labelStyle(.iconOnly)
                .help("Refresh crontab")
                .disabled(store.isLoading)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)

            Divider()

            List(selection: selectionBinding) {
                ForEach(store.jobs) { job in
                    JobRow(
                        job: job,
                        status: store.statuses[job.id],
                        isStatusLoading: store.statusLoadingJobIDs.contains(job.id),
                        isRunning: store.runningJobIDs.contains(job.id)
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
        .navigationTitle("Crontab")
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
                        .font(.body.weight(.semibold))
                        .lineLimit(1)

                    if isRunning || isStatusLoading {
                        ProgressView()
                            .controlSize(.small)
                    }
                }

                Text(job.scheduleDescription)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer(minLength: 16)

            VStack(alignment: .trailing, spacing: 3) {
                Text(errorText)
                    .font(.caption2)
                    .foregroundStyle(errorColor)
                    .lineLimit(1)

                Text(lastSuccessText)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
        .padding(.vertical, 4)
    }

    private var lastSuccessText: String {
        if isStatusLoading, status == nil {
            return "Checking logs..."
        }

        guard let date = status?.lastSuccessfulRun else { return "Last success -" }
        return "Last success \(DisplayFormatters.relativeString(for: date))"
    }

    private var errorText: String {
        if isStatusLoading, status == nil {
            return "Checking errors..."
        }

        if status?.hasRecentError == true {
            return "Recent error"
        }

        if let note = status?.note {
            return note
        }

        return isStatusLoading ? "Refreshing status..." : "No recent errors"
    }

    private var errorColor: Color {
        status?.hasRecentError == true ? .red : .secondary
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
            return .yellow
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
