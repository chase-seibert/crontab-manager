import Foundation

@MainActor
final class CrontabStore: ObservableObject {
    @Published private(set) var document: CrontabDocument = .empty
    @Published private(set) var jobs: [CronJob] = []
    @Published private(set) var statuses: [CronJob.ID: JobStatus] = [:]
    @Published private(set) var statusLoadingJobIDs = Set<CronJob.ID>()
    @Published private(set) var runResults: [CronJob.ID: ManualRunResult] = [:]
    @Published var selectedJobID: CronJob.ID?
    @Published var errorMessage: String?
    @Published private(set) var isLoading = false
    @Published private(set) var runningJobIDs = Set<CronJob.ID>()

    private let crontabService = CrontabService()
    private var statusRefreshTask: Task<Void, Never>?

    var selectedJob: CronJob? {
        guard let selectedJobID else { return nil }
        return jobs.first { $0.id == selectedJobID }
    }

    func refresh() async {
        isLoading = true
        defer { isLoading = false }

        do {
            let loadedDocument = try await crontabService.load()
            apply(document: loadedDocument)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func setEnabled(jobID: CronJob.ID, enabled: Bool) async {
        await modifyAndInstall(selecting: jobID) { document in
            try document.setJobEnabled(jobID: jobID, enabled: enabled)
        }
    }

    func update(jobID: CronJob.ID, draft: JobDraft) async {
        await modifyAndInstall(selecting: jobID) { document in
            try document.updateJob(jobID: jobID, draft: draft)
        }
    }

    func addJob() async {
        await modifyAndInstall(selecting: nil) { document in
            document.addJob()
        }
        selectedJobID = jobs.last?.id
    }

    func removeSelectedJob() async {
        guard let selectedJobID else { return }
        await removeJob(jobID: selectedJobID)
    }

    func removeJob(jobID: CronJob.ID) async {
        await modifyAndInstall(selecting: nil) { document in
            try document.removeJob(jobID: jobID)
        }
    }

    func runSelectedJobNow() async {
        guard let selectedJob else { return }
        await runNow(jobID: selectedJob.id)
    }

    func runNow(jobID: CronJob.ID) async {
        guard let job = jobs.first(where: { $0.id == jobID }) else { return }
        runningJobIDs.insert(jobID)
        defer { runningJobIDs.remove(jobID) }

        do {
            let result = try await crontabService.runNow(job)
            runResults[jobID] = result
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    nonisolated func loadLogTail(path: String) async -> Result<String, Error> {
        await Task.detached(priority: .userInitiated) {
            Result { try LogAnalyzer().readTail(displayPath: path) }
        }
        .value
    }

    private func modifyAndInstall(
        selecting selectedAfterInstall: CronJob.ID?,
        _ mutation: (inout CrontabDocument) throws -> Void
    ) async {
        var editedDocument = document

        do {
            try mutation(&editedDocument)
            try await crontabService.install(editedDocument)
            apply(document: editedDocument)

            if let selectedAfterInstall {
                selectedJobID = jobs.contains(where: { $0.id == selectedAfterInstall }) ? selectedAfterInstall : jobs.first?.id
            } else if selectedJobID == nil || !jobs.contains(where: { $0.id == selectedJobID }) {
                selectedJobID = jobs.first?.id
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func apply(document newDocument: CrontabDocument) {
        document = newDocument
        jobs = newDocument.jobs
        statuses = statuses.filter { jobID, _ in
            jobs.contains { $0.id == jobID }
        }

        if selectedJobID == nil || !jobs.contains(where: { $0.id == selectedJobID }) {
            selectedJobID = jobs.first?.id
        }

        refreshStatuses(for: jobs)
    }

    private func refreshStatuses(for jobs: [CronJob]) {
        statusRefreshTask?.cancel()

        let jobIDs = Set(jobs.map(\.id))
        statusLoadingJobIDs = jobIDs

        guard !jobs.isEmpty else {
            statuses = [:]
            return
        }

        statusRefreshTask = Task { [jobs] in
            let loadedStatuses = await Task.detached(priority: .utility) {
                Dictionary(uniqueKeysWithValues: jobs.map { job in
                    (job.id, LogAnalyzer().analyze(job: job))
                })
            }
            .value

            guard !Task.isCancelled else { return }

            statuses = loadedStatuses
            statusLoadingJobIDs = []
        }
    }
}
