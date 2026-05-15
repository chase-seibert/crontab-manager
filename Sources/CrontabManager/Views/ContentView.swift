import AppKit
import SwiftUI

struct ContentView: View {
    @ObservedObject var store: CrontabStore
    @SceneStorage("isDetailPaneVisible") private var isDetailPaneVisible = true
    @State private var windowHandle = WindowHandle()
    @State private var measuredListWidth = DetailPaneWindowSizing.collapsedContentWidth
    @State private var lastExpandedContentWidth = DetailPaneWindowSizing.expandedContentWidth

    var body: some View {
        HSplitView {
            JobListView(store: store)
                .frame(minWidth: 360, idealWidth: 460, maxWidth: isDetailPaneVisible ? 560 : .infinity)
                .background {
                    GeometryReader { proxy in
                        Color.clear.preference(key: ListPaneWidthPreferenceKey.self, value: proxy.size.width)
                    }
                }

            if isDetailPaneVisible {
                if let job = store.selectedJob {
                    JobDetailView(store: store, job: job)
                        .id(job.id)
                        .frame(minWidth: 540, maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    EmptyStateView()
                        .frame(minWidth: 540, maxWidth: .infinity, maxHeight: .infinity)
                }
            }
        }
        .frame(
            minWidth: isDetailPaneVisible ? DetailPaneWindowSizing.expandedMinimumContentWidth : DetailPaneWindowSizing.minimumListWidth,
            idealWidth: isDetailPaneVisible ? DetailPaneWindowSizing.expandedContentWidth : DetailPaneWindowSizing.collapsedContentWidth,
            minHeight: DetailPaneWindowSizing.minimumHeight
        )
        .background(WindowAccessor(handle: windowHandle))
        .onPreferenceChange(ListPaneWidthPreferenceKey.self) { width in
            guard width.isFinite, width > 0 else { return }
            measuredListWidth = width
        }
        .task {
            await store.refresh()
        }
        .toolbar {
            ToolbarItemGroup(placement: .primaryAction) {
                Button {
                    Task { await store.refresh() }
                } label: {
                    Label("Refresh", systemImage: "arrow.clockwise")
                }
                .labelStyle(.iconOnly)
                .help("Refresh crontab")
                .disabled(store.isLoading)

                Button {
                    toggleDetailPane()
                } label: {
                    Label(isDetailPaneVisible ? "Hide Details" : "Show Details", systemImage: "sidebar.right")
                }
                .labelStyle(.iconOnly)
                .help(isDetailPaneVisible ? "Hide details pane" : "Show details pane")
            }
        }
        .alert("Crontab Manager", isPresented: errorBinding) {
            Button("OK", role: .cancel) {
                store.errorMessage = nil
            }
        } message: {
            Text(store.errorMessage ?? "")
        }
    }

    private var errorBinding: Binding<Bool> {
        Binding(
            get: { store.errorMessage != nil },
            set: { newValue in
                if !newValue {
                    store.errorMessage = nil
                }
            }
        )
    }

    private func toggleDetailPane() {
        if isDetailPaneVisible {
            if let contentWidth = windowHandle.window?.contentView?.bounds.width, contentWidth > 0 {
                lastExpandedContentWidth = contentWidth
            }

            let targetWidth = measuredListWidth
                .clamped(to: DetailPaneWindowSizing.minimumListWidth...DetailPaneWindowSizing.maximumListWidth)

            withAnimation(.easeInOut(duration: 0.16)) {
                isDetailPaneVisible = false
            }
            resizeWindowAfterLayout(toContentWidth: targetWidth)
        } else {
            let targetWidth = max(lastExpandedContentWidth, DetailPaneWindowSizing.expandedMinimumContentWidth)

            withAnimation(.easeInOut(duration: 0.16)) {
                isDetailPaneVisible = true
            }
            resizeWindowAfterLayout(toContentWidth: targetWidth)
        }
    }

    private func resizeWindowAfterLayout(toContentWidth width: CGFloat) {
        Task { @MainActor in
            await Task.yield()
            resizeWindow(toContentWidth: width)
        }
    }

    private func resizeWindow(toContentWidth width: CGFloat) {
        guard let window = windowHandle.window else { return }

        let currentFrame = window.frame
        let currentContentHeight = window.contentView?.bounds.height ?? window.contentLayoutRect.height
        let contentHeight = max(currentContentHeight, DetailPaneWindowSizing.minimumHeight)
        let contentRect = NSRect(
            x: 0,
            y: 0,
            width: width.rounded(.up),
            height: contentHeight.rounded(.up)
        )
        var targetFrame = window.frameRect(forContentRect: contentRect)

        targetFrame.origin.x = currentFrame.minX
        targetFrame.origin.y = currentFrame.maxY - targetFrame.height

        if let visibleRect = window.screen?.visibleFrame {
            targetFrame.origin.x = min(max(targetFrame.minX, visibleRect.minX), visibleRect.maxX - targetFrame.width)
            targetFrame.origin.y = min(max(targetFrame.minY, visibleRect.minY), visibleRect.maxY - targetFrame.height)
        }

        window.setFrame(targetFrame, display: true, animate: true)
    }
}

private struct EmptyStateView: View {
    @AppStorage(AppTextSizing.storageKey) private var appTextFontSize = AppTextSizing.defaultSize

    var body: some View {
        VStack(spacing: 14) {
            Image(systemName: "calendar.badge.clock")
                .font(.system(size: 52))
                .foregroundStyle(.secondary)
            Text("No Scheduled Items")
                .font(AppTextSizing.title3(appTextFontSize, weight: .semibold))
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

enum DetailPaneWindowSizing {
    static let minimumListWidth: CGFloat = 360
    static let collapsedContentWidth: CGFloat = 460
    static let maximumListWidth: CGFloat = 560
    static let minimumDetailWidth: CGFloat = 540
    static let expandedMinimumContentWidth = minimumListWidth + minimumDetailWidth
    static let expandedContentWidth: CGFloat = 980
    static let minimumHeight: CGFloat = 640
}

private struct ListPaneWidthPreferenceKey: PreferenceKey {
    static let defaultValue: CGFloat = DetailPaneWindowSizing.collapsedContentWidth

    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        let nextValue = nextValue()
        if nextValue > 0 {
            value = nextValue
        }
    }
}

private extension CGFloat {
    func clamped(to range: ClosedRange<CGFloat>) -> CGFloat {
        Swift.min(Swift.max(self, range.lowerBound), range.upperBound)
    }
}

private final class WindowHandle {
    weak var window: NSWindow?
}

private struct WindowAccessor: NSViewRepresentable {
    let handle: WindowHandle

    func makeNSView(context: Context) -> NSView {
        WindowCaptureView(handle: handle)
    }

    func updateNSView(_ nsView: NSView, context: Context) {}

    private final class WindowCaptureView: NSView {
        private let handle: WindowHandle

        init(handle: WindowHandle) {
            self.handle = handle
            super.init(frame: .zero)
        }

        @available(*, unavailable)
        required init?(coder: NSCoder) {
            nil
        }

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            handle.window = window
            window?.title = "Crontab Manager"
        }
    }
}
