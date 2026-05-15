import AppKit
import SwiftUI

struct LogFilesView: View {
    var logPaths: [String]
    var didClearLog: () -> Void = {}

    var body: some View {
        GroupBox("Log Files") {
            LogFilesInlineView(logPaths: logPaths, didClearLog: didClearLog)
        }
    }
}

struct LogFilesInlineView: View {
    var logPaths: [String]
    var isEmbeddedInDetailRow = false
    var didClearLog: () -> Void = {}

    var body: some View {
        if logPaths.isEmpty {
            Text("No log file redirection")
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.vertical, isEmbeddedInDetailRow ? 0 : 4)
        } else {
            VStack(alignment: .leading, spacing: 8) {
                ForEach(logPaths, id: \.self) { path in
                    LogFileRow(path: path, didClearLog: didClearLog)
                }
            }
            .padding(.vertical, isEmbeddedInDetailRow ? 0 : 4)
        }
    }
}

struct LogFileRow: View {
    var path: String
    var didClearLog: () -> Void
    @State private var isConfirmingClear = false
    @State private var isClearing = false
    @State private var clearError: String?
    @State private var openError: String?

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "doc.text.magnifyingglass")
                .foregroundStyle(.secondary)
                .frame(width: 18)

            VStack(alignment: .leading, spacing: 2) {
                Text(fileName)
                    .font(.body)
                    .lineLimit(1)
                    .truncationMode(.middle)

                Text(resolvedPath)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }

            Spacer(minLength: 12)

            Button(role: .destructive) {
                isConfirmingClear = true
            } label: {
                Label("Clear", systemImage: "trash")
            }
            .disabled(isClearing)

            Button {
                openExternally()
            } label: {
                Label("Open", systemImage: "arrow.up.right.square")
            }
        }
        .confirmationDialog(
            "Clear this log file?",
            isPresented: $isConfirmingClear,
            titleVisibility: .visible
        ) {
            Button("Clear Log File", role: .destructive) {
                clearLogFile()
            }

            Button("Cancel", role: .cancel) {}
        } message: {
            Text(resolvedPath)
        }
        .alert("Could Not Clear Log File", isPresented: clearErrorBinding) {
            Button("OK", role: .cancel) {
                clearError = nil
            }
        } message: {
            Text(clearError ?? "")
        }
        .alert("Could Not Open Log File", isPresented: openErrorBinding) {
            Button("OK", role: .cancel) {
                openError = nil
            }
        } message: {
            Text(openError ?? "")
        }
    }

    private var resolvedPath: String {
        PathResolver.resolve(path)
    }

    private var fileName: String {
        URL(fileURLWithPath: resolvedPath).lastPathComponent
    }

    private var clearErrorBinding: Binding<Bool> {
        Binding(
            get: { clearError != nil },
            set: { newValue in
                if !newValue {
                    clearError = nil
                }
            }
        )
    }

    private var openErrorBinding: Binding<Bool> {
        Binding(
            get: { openError != nil },
            set: { newValue in
                if !newValue {
                    openError = nil
                }
            }
        )
    }

    private func clearLogFile() {
        isClearing = true

        Task {
            let result = await Task.detached(priority: .userInitiated) {
                Result {
                    try LogFileService.clear(displayPath: path)
                }
            }
            .value

            switch result {
            case .success:
                clearError = nil
                didClearLog()
            case let .failure(error):
                clearError = error.localizedDescription
            }

            isClearing = false
        }
    }

    private func openExternally() {
        do {
            try LogFileService.openExternally(displayPath: path)
            openError = nil
        } catch {
            openError = error.localizedDescription
        }
    }
}
