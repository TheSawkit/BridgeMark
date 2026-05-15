import SwiftUI
import AppKit

@main
struct BridgeMarkApp: App {
    @State private var viewModel = SyncViewModel()

    var body: some Scene {
        WindowGroup {
            ContentView(viewModel: viewModel)
                .frame(minWidth: 420, minHeight: 280)
        }
        .windowStyle(.automatic)
        .windowToolbarStyle(.unified)
    }
}

enum SyncState: Equatable {
    case idle
    case running
    case success(message: String)
    case failure(message: String, recoveryURL: URL?)
}

@Observable
@MainActor
final class SyncViewModel {
    var strategy: SyncStrategy = .merge
    var selectedBrowser: BrowserProfile? = BrowserProfile.installed.first
    var state: SyncState = .idle
    var showPermissionAlert = false

    var isRunning: Bool { state == .running }

    func run() {
        guard let browser = selectedBrowser, !isRunning else { return }
        state = .running
        let strategy = self.strategy
        Task.detached(priority: .userInitiated) { [weak self] in
            let result = Result { try SyncEngine().sync(to: browser, strategy: strategy) }
            await self?.apply(result)
        }
    }

    private func apply(_ result: Result<SyncReport, Error>) {
        switch result {
        case .success(let report):
            state = .success(message: report.message)
        case .failure(let error):
            let syncError = error as? SyncError
            state = .failure(message: error.localizedDescription, recoveryURL: syncError?.recoveryURL)
            if case .permissionDenied = syncError { showPermissionAlert = true }
        }
    }
}

struct ContentView: View {
    @Bindable var viewModel: SyncViewModel
    @State private var showOverwriteConfirm = false

    private var installedBrowsers: [BrowserProfile] { BrowserProfile.installed }

    var body: some View {
        if installedBrowsers.isEmpty {
            NoBrowsersView()
        } else {
            mainForm
        }
    }

    private var mainForm: some View {
        Form {
            Section {
                SyncHeaderView(targetBrowser: viewModel.selectedBrowser)
            }

            Section {
                Picker(selection: $viewModel.selectedBrowser) {
                    ForEach(installedBrowsers) { browser in
                        Label {
                            Text(browser.name)
                        } icon: {
                            BrowserIconView(appURL: browser.appURL)
                        }
                        .tag(Optional(browser))
                    }
                } label: {
                    Text("picker.browser.label", bundle: .module)
                }

                Picker(selection: $viewModel.strategy) {
                    ForEach(SyncStrategy.allCases, id: \.self) { Text($0.label).tag($0) }
                } label: {
                    Text("picker.strategy.label", bundle: .module)
                }
                .pickerStyle(.segmented)
            }

            if viewModel.strategy == .overwrite {
                OverwriteWarningView(browserName: viewModel.selectedBrowser?.name ?? "…")
            }

            Section {
                SyncButtonView(
                    browserName: viewModel.selectedBrowser?.name ?? "…",
                    isRunning: viewModel.isRunning,
                    isDisabled: viewModel.isRunning || viewModel.selectedBrowser == nil,
                    strategy: viewModel.strategy,
                    showConfirm: $showOverwriteConfirm,
                    onSync: viewModel.run
                )
            }

            if case .success(let message) = viewModel.state {
                Section {
                    ResultBannerView(isSuccess: true, message: message, recoveryURL: nil)
                }
            }

            if case .failure(let message, let url) = viewModel.state {
                Section {
                    ResultBannerView(isSuccess: false, message: message, recoveryURL: url)
                }
            }
        }
        .formStyle(.grouped)
        .animation(.spring(duration: 0.3), value: viewModel.state)
        .animation(.spring(duration: 0.25), value: viewModel.strategy)
        .alert(
            String(localized: "permission.alert.title", bundle: .module),
            isPresented: $viewModel.showPermissionAlert
        ) {
            Button(String(localized: "permission.alert.open", bundle: .module)) {
                NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_AllFiles")!)
            }
            Button(String(localized: "permission.alert.later", bundle: .module), role: .cancel) {}
        } message: {
            Text("permission.alert.message", bundle: .module)
        }
    }
}

struct NoBrowsersView: View {
    var body: some View {
        VStack(spacing: 12) {
            Text("🔍").font(.system(size: 40))
            Text("no.browsers.detected", bundle: .module)
                .font(.body)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding()
    }
}

struct BrowserIconView: View {
    let appURL: URL?
    var size: CGFloat = 16

    var body: some View {
        if let appURL,
           let cgImage = NSWorkspace.shared.icon(forFile: appURL.path).cgImage(forProposedRect: nil, context: nil, hints: nil) {
            Image(decorative: cgImage, scale: 1)
                .resizable()
                .frame(width: size, height: size)
        } else {
            Image(systemName: "globe").frame(width: size, height: size)
        }
    }
}

struct SyncHeaderView: View {
    let targetBrowser: BrowserProfile?

    var body: some View {
        HStack(spacing: 0) {
            Spacer()
            BrowserPillView(appURL: BrowserProfile.safariAppURL, name: "Safari")
            Image(systemName: "arrow.right")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(.secondary)
                .padding(.horizontal, 12)
                .padding(.bottom, 14)
            BrowserPillView(appURL: targetBrowser.flatMap(\.appURL), name: targetBrowser?.name ?? "…")
            Spacer()
        }
        .padding(.vertical, 8)
    }
}

struct BrowserPillView: View {
    let appURL: URL?
    let name: String

    var body: some View {
        VStack(spacing: 4) {
            if let appURL {
                Image(nsImage: NSWorkspace.shared.icon(forFile: appURL.path))
                    .resizable()
                    .frame(width: 36, height: 36)
            } else {
                Image(systemName: "globe")
                    .font(.system(size: 28))
                    .frame(width: 36, height: 36)
            }
            Text(name)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }
}

struct OverwriteWarningView: View {
    let browserName: String

    var body: some View {
        Section {
            Label {
                Text("overwrite.warning \(browserName)", bundle: .module)
                    .font(.callout)
                    .fixedSize(horizontal: false, vertical: true)
            } icon: {
                Text("⚠️")
            }
        }
    }
}

struct SyncButtonView: View {
    let browserName: String
    let isRunning: Bool
    let isDisabled: Bool
    let strategy: SyncStrategy
    @Binding var showConfirm: Bool
    let onSync: () -> Void

    var body: some View {
        Button {
            if strategy == .overwrite { showConfirm = true } else { onSync() }
        } label: {
            Group {
                if isRunning {
                    HStack(spacing: 8) {
                        ProgressView().controlSize(.small)
                        Text("status.syncing", bundle: .module)
                    }
                } else {
                    Text(String(localized: "sync.button \(browserName)", bundle: .module))
                }
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 2)
        }
        .buttonStyle(.borderedProminent)
        .disabled(isDisabled)
        .confirmationDialog(
            Text("overwrite.confirm.title \(browserName)", bundle: .module),
            isPresented: $showConfirm,
            titleVisibility: .visible
        ) {
            Button(role: .destructive, action: onSync) {
                Text("overwrite.confirm.destructive", bundle: .module)
            }
            Button(role: .cancel, action: {}) {
                Text("overwrite.confirm.cancel", bundle: .module)
            }
        } message: {
            Text("overwrite.confirm.message \(browserName)", bundle: .module)
        }
    }
}

struct ResultBannerView: View {
    let isSuccess: Bool
    let message: String
    let recoveryURL: URL?

    private var accentColor: Color { isSuccess ? .green : .red }

    var body: some View {
        HStack(spacing: 10) {
            Text(isSuccess ? "✅" : "❌").font(.system(size: 15))
            VStack(alignment: .leading, spacing: 2) {
                Text(message)
                    .font(.callout.weight(.medium))
                    .foregroundStyle(accentColor)
                    .textSelection(.enabled)
                if let url = recoveryURL {
                    Button { NSWorkspace.shared.open(url) } label: {
                        Text("open.system.settings.fda", bundle: .module)
                    }
                    .buttonStyle(.link)
                    .font(.caption)
                }
            }
            Spacer()
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(accentColor.opacity(0.08))
                .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(accentColor.opacity(0.25), lineWidth: 1))
        )
        .listRowInsets(EdgeInsets())
        .listRowBackground(Color.clear)
    }
}
