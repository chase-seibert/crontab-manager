import AppKit
import SwiftUI

struct LogFilesView: View {
    var logPaths: [String]
    var didClearLog: () -> Void = {}
    @AppStorage(AppTextSizing.storageKey) private var appTextFontSize = AppTextSizing.defaultSize

    var body: some View {
        GroupBox {
            LogFilesInlineView(logPaths: logPaths, didClearLog: didClearLog)
        } label: {
            Text("Log Files")
                .font(AppTextSizing.caption(appTextFontSize, weight: .semibold))
        }
    }
}

struct LogFilesInlineView: View {
    var logPaths: [String]
    var isEmbeddedInDetailRow = false
    var didClearLog: () -> Void = {}
    @AppStorage(AppTextSizing.storageKey) private var appTextFontSize = AppTextSizing.defaultSize

    var body: some View {
        if logPaths.isEmpty {
            Text("No log file redirection")
                .font(AppTextSizing.body(appTextFontSize))
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
    @AppStorage(AppTextSizing.storageKey) private var appTextFontSize = AppTextSizing.defaultSize

    var body: some View {
        HStack(spacing: 8) {
            Text(resolvedPath)
                .font(AppTextSizing.code(appTextFontSize))
                .lineLimit(1)
                .truncationMode(.middle)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 8)
                .padding(.vertical, 6)
                .background(Color(nsColor: .textBackgroundColor), in: RoundedRectangle(cornerRadius: 6))
                .overlay {
                    RoundedRectangle(cornerRadius: 6)
                        .strokeBorder(Color(nsColor: .separatorColor).opacity(0.35), lineWidth: 1)
                }

            Button {
                copyLogFilePath()
            } label: {
                Label("Copy Log File Path", systemImage: "doc.on.doc")
            }
            .labelStyle(.iconOnly)
            .controlSize(.small)
            .help("Copy log file path")

            Button(role: .destructive) {
                isConfirmingClear = true
            } label: {
                Label("Clear", systemImage: "trash")
                    .font(AppTextSizing.body(appTextFontSize))
            }
            .controlSize(.small)
            .disabled(isClearing)

            Button {
                openExternally()
            } label: {
                Label("Open", systemImage: "arrow.up.right.square")
                    .font(AppTextSizing.body(appTextFontSize))
            }
            .controlSize(.small)
            .buttonStyle(.borderedProminent)
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

    private func copyLogFilePath() {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(resolvedPath, forType: .string)
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
