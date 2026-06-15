import AppKit
import CodexContextCore
import Foundation
import SwiftUI
import UserNotifications

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, UNUserNotificationCenterDelegate {
    private let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    private let dashboardState = DashboardState()
    private let text = AppText.current
    private let selectedSessionKey = "selectedSessionID"
    private let displayBaselinesKey = "clearBaselines"
    private let contextUsageNotificationThreshold = 0.50
    private var selectedTheme: AppThemeChoice = .saved
    private var timer: Timer?
    private var refreshTask: Task<Void, Never>?
    private var compressionTask: Task<Void, Never>?
    private var updateTask: Task<Void, Never>?
    private var dashboardWindow: NSWindow?
    private var refreshGeneration = 0
    private var refreshInProgress = false
    private var showsLoadingState = false
    private var compressionStatus: CompressionStatus?
    private var lastSnapshot: ContextSnapshot?
    private var recentSessions: [SessionChoice] = []
    private var loadingSessionID: String?
    private var selectedSessionID: String?
    private var displayBaselines: [String: ContextBaseline] = [:]
    private var updateState: AppUpdateState = .idle
    private var contextUsageNotificationHandledSessionIDs: Set<String> = []
    private var contextUsageNotificationPendingSessionIDs: Set<String> = []
    private lazy var relativeDateFormatter: RelativeDateTimeFormatter = {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .short
        formatter.locale = text.locale
        return formatter
    }()

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        UNUserNotificationCenter.current().delegate = self
        selectedSessionID = UserDefaults.standard.string(forKey: selectedSessionKey)
        displayBaselines = loadDisplayBaselines()
        dashboardState.onResetDisplayBaseline = { [weak self] in
            self?.resetDisplayBaselineNow()
        }
        dashboardState.onUndoDisplayBaselineReset = { [weak self] in
            self?.undoDisplayBaselineReset()
        }
        dashboardState.onSelectSession = { [weak self] id in
            self?.selectSession(id: id)
        }
        dashboardState.onSelectAutoLatest = { [weak self] in
            self?.selectAutoLatest()
        }
        dashboardState.onCompress = { [weak self] in
            self?.compressCurrentSession()
        }
        dashboardState.onCheckForUpdates = { [weak self] in
            self?.checkForUpdatesFromMenu()
        }
        dashboardState.onInstallUpdate = { [weak self] in
            self?.installUpdate()
        }
        dashboardState.onOpenUpdateRelease = { [weak self] in
            self?.openUpdateRelease()
        }
        applyThemeToWindow()

        statusItem.button?.image = NSImage(systemSymbolName: "gauge.with.dots.needle.50percent", accessibilityDescription: text.codexContext)
        statusItem.button?.imagePosition = .imageLeading
        statusItem.button?.font = .monospacedDigitSystemFont(ofSize: NSFont.systemFontSize, weight: .medium)
        updateStatusItemTitle("Codex ...", isWarning: false)
        updateMenu(isLoading: true)
        showDashboard()

        refresh(showLoading: true, priority: .userInitiated)
        checkForUpdates(showUpToDate: false, showFailure: false)
        timer = Timer.scheduledTimer(
            timeInterval: 5,
            target: self,
            selector: #selector(refreshFromTimer),
            userInfo: nil,
            repeats: true
        )
    }

    private func refresh(showLoading: Bool, priority: TaskPriority) {
        if !showLoading, refreshInProgress {
            return
        }

        refreshGeneration += 1
        let generation = refreshGeneration
        let selectedSessionID = selectedSessionID
        let displayBaselines = displayBaselines
        let cachedSessions = recentSessions

        refreshInProgress = true
        showsLoadingState = showLoading || lastSnapshot == nil
        if showLoading || lastSnapshot == nil {
            loadingSessionID = selectedSessionID
            updateMenu(isLoading: true)
        }
        syncDashboardState(isLoading: showsLoadingState)

        refreshTask?.cancel()
        refreshTask = Task.detached(priority: priority) {
            let result = RefreshLoader.load(
                selectedSessionID: selectedSessionID,
                displayBaselines: displayBaselines,
                cachedSessions: cachedSessions,
                menuSessionLimit: 15
            )

            guard !Task.isCancelled else {
                return
            }

            await MainActor.run {
                self.applyRefreshResult(result, generation: generation)
            }
        }
    }

    private func applyRefreshResult(_ result: RefreshResult, generation: Int) {
        guard generation == refreshGeneration else {
            return
        }

        refreshInProgress = false
        showsLoadingState = false
        loadingSessionID = nil
        lastSnapshot = result.snapshot
        recentSessions = result.recentSessions
        updateContextUsageNotification(for: result.snapshot)
        updateStatusItem(for: result.snapshot)
        updateMenu(isLoading: false)
        syncDashboardState(isLoading: false)
    }

    private func updateContextUsageNotification(for snapshot: ContextSnapshot) {
        guard let sessionID = snapshot.session?.id, snapshot.contextWindow > 0 else {
            return
        }

        guard snapshot.usageRatio >= contextUsageNotificationThreshold else {
            contextUsageNotificationHandledSessionIDs.remove(sessionID)
            contextUsageNotificationPendingSessionIDs.remove(sessionID)
            return
        }

        guard !contextUsageNotificationHandledSessionIDs.contains(sessionID),
              !contextUsageNotificationPendingSessionIDs.contains(sessionID) else {
            return
        }

        contextUsageNotificationPendingSessionIDs.insert(sessionID)
        let title = text.contextUsageNotificationTitle
        let body = text.contextUsageNotificationBody(formatPercent(snapshot.usageRatio))

        Task { [weak self] in
            let didSubmitNotification = await Self.submitContextUsageNotification(
                title: title,
                body: body,
                sessionID: sessionID
            )

            guard let self else {
                return
            }
            if contextUsageNotificationPendingSessionIDs.remove(sessionID) != nil {
                if didSubmitNotification {
                    contextUsageNotificationHandledSessionIDs.insert(sessionID)
                }
            }
        }
    }

    private func updateMenu(isLoading: Bool) {
        let menuSnapshot = snapshotForCurrentSelection()
        statusItem.menu = buildMenu(
            snapshot: menuSnapshot,
            sessions: recentSessions,
            isLoading: isLoading || showsLoadingState
        )
    }

    private func syncDashboardState(isLoading: Bool) {
        dashboardState.snapshot = snapshotForCurrentSelection()
        dashboardState.sessions = recentSessions
        dashboardState.isLoading = isLoading
        dashboardState.selectedSessionID = selectedSessionID
        dashboardState.loadingSessionID = loadingSessionID
        dashboardState.displayBaselines = displayBaselines
        dashboardState.compressionStatus = compressionStatus
        dashboardState.updateState = updateState
    }

    private func snapshotForCurrentSelection() -> ContextSnapshot? {
        guard let selectedSessionID else {
            return lastSnapshot
        }

        guard lastSnapshot?.session?.id == selectedSessionID else {
            return nil
        }

        return lastSnapshot
    }

    private func statusTitle(_ snapshot: ContextSnapshot) -> String {
        guard snapshot.contextWindow > 0 else {
            return "Codex --"
        }
        return "Codex \(formatPercent(snapshot.usageRatio))"
    }

    private func updateStatusItem(for snapshot: ContextSnapshot) {
        let isWarning = snapshot.contextWindow > 0 && snapshot.usageRatio >= contextUsageNotificationThreshold
        updateStatusItemTitle(statusTitle(snapshot), isWarning: isWarning)
    }

    private func updateStatusItemTitle(_ title: String, isWarning: Bool) {
        let color: NSColor = isWarning ? .systemRed : .labelColor
        statusItem.button?.attributedTitle = NSAttributedString(
            string: title,
            attributes: [
                .font: NSFont.monospacedDigitSystemFont(ofSize: NSFont.systemFontSize, weight: .medium),
                .foregroundColor: color
            ]
        )
    }

    private func buildMenu(snapshot: ContextSnapshot?, sessions: [SessionChoice], isLoading: Bool) -> NSMenu {
        let menu = NSMenu()
        menu.autoenablesItems = false

        if let session = snapshot?.session {
            menu.addItem(header(text.codexContext))
            menu.addItem(label(text.session, session.name ?? shortID(session.id)))
            menu.addItem(label(text.mode, selectedSessionID == nil ? text.autoLatest : text.pinned))
            if let baseline = snapshot?.baseline {
                menu.addItem(label(text.baselineSet, relativeDate(baseline.baselineSetAt)))
            }
            if let cwd = session.cwd {
                menu.addItem(label(text.workspace, abbreviateHome(cwd)))
            }
            menu.addItem(label(text.updated, relativeDate(session.updatedAt)))
        } else if let loadingSession = loadingSession() {
            menu.addItem(header(text.codexContext))
            menu.addItem(label(text.session, loadingSession.name ?? shortID(loadingSession.id)))
            menu.addItem(label(text.mode, selectedSessionID == nil ? text.autoLatest : text.pinned))
            if let cwd = loadingSession.cwd {
                menu.addItem(label(text.workspace, abbreviateHome(cwd)))
            }
            menu.addItem(label(text.status, text.loading))
        } else if isLoading {
            menu.addItem(header(text.codexContext))
            menu.addItem(disabled(text.loadingSessionData))
        } else {
            menu.addItem(header(text.codexContext))
            menu.addItem(disabled(text.noActiveUserSessionFound))
        }

        menu.addItem(.separator())
        if let snapshot {
            menu.addItem(label(displayContextTitle(snapshot), contextLine(snapshot)))
            menu.addItem(label(displayInputTitle(snapshot), text.tokenCount(formatTokens(snapshot.displayInputTokens))))
            menu.addItem(label(displayCachedInputTitle(snapshot), text.tokenCount(formatTokens(snapshot.displayCachedInputTokens))))
            menu.addItem(label(displayRunTotalTitle(snapshot), text.tokenCount(formatTokens(snapshot.displayTotalRunTokens))))
            if snapshot.baseline != nil {
                menu.addItem(label(text.actualContext, text.percentOf(formatPercent(snapshot.usageRatio), formatTokens(snapshot.contextWindow))))
                menu.addItem(disabled(text.displayResetHint))
            }
        } else {
            menu.addItem(label(text.context, isLoading ? text.loading : text.waitingForTokenData))
        }

        menu.addItem(.separator())
        menu.addItem(sessionPickerItem(currentSessionID: snapshot?.session?.id, sessions: sessions, isLoading: isLoading))

        if let snapshot, !snapshot.warnings.isEmpty {
            menu.addItem(.separator())
            for warning in snapshot.warnings {
                menu.addItem(disabled(text.warning(warning)))
            }
        }

        menu.addItem(.separator())
        if let snapshot, !snapshot.categories.isEmpty {
            for category in snapshot.categories {
                menu.addItem(categoryItem(category, total: max(snapshot.estimatedCategoryTokens, 1)))
            }
        } else {
            menu.addItem(disabled(isLoading ? text.loadingBreakdown : text.noBreakdownAvailableYet))
        }

        menu.addItem(.separator())
        let dashboardItem = NSMenuItem(title: text.openDashboard, action: #selector(openDashboard), keyEquivalent: "o")
        dashboardItem.target = self
        menu.addItem(dashboardItem)
        menu.addItem(themePickerItem())
        menu.addItem(updateMenuItem())

        if snapshot?.session != nil {
            let compressItem = NSMenuItem(title: text.compressCurrentSession, action: #selector(compressCurrentSession), keyEquivalent: "")
            compressItem.target = self
            compressItem.isEnabled = compressionStatus != .compressing
            menu.addItem(compressItem)

            let resetDisplayBaselineItem = NSMenuItem(title: text.resetDisplayBaseline, action: #selector(resetDisplayBaselineNow), keyEquivalent: "")
            resetDisplayBaselineItem.target = self
            menu.addItem(resetDisplayBaselineItem)
        }

        if let sessionID = snapshot?.session?.id, displayBaselines[sessionID] != nil {
            let undoDisplayBaselineResetItem = NSMenuItem(title: text.undoDisplayBaselineReset, action: #selector(undoDisplayBaselineReset), keyEquivalent: "")
            undoDisplayBaselineResetItem.target = self
            menu.addItem(undoDisplayBaselineResetItem)
        }

        if let path = snapshot?.session?.path.path {
            let openItem = NSMenuItem(title: text.revealSessionFile, action: #selector(revealSessionFile), keyEquivalent: "")
            openItem.target = self
            openItem.representedObject = path
            menu.addItem(openItem)
        }

        menu.addItem(NSMenuItem(title: text.quit, action: #selector(quit), keyEquivalent: "q"))
        menu.items.last?.target = self
        return menu
    }

    private func themePickerItem() -> NSMenuItem {
        let item = NSMenuItem(title: text.theme, action: nil, keyEquivalent: "")
        let submenu = NSMenu()

        for theme in AppThemeChoice.menuChoices {
            let themeItem = NSMenuItem(title: theme.displayName(text), action: #selector(selectThemeFromMenu(_:)), keyEquivalent: "")
            themeItem.target = self
            themeItem.representedObject = theme.rawValue
            themeItem.state = theme == selectedTheme ? NSControl.StateValue.on : NSControl.StateValue.off
            submenu.addItem(themeItem)
        }

        item.submenu = submenu
        return item
    }

    private func updateMenuItem() -> NSMenuItem {
        let item = NSMenuItem(title: updateMenuTitle, action: updateMenuAction, keyEquivalent: "")
        item.target = self
        item.isEnabled = updateMenuAction != nil
        return item
    }

    private var updateMenuTitle: String {
        switch updateState {
        case .idle, .failed, .upToDate:
            text.checkForUpdates
        case .checking:
            text.checkingForUpdates
        case .available(let update):
            text.downloadUpdateVersion(update.version)
        case .downloading:
            text.downloadingUpdate
        case .downloaded:
            text.openInstaller
        }
    }

    private var updateMenuAction: Selector? {
        switch updateState {
        case .idle, .failed, .upToDate:
            #selector(checkForUpdatesFromMenu)
        case .available:
            #selector(installUpdate)
        case .downloaded:
            #selector(installUpdate)
        case .checking, .downloading:
            nil
        }
    }

    private func loadingSession() -> SessionChoice? {
        guard let id = loadingSessionID ?? selectedSessionID else {
            return recentSessions.first
        }
        return recentSessions.first { $0.id == id }
    }

    private func sessionPickerItem(currentSessionID: String?, sessions: [SessionChoice], isLoading: Bool) -> NSMenuItem {
        let item = NSMenuItem(title: text.sessions, action: nil, keyEquivalent: "")
        let submenu = NSMenu()

        let autoItem = NSMenuItem(title: text.autoLatestTitle, action: #selector(selectAutoLatest), keyEquivalent: "")
        autoItem.target = self
        autoItem.state = selectedSessionID == nil ? .on : .off
        submenu.addItem(autoItem)
        submenu.addItem(.separator())

        if sessions.isEmpty {
            submenu.addItem(disabled(isLoading ? text.loadingSessions : text.noSessionsFound))
        } else {
            for session in sessions {
                let title = sessionTitle(session)
                let sessionItem = NSMenuItem(title: title, action: #selector(selectSession(_:)), keyEquivalent: "")
                sessionItem.target = self
                sessionItem.representedObject = session.id
                sessionItem.state = session.id == (selectedSessionID ?? currentSessionID)
                    ? NSControl.StateValue.on
                    : NSControl.StateValue.off
                sessionItem.toolTip = [
                    session.cwd.map(abbreviateHome),
                    session.id,
                    session.path.path
                ].compactMap { $0 }.joined(separator: "\n")
                submenu.addItem(sessionItem)
            }
        }

        item.submenu = submenu
        return item
    }

    private func categoryItem(_ category: ContextCategory, total: Int) -> NSMenuItem {
        let ratio = Double(category.tokens) / Double(total)
        let item = NSMenuItem(title: "\(text.categoryName(category.kind))  \(formatTokens(category.tokens))  \(formatPercent(ratio))", action: nil, keyEquivalent: "")
        let submenu = NSMenu()

        let shown = category.items.prefix(20)
        for detail in shown {
            let count = detail.count > 1 ? " x\(detail.count)" : ""
            let title = "\(text.displayItemTitle(detail.title))\(count)  \(formatTokens(detail.tokens))"
            let child = NSMenuItem(title: title, action: nil, keyEquivalent: "")
            if let subtitle = detail.subtitle, !subtitle.isEmpty {
                child.toolTip = text.displayItemSubtitle(subtitle)
            }
            submenu.addItem(child)
        }

        if category.items.count > shown.count {
            submenu.addItem(.separator())
            submenu.addItem(disabled(text.moreItems(category.items.count - shown.count)))
        }

        item.submenu = submenu
        return item
    }

    private func contextLine(_ snapshot: ContextSnapshot) -> String {
        guard snapshot.contextWindow > 0 else {
            return text.waitingForTokenData
        }
        let usage = text.percentOf(formatPercent(snapshot.displayUsageRatio), formatTokens(snapshot.contextWindow))
        return snapshot.baseline == nil ? usage : "\(text.sinceDisplayBaseline): \(usage)"
    }

    private func displayContextTitle(_ snapshot: ContextSnapshot) -> String {
        snapshot.baseline == nil ? text.context : text.displayContextUsed
    }

    private func displayInputTitle(_ snapshot: ContextSnapshot) -> String {
        snapshot.baseline == nil ? text.lastInput : text.displayedInput
    }

    private func displayCachedInputTitle(_ snapshot: ContextSnapshot) -> String {
        snapshot.baseline == nil ? text.cachedInput : text.displayedCachedInput
    }

    private func displayRunTotalTitle(_ snapshot: ContextSnapshot) -> String {
        snapshot.baseline == nil ? text.runTotal : text.displayedRunTotal
    }

    private func header(_ title: String) -> NSMenuItem {
        let item = disabled(title)
        item.attributedTitle = NSAttributedString(
            string: title,
            attributes: [
                .font: NSFont.boldSystemFont(ofSize: NSFont.systemFontSize),
                .foregroundColor: NSColor.labelColor
            ]
        )
        return item
    }

    private func label(_ title: String, _ value: String) -> NSMenuItem {
        disabled("\(title): \(value)")
    }

    private func disabled(_ title: String) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        item.isEnabled = false
        return item
    }

    private func formatPercent(_ value: Double) -> String {
        "\(Int((value * 100).rounded()))%"
    }

    private func formatTokens(_ value: Int) -> String {
        if value >= 1_000_000 {
            return String(format: "%.1fM", Double(value) / 1_000_000)
        }
        if value >= 1_000 {
            return String(format: "%.1fk", Double(value) / 1_000)
        }
        return "\(value)"
    }

    private func relativeDate(_ date: Date) -> String {
        relativeDateFormatter.localizedString(for: date, relativeTo: Date())
    }

    private func shortID(_ id: String) -> String {
        String(id.prefix(8))
    }

    private func sessionTitle(_ session: SessionChoice) -> String {
        let name = session.name ?? shortID(session.id)
        return "\(name)  \(relativeDate(session.updatedAt))"
    }

    private func abbreviateHome(_ path: String) -> String {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        if path.hasPrefix(home) {
            return "~" + path.dropFirst(home.count)
        }
        return path
    }

    private func loadDisplayBaselines() -> [String: ContextBaseline] {
        guard let data = UserDefaults.standard.data(forKey: displayBaselinesKey),
              let baselines = try? JSONDecoder().decode([String: ContextBaseline].self, from: data) else {
            return [:]
        }
        return baselines
    }

    private func saveDisplayBaselines() {
        guard let data = try? JSONEncoder().encode(displayBaselines) else {
            return
        }
        UserDefaults.standard.set(data, forKey: displayBaselinesKey)
    }

    private func lineCount(for url: URL) -> Int {
        guard let text = try? String(contentsOf: url, encoding: .utf8) else {
            return 0
        }
        return text.split(separator: "\n", omittingEmptySubsequences: true).count
    }

    @objc private func refreshFromTimer() {
        refresh(showLoading: false, priority: .utility)
    }

    @objc private func resetDisplayBaselineNow() {
        guard let snapshot = lastSnapshot,
              let session = snapshot.session else {
            return
        }

        displayBaselines[session.id] = ContextBaseline(
            sessionID: session.id,
            lineCount: lineCount(for: session.path),
            lastInputTokens: snapshot.lastInputTokens,
            cachedInputTokens: snapshot.cachedInputTokens,
            totalRunTokens: snapshot.totalRunTokens,
            baselineSetAt: Date()
        )
        saveDisplayBaselines()
        refresh(showLoading: true, priority: .userInitiated)
    }

    @objc private func undoDisplayBaselineReset() {
        guard let sessionID = lastSnapshot?.session?.id else {
            return
        }
        displayBaselines.removeValue(forKey: sessionID)
        saveDisplayBaselines()
        refresh(showLoading: true, priority: .userInitiated)
    }

    @objc private func compressCurrentSession() {
        guard compressionStatus != .compressing else {
            return
        }
        guard let session = snapshotForCurrentSelection()?.session ?? lastSnapshot?.session else {
            compressionStatus = .failed(text.noActiveUserSessionFound)
            updateMenu(isLoading: showsLoadingState || refreshInProgress)
            syncDashboardState(isLoading: showsLoadingState || refreshInProgress)
            return
        }

        compressionTask?.cancel()
        compressionStatus = .compressing
        updateMenu(isLoading: showsLoadingState || refreshInProgress)
        syncDashboardState(isLoading: showsLoadingState || refreshInProgress)

        compressionTask = Task.detached(priority: .userInitiated) {
            let result: Result<SessionCompressionDraft, Error>
            do {
                result = .success(try SessionCompressor().compress(session: session))
            } catch {
                result = .failure(error)
            }

            guard !Task.isCancelled else {
                return
            }

            await MainActor.run {
                self.applyCompressionResult(result)
            }
        }
    }

    @objc private func checkForUpdatesFromMenu() {
        checkForUpdates(showUpToDate: true, showFailure: true)
    }

    private func checkForUpdates(showUpToDate: Bool, showFailure: Bool) {
        guard updateState != .checking, !updateState.isDownloading else {
            return
        }

        updateTask?.cancel()
        updateState = .checking
        updateMenu(isLoading: showsLoadingState || refreshInProgress)
        syncDashboardState(isLoading: showsLoadingState || refreshInProgress)

        let currentVersion = currentAppVersion
        updateTask = Task.detached(priority: .userInitiated) {
            let result: Result<AppUpdate?, Error>
            do {
                result = .success(try await AppUpdater().latestUpdate(currentVersion: currentVersion))
            } catch {
                result = .failure(error)
            }

            guard !Task.isCancelled else {
                return
            }

            await MainActor.run {
                switch result {
                case .success(let update?):
                    self.updateState = .available(update)
                case .success(nil):
                    self.updateState = showUpToDate ? .upToDate(Date()) : .idle
                case .failure(let error):
                    self.updateState = showFailure ? .failed(self.updateErrorMessage(error)) : .idle
                }

                self.updateMenu(isLoading: self.showsLoadingState || self.refreshInProgress)
                self.syncDashboardState(isLoading: self.showsLoadingState || self.refreshInProgress)
            }
        }
    }

    @objc private func installUpdate() {
        switch updateState {
        case .available(let update):
            downloadAndOpen(update)
        case .downloaded(_, let url):
            NSWorkspace.shared.open(url)
        default:
            break
        }
    }

    private func downloadAndOpen(_ update: AppUpdate) {
        guard !updateState.isDownloading else {
            return
        }

        updateTask?.cancel()
        updateState = .downloading(update)
        updateMenu(isLoading: showsLoadingState || refreshInProgress)
        syncDashboardState(isLoading: showsLoadingState || refreshInProgress)

        updateTask = Task.detached(priority: .userInitiated) {
            let result: Result<URL, Error>
            do {
                result = .success(try await AppUpdater().download(update))
            } catch {
                result = .failure(error)
            }

            guard !Task.isCancelled else {
                return
            }

            await MainActor.run {
                switch result {
                case .success(let url):
                    self.updateState = .downloaded(update, url)
                    NSWorkspace.shared.open(url)
                case .failure(let error):
                    self.updateState = .failed(self.updateErrorMessage(error))
                }

                self.updateMenu(isLoading: self.showsLoadingState || self.refreshInProgress)
                self.syncDashboardState(isLoading: self.showsLoadingState || self.refreshInProgress)
            }
        }
    }

    @objc private func openUpdateRelease() {
        guard let update = updateState.update else {
            return
        }
        NSWorkspace.shared.open(update.releaseURL)
    }

    private var currentAppVersion: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0.1.4"
    }

    private func updateErrorMessage(_ error: Error) -> String {
        (error as? LocalizedError)?.errorDescription ?? String(describing: error)
    }

    private func applyCompressionResult(_ result: Result<SessionCompressionDraft, Error>) {
        switch result {
        case .success(let draft):
            let rendered = CompressionRenderer(text: text).render(draft)
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(rendered, forType: .string)
            compressionStatus = .copied(Date(), TokenEstimator.estimate(rendered))
        case .failure(let error):
            let message = (error as? LocalizedError)?.errorDescription ?? String(describing: error)
            compressionStatus = .failed(message)
        }
        updateMenu(isLoading: showsLoadingState || refreshInProgress)
        syncDashboardState(isLoading: showsLoadingState || refreshInProgress)
    }

    @objc private func selectAutoLatest() {
        selectedSessionID = nil
        loadingSessionID = nil
        compressionStatus = nil
        UserDefaults.standard.removeObject(forKey: selectedSessionKey)
        updateMenu(isLoading: true)
        refresh(showLoading: true, priority: .userInitiated)
    }

    @objc private func selectSession(_ sender: NSMenuItem) {
        guard let id = sender.representedObject as? String else {
            return
        }
        selectSession(id: id)
    }

    private func selectSession(id: String) {
        selectedSessionID = id
        loadingSessionID = id
        compressionStatus = nil
        UserDefaults.standard.set(id, forKey: selectedSessionKey)
        updateMenu(isLoading: true)
        refresh(showLoading: true, priority: .userInitiated)
    }

    @objc private func revealSessionFile(_ sender: NSMenuItem) {
        guard let path = sender.representedObject as? String else {
            return
        }
        NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: path)])
    }

    @objc private func selectThemeFromMenu(_ sender: NSMenuItem) {
        guard let rawValue = sender.representedObject as? String,
              let theme = AppThemeChoice(rawValue: rawValue) else {
            return
        }
        selectTheme(theme)
    }

    private func selectTheme(_ theme: AppThemeChoice) {
        selectedTheme = theme
        theme.save()
        applyThemeToWindow()
        updateMenu(isLoading: showsLoadingState || refreshInProgress)
        syncDashboardState(isLoading: showsLoadingState || refreshInProgress)
    }

    private func applyThemeToWindow() {
        dashboardWindow?.appearance = selectedTheme.windowAppearance
    }

    @objc private func quit() {
        NSApp.terminate(nil)
    }

    @objc private func openDashboard() {
        showDashboard()
    }

    private func showDashboard() {
        if dashboardWindow == nil {
            let rootView = DashboardView(state: dashboardState)
            let hostingView = NSHostingView(rootView: rootView)
            let window = NSWindow(
                contentRect: NSRect(x: 0, y: 0, width: 1180, height: 760),
                styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
                backing: .buffered,
                defer: false
            )
            window.title = text.windowTitle
            window.titlebarAppearsTransparent = true
            window.isReleasedWhenClosed = false
            window.contentMinSize = NSSize(width: 980, height: 640)
            window.appearance = selectedTheme.windowAppearance
            window.contentView = hostingView
            window.center()
            dashboardWindow = window
        }

        dashboardWindow?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        syncDashboardState(isLoading: showsLoadingState || refreshInProgress)
    }

    nonisolated private static func submitContextUsageNotification(
        title: String,
        body: String,
        sessionID: String
    ) async -> Bool {
        let center = UNUserNotificationCenter.current()
        let settings = await center.notificationSettings()

        let isAuthorized: Bool
        switch settings.authorizationStatus {
        case .authorized, .provisional:
            isAuthorized = true
        case .notDetermined:
            isAuthorized = (try? await center.requestAuthorization(options: [.alert])) == true
        default:
            isAuthorized = false
        }

        guard isAuthorized else {
            return false
        }

        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.threadIdentifier = "codex-context-usage"

        let request = UNNotificationRequest(
            identifier: "codex-context-usage-\(sessionID)-\(UUID().uuidString)",
            content: content,
            trigger: nil
        )

        do {
            try await center.add(request)
            return true
        } catch {
            return false
        }
    }

    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification
    ) async -> UNNotificationPresentationOptions {
        [.banner, .list]
    }
}

private extension AppUpdateState {
    var isDownloading: Bool {
        if case .downloading = self {
            return true
        }
        return false
    }

    var update: AppUpdate? {
        switch self {
        case .available(let update), .downloading(let update), .downloaded(let update, _):
            update
        case .idle, .checking, .upToDate, .failed:
            nil
        }
    }
}

private struct RefreshResult: Sendable {
    let snapshot: ContextSnapshot
    let recentSessions: [SessionChoice]
}

private enum RefreshLoader {
    static func load(
        selectedSessionID: String?,
        displayBaselines: [String: ContextBaseline],
        cachedSessions: [SessionChoice],
        menuSessionLimit: Int
    ) -> RefreshResult {
        let analyzer = ContextAnalyzer()
        let loadedSessions = analyzer.recentSessions(limit: menuSessionLimit)
        let menuSessions = loadedSessions.isEmpty ? cachedSessions : loadedSessions
        let session: SessionChoice?

        if let selectedSessionID, !selectedSessionID.isEmpty {
            session = cachedSessions.first { $0.id == selectedSessionID }
                ?? menuSessions.first { $0.id == selectedSessionID }
        } else {
            session = menuSessions.first
        }

        let snapshot: ContextSnapshot
        if let session {
            do {
                snapshot = try analyzer.snapshot(
                    for: session,
                    baseline: displayBaselines[session.id]
                )
            } catch {
                snapshot = analyzer.snapshot(sessionID: selectedSessionID, baseline: selectedSessionID.flatMap { displayBaselines[$0] })
            }
        } else {
            snapshot = analyzer.snapshot(sessionID: selectedSessionID, baseline: selectedSessionID.flatMap { displayBaselines[$0] })
        }

        return RefreshResult(snapshot: snapshot, recentSessions: menuSessions)
    }
}

struct CompressionRenderer {
    let text: AppText

    func render(_ draft: SessionCompressionDraft) -> String {
        var lines: [String] = []
        lines.append(text.compressionDocumentTitle)
        lines.append("")
        lines.append(text.compressionDocumentIntro)
        lines.append("")
        lines.append("## \(text.compressionSectionSession)")
        lines.append("- \(text.session): \(draft.session.name ?? shortID(draft.session.id))")
        lines.append("- ID: \(draft.session.id)")
        if let cwd = draft.session.cwd {
            lines.append("- \(text.workspace): \(abbreviateHome(cwd))")
        }
        lines.append("- \(text.compressionSourceLines): \(draft.sourceLineCount)")
        lines.append("- \(text.compressionSourceTokens): \(formatTokens(draft.sourceTokenEstimate))")
        if draft.contextWindow > 0 {
            lines.append("- \(text.contextWindow): \(formatTokens(draft.contextWindow))")
        }
        if draft.lastInputTokens > 0 {
            lines.append("- \(text.actualContextUsed): \(formatTokens(draft.lastInputTokens))")
        }
        lines.append("")

        appendMessages(
            title: text.compressionSectionLatestUserRequests,
            empty: text.compressionNoLatestUserRequests,
            messages: draft.latestUserMessages,
            into: &lines
        )
        lines.append("")

        appendMessages(
            title: text.compressionSectionRecentConversation,
            empty: text.compressionNoRecentConversation,
            messages: draft.recentMessages,
            omittedCount: draft.omittedMessageCount,
            into: &lines
        )
        lines.append("")

        lines.append("## \(text.compressionSectionReferencedFiles)")
        if draft.referencedFiles.isEmpty {
            lines.append("- \(text.compressionNoReferencedFiles)")
        } else {
            for file in draft.referencedFiles {
                lines.append("- `\(file)`")
            }
        }
        lines.append("")

        lines.append("## \(text.compressionSectionRecentToolActivity)")
        if draft.recentToolActivities.isEmpty {
            lines.append("- \(text.compressionNoToolActivity)")
        } else {
            for activity in draft.recentToolActivities {
                lines.append("- \(activity.title): \(singleLine(activity.detail))")
            }
            if draft.omittedToolActivityCount > 0 {
                lines.append("- \(text.compressionOmittedToolActivities(draft.omittedToolActivityCount))")
            }
        }

        return lines.joined(separator: "\n")
    }

    private func appendMessages(
        title: String,
        empty: String,
        messages: [CompressedMessage],
        omittedCount: Int = 0,
        into lines: inout [String]
    ) {
        lines.append("## \(title)")
        guard !messages.isEmpty else {
            lines.append("- \(empty)")
            return
        }

        for message in messages {
            lines.append("- \(text.compressionRoleName(message.role)): \(singleLine(message.text))")
        }
        if omittedCount > 0 {
            lines.append("- \(text.compressionOmittedMessages(omittedCount))")
        }
    }

    private func singleLine(_ value: String) -> String {
        value
            .split(whereSeparator: \.isNewline)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .joined(separator: " / ")
    }

    private func formatTokens(_ value: Int) -> String {
        if value >= 1_000_000 {
            return String(format: "%.1fM", Double(value) / 1_000_000)
        }
        if value >= 1_000 {
            return String(format: "%.1fk", Double(value) / 1_000)
        }
        return "\(value)"
    }

    private func shortID(_ id: String) -> String {
        String(id.prefix(8))
    }

    private func abbreviateHome(_ path: String) -> String {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        if path.hasPrefix(home) {
            return "~" + path.dropFirst(home.count)
        }
        return path
    }
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.run()
