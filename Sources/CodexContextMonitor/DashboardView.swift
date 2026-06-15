import AppKit
import CodexContextCore
import SwiftUI

@MainActor
final class DashboardState: ObservableObject {
    @Published var snapshot: ContextSnapshot?
    @Published var sessions: [SessionChoice] = []
    @Published var isLoading = false
    @Published var selectedSessionID: String?
    @Published var loadingSessionID: String?
    @Published var displayBaselines: [String: ContextBaseline] = [:]
    @Published var compressionStatus: CompressionStatus?
    @Published var updateState: AppUpdateState = .idle
    var onResetDisplayBaseline: (() -> Void)?
    var onUndoDisplayBaselineReset: (() -> Void)?
    var onSelectSession: ((String) -> Void)?
    var onSelectAutoLatest: (() -> Void)?
    var onCompress: (() -> Void)?
    var onCheckForUpdates: (() -> Void)?
    var onInstallUpdate: (() -> Void)?
    var onOpenUpdateRelease: (() -> Void)?

    func resetDisplayBaseline() {
        onResetDisplayBaseline?()
    }

    func undoDisplayBaselineReset() {
        onUndoDisplayBaselineReset?()
    }

    func selectSession(_ id: String) {
        onSelectSession?(id)
    }

    func selectAutoLatest() {
        onSelectAutoLatest?()
    }

    func compressCurrentSession() {
        onCompress?()
    }

    func checkForUpdates() {
        onCheckForUpdates?()
    }

    func installUpdate() {
        onInstallUpdate?()
    }

    func openUpdateRelease() {
        onOpenUpdateRelease?()
    }
}

enum CompressionStatus: Equatable {
    case compressing
    case copied(Date, Int)
    case failed(String)
}

struct DashboardView: View {
    @ObservedObject var state: DashboardState
    @State private var hoveredSegmentID: String?
    @State private var selectedCategoryID: String?
    private let text = AppText.current

    var body: some View {
        GeometryReader { proxy in
            HStack(spacing: 0) {
                sessionRail(width: max(232, min(280, proxy.size.width * 0.23)))

                Divider()

                ScrollView {
                    VStack(alignment: .leading, spacing: 22) {
                        header
                        compressionBanner
                        updateBanner
                        metricStrip
                        chartSection
                    }
                    .padding(.horizontal, 28)
                    .padding(.top, 26)
                    .padding(.bottom, 28)
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .background(Color.dashboardBackground)
            }
            .frame(width: proxy.size.width, height: proxy.size.height)
            .background(Color.dashboardBackground)
            .onChange(of: state.snapshot?.session?.id) { _, _ in
                selectedCategoryID = nil
            }
        }
        .frame(minWidth: 980, minHeight: 640)
    }

    private var header: some View {
        HStack(alignment: .top, spacing: 18) {
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 10) {
                    Text(sessionName)
                        .font(.system(size: 24, weight: .semibold))
                        .foregroundStyle(Color.primaryText)
                        .lineLimit(1)

                    autoRefreshStatus

                }

                Label(workspaceLine, systemImage: "folder")
                    .font(.system(size: 13, weight: .regular))
                    .foregroundStyle(Color.secondaryText)
                    .lineLimit(1)
            }

            Spacer()

            HStack(spacing: 12) {
                Label(updatedLine, systemImage: "clock")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(Color.secondaryText)

                Button {
                    state.compressCurrentSession()
                } label: {
                    Text(compressButtonTitle)
                        .lineLimit(1)
                        .fixedSize(horizontal: true, vertical: false)
                }
                .buttonStyle(PrimaryToolbarButtonStyle())
                .disabled(state.snapshot?.session == nil || state.compressionStatus == .compressing)

                Button {
                    state.resetDisplayBaseline()
                } label: {
                    Text(text.resetDisplayBaselineShort)
                        .lineLimit(1)
                        .fixedSize(horizontal: true, vertical: false)
                }
                .buttonStyle(SecondaryToolbarButtonStyle())
                .disabled(state.snapshot?.session == nil)
            }
        }
    }

    @ViewBuilder
    private var compressionBanner: some View {
        if let status = state.compressionStatus {
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: compressionStatusSymbol(status))
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(compressionStatusColor(status))
                    .frame(width: 18)

                VStack(alignment: .leading, spacing: 4) {
                    Text(compressionStatusTitle(status))
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(Color.primaryText)

                    Text(compressionStatusDetail(status))
                        .font(.system(size: 12))
                        .foregroundStyle(Color.secondaryText)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(compressionStatusColor(status).opacity(0.09), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .stroke(compressionStatusColor(status).opacity(0.28), lineWidth: 1)
            )
        }
    }

    @ViewBuilder
    private var updateBanner: some View {
        switch state.updateState {
        case .idle:
            EmptyView()
        case .checking:
            statusBanner(
                symbol: "arrow.triangle.2.circlepath",
                color: .blueAccent,
                title: text.updateCheckingTitle,
                detail: text.updateCheckingDetail
            )
        case .upToDate(let date):
            statusBanner(
                symbol: "checkmark.circle.fill",
                color: .greenAccent,
                title: text.updateUpToDateTitle,
                detail: text.updateUpToDateDetail(formattedTime(date))
            )
        case .available(let update):
            statusBanner(
                symbol: "arrow.down.circle.fill",
                color: .blueAccent,
                title: text.updateAvailableTitle(update.version),
                detail: text.updateAvailableDetail(update.assetName),
                primaryActionTitle: text.downloadAndOpenUpdate,
                primaryAction: state.installUpdate,
                secondaryActionTitle: text.viewRelease,
                secondaryAction: state.openUpdateRelease
            )
        case .downloading(let update):
            statusBanner(
                symbol: "arrow.down.circle",
                color: .blueAccent,
                title: text.updateDownloadingTitle,
                detail: text.updateDownloadingDetail(update.assetName)
            )
        case .downloaded(let update, let url):
            statusBanner(
                symbol: "checkmark.circle.fill",
                color: .greenAccent,
                title: text.updateDownloadedTitle(update.version),
                detail: text.updateDownloadedDetail(url.lastPathComponent),
                primaryActionTitle: text.openInstaller,
                primaryAction: state.installUpdate
            )
        case .failed(let message):
            statusBanner(
                symbol: "exclamationmark.triangle.fill",
                color: .redAccent,
                title: text.updateFailedTitle,
                detail: text.updateFailedDetail(message),
                primaryActionTitle: text.checkForUpdates,
                primaryAction: state.checkForUpdates
            )
        }
    }

    private func statusBanner(
        symbol: String,
        color: Color,
        title: String,
        detail: String,
        primaryActionTitle: String? = nil,
        primaryAction: (() -> Void)? = nil,
        secondaryActionTitle: String? = nil,
        secondaryAction: (() -> Void)? = nil
    ) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: symbol)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(color)
                .frame(width: 18)

            VStack(alignment: .leading, spacing: 8) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(title)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(Color.primaryText)

                    Text(detail)
                        .font(.system(size: 12))
                        .foregroundStyle(Color.secondaryText)
                        .fixedSize(horizontal: false, vertical: true)
                }

                if primaryActionTitle != nil || secondaryActionTitle != nil {
                    HStack(spacing: 8) {
                        if let primaryActionTitle, let primaryAction {
                            Button(primaryActionTitle, action: primaryAction)
                                .buttonStyle(SecondaryToolbarButtonStyle())
                        }

                        if let secondaryActionTitle, let secondaryAction {
                            Button(secondaryActionTitle, action: secondaryAction)
                                .buttonStyle(SecondaryToolbarButtonStyle())
                        }
                    }
                }
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(color.opacity(0.09), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(color.opacity(0.28), lineWidth: 1)
        )
    }

    private var metricStrip: some View {
        HStack(spacing: 0) {
            metricCard(
                title: text.actualContextUsed,
                value: formatTokens(snapshot?.lastInputTokens ?? 0),
                suffix: text.tokenUnitSuffix,
                detail: actualUsageDetail
            )

            metricDivider

            metricCard(
                title: text.displayContextUsed,
                value: formatTokens(snapshot?.displayInputTokens ?? 0),
                suffix: text.tokenUnitSuffix,
                detail: displayUsageDetail
            )

            metricDivider

            metricCard(
                title: text.contextWindow,
                value: formatTokens(snapshot?.contextWindow ?? 0),
                suffix: text.tokenUnitSuffix,
                detail: windowDetail
            )

            metricDivider

            metricCard(
                title: text.cachedInput,
                value: formatTokens(snapshot?.displayCachedInputTokens ?? 0),
                suffix: text.tokenUnitSuffix,
                detail: cachedInputDetail
            )
        }
        .padding(.vertical, 16)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(Color.panelBackground)
                .shadow(color: .black.opacity(0.05), radius: 14, x: 0, y: 7)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(Color.hairline, lineWidth: 1)
        )
    }

    private var chartSection: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(alignment: .top, spacing: 28) {
                VStack(spacing: 16) {
                    ZStack {
                        DonutChartView(
                            segments: activeSegments,
                            hoveredID: $hoveredSegmentID,
                            selectedID: selectedSegmentID,
                            centerTitle: centerTitle,
                            centerSubtitle: centerSubtitle
                        ) { segment in
                            selectedCategoryID = segment.id
                        }
                        .frame(width: 382, height: 382)

                        if activeSegments.isEmpty {
                            emptyChart
                        }
                    }

                    usageStatusHint
                }
                .frame(maxWidth: 430)
                .frame(height: 446, alignment: .top)

                chartLegend
            }
        }
    }

    private var usageStatusHint: some View {
        HStack(alignment: .top, spacing: 10) {
            if let usageStatus {
                Image(systemName: usageStatus.symbol)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(usageStatus.color)
                    .frame(width: 18)

                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 6) {
                        Text(usageStatus.title(text))
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(usageStatus.color)
                        Text(formatPercent(snapshot?.usageRatio ?? 0))
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(Color.secondaryText)
                            .monospacedDigit()
                    }

                    Text(usageStatus.message(text))
                        .font(.system(size: 12))
                        .foregroundStyle(Color.secondaryText)
                        .fixedSize(horizontal: false, vertical: true)

                    if snapshot?.baseline != nil {
                        Text(text.displayResetHint)
                            .font(.system(size: 12))
                            .foregroundStyle(Color.secondaryText)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            } else {
                Image(systemName: "info.circle")
                    .font(.system(size: 13))
                    .foregroundStyle(Color.secondaryText)
                    .frame(width: 18)
                Text(text.hoverOverviewHint)
                    .font(.system(size: 12))
                    .foregroundStyle(Color.secondaryText)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background((usageStatus?.color ?? Color.grayAccent).opacity(0.09), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke((usageStatus?.color ?? Color.hairline).opacity(0.28), lineWidth: 1)
        )
    }

    private var chartLegend: some View {
        Group {
            if let selectedCategory {
                selectedCategoryDetails(selectedCategory)
            } else {
                overviewLegend
            }
        }
        .frame(minWidth: 300, maxWidth: 380)
    }

    private var overviewLegend: some View {
        VStack(alignment: .leading, spacing: 13) {
            VStack(alignment: .leading, spacing: 6) {
                Text(text.overview)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(Color.primaryText)

                Text(text.overviewDescription)
                    .font(.system(size: 12))
                    .foregroundStyle(Color.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.bottom, 2)

            ForEach(activeSegments) { segment in
                Button {
                    selectedCategoryID = segment.id
                } label: {
                    HStack(spacing: 12) {
                        Circle()
                            .fill(segment.color)
                            .frame(width: 10, height: 10)

                        Text(segment.title)
                            .font(.system(size: 14, weight: hoveredSegmentID == segment.id ? .semibold : .regular))
                            .foregroundStyle(Color.primaryText)
                            .lineLimit(1)

                        Spacer(minLength: 16)

                        Text(formatTokens(segment.tokens))
                            .font(.system(size: 13, weight: .medium))
                            .foregroundStyle(Color.primaryText)
                            .monospacedDigit()

                        Text(formatPercent(segment.ratio))
                            .font(.system(size: 13, weight: .regular))
                            .foregroundStyle(Color.secondaryText)
                            .monospacedDigit()
                            .frame(width: 52, alignment: .trailing)

                        Image(systemName: "chevron.right")
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundStyle(Color.tertiaryText)
                    }
                    .padding(.vertical, 5)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .onHover { hovering in
                    hoveredSegmentID = hovering ? segment.id : nil
                }
            }
        }
    }

    private func selectedCategoryDetails(_ category: ContextCategory) -> some View {
        let total = max(snapshot?.estimatedCategoryTokens ?? 1, 1)
        let categoryRatio = Double(category.tokens) / Double(total)
        let shownItems = Array(category.items.prefix(10).enumerated())

        return VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .center, spacing: 10) {
                Button {
                    selectedCategoryID = nil
                } label: {
                    Label(text.backToOverview, systemImage: "chevron.left")
                }
                .buttonStyle(SecondaryToolbarButtonStyle())

                Spacer()
            }

            VStack(alignment: .leading, spacing: 7) {
                HStack(spacing: 9) {
                    Circle()
                        .fill(color(for: category.kind))
                        .frame(width: 11, height: 11)

                    Text(text.categoryName(category.kind))
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(Color.primaryText)
                        .lineLimit(1)

                    Spacer(minLength: 12)

                    Text(formatPercent(categoryRatio))
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(Color.primaryText)
                        .monospacedDigit()
                }

                HStack(spacing: 8) {
                    Text(text.tokenCount(formatTokens(category.tokens)))
                    Text(text.itemCount(category.items.count))
                }
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(Color.secondaryText)
            }

            VStack(alignment: .leading, spacing: 10) {
                Text(text.topContributors)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Color.secondaryText)
                    .textCase(.uppercase)

                if shownItems.isEmpty {
                    Text(text.noBreakdownAvailableYet)
                        .font(.system(size: 13))
                        .foregroundStyle(Color.secondaryText)
                } else {
                    ForEach(shownItems, id: \.offset) { _, item in
                        categoryDetailRow(item, category: category)
                    }

                    if category.items.count > shownItems.count {
                        Text(text.moreItems(category.items.count - shownItems.count))
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(Color.tertiaryText)
                            .padding(.top, 2)
                    }
                }
            }
        }
    }

    private func categoryDetailRow(_ item: ContextItem, category: ContextCategory) -> some View {
        let itemRatio = Double(item.tokens) / Double(max(category.tokens, 1))
        let count = item.count > 1 ? " x\(item.count)" : ""

        return VStack(alignment: .leading, spacing: 7) {
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                VStack(alignment: .leading, spacing: 3) {
                    Text("\(text.displayItemTitle(item.title))\(count)")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(Color.primaryText)
                        .lineLimit(1)

                    if let subtitle = text.displayItemSubtitle(item.subtitle), !subtitle.isEmpty {
                        Text(subtitle)
                            .font(.system(size: 11))
                            .foregroundStyle(Color.tertiaryText)
                            .lineLimit(1)
                    }
                }

                Spacer(minLength: 12)

                VStack(alignment: .trailing, spacing: 3) {
                    Text(formatTokens(item.tokens))
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(Color.primaryText)
                        .monospacedDigit()

                    Text(formatPercent(itemRatio))
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(Color.secondaryText)
                        .monospacedDigit()
                }
            }

            GeometryReader { proxy in
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(Color.hairline.opacity(0.7))
                    Capsule()
                        .fill(color(for: category.kind))
                        .frame(width: max(4, proxy.size.width * itemRatio))
                }
            }
            .frame(height: 4)
        }
        .padding(.vertical, 4)
    }

    private func sessionRail(width: CGFloat) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text(text.sessions)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(Color.secondaryText)
                    .textCase(.uppercase)
                Spacer()
            }

            if state.sessions.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    Text(state.isLoading ? text.loadingSessions : text.noSessionsFound)
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(Color.primaryText)
                    Text(text.localSessionFilesHere)
                        .font(.system(size: 12))
                        .foregroundStyle(Color.secondaryText)
                }
                .padding(14)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.panelBackground, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            } else {
                ScrollView {
                    VStack(spacing: 8) {
                        ForEach(state.sessions, id: \.id) { session in
                            sessionRow(session)
                        }
                    }
                    .padding(.vertical, 1)
                }
            }

            Spacer()
        }
        .padding(.horizontal, 18)
        .padding(.top, 26)
        .frame(width: width)
        .background(Color.railBackground)
    }

    private var autoRefreshStatus: some View {
        HStack(spacing: 8) {
            Circle()
                .fill(state.isLoading ? Color.amberAccent : Color.greenAccent)
                .frame(width: 8, height: 8)

            Text(state.isLoading ? text.refreshing : text.autoRefreshIsOn)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(Color.primaryText)
                .lineLimit(1)
        }
    }

    private func sessionRow(_ session: SessionChoice) -> some View {
        let isSelected = session.id == (state.selectedSessionID ?? snapshot?.session?.id)
        return Button {
            state.selectSession(session.id)
        } label: {
            HStack(alignment: .top, spacing: 12) {
                Circle()
                    .fill(isSelected ? Color.blueAccent : Color.gray.opacity(0.45))
                    .frame(width: 8, height: 8)
                    .padding(.top, 6)

                VStack(alignment: .leading, spacing: 5) {
                    Text(session.name ?? shortID(session.id))
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(Color.primaryText)
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)

                    Text(relativeDate(session.updatedAt))
                        .font(.system(size: 12))
                        .foregroundStyle(Color.secondaryText)
                }

                Spacer(minLength: 0)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(isSelected ? Color.blueSoft : Color.clear, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .stroke(isSelected ? Color.blueAccent.opacity(0.35) : Color.clear, lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }

    private var emptyChart: some View {
        VStack(spacing: 8) {
            Image(systemName: "chart.pie")
                .font(.system(size: 28, weight: .medium))
                .foregroundStyle(Color.secondaryText)
            Text(state.isLoading ? text.loadingContext : text.noBreakdownYet)
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(Color.secondaryText)
        }
    }

    private func metricCard(title: String, value: String, suffix: String, detail: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(Color.secondaryText)
                .textCase(.uppercase)
                .lineLimit(1)

            HStack(alignment: .firstTextBaseline, spacing: 5) {
                Text(value)
                    .font(.system(size: 21, weight: .semibold))
                    .foregroundStyle(Color.primaryText)
                    .monospacedDigit()
                    .lineLimit(1)
                if !suffix.isEmpty {
                    Text(suffix)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(Color.secondaryText)
                }
            }

            Text(detail)
                .font(.system(size: 13))
                .foregroundStyle(Color.secondaryText)
                .lineLimit(1)
        }
        .padding(.horizontal, 18)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var metricDivider: some View {
        Rectangle()
            .fill(Color.hairline)
            .frame(width: 1)
            .padding(.vertical, 4)
    }

    private var activeSegments: [ChartSegment] {
        let total = max(snapshot?.estimatedCategoryTokens ?? 1, 1)
        return (snapshot?.categories ?? []).map { category in
            ChartSegment(
                id: category.kind.rawValue,
                title: text.categoryName(category.kind),
                subtitle: text.itemCount(category.items.count),
                tokens: category.tokens,
                ratio: Double(category.tokens) / Double(total),
                color: color(for: category.kind),
                kind: category.kind,
                count: category.items.count
            )
        }
    }

    private var selectedCategory: ContextCategory? {
        guard let selectedCategoryID else {
            return nil
        }
        return snapshot?.categories.first { $0.kind.rawValue == selectedCategoryID }
    }

    private var selectedSegmentID: String? {
        selectedCategory?.kind.rawValue
    }

    private var centerTitle: String {
        return formatTokens(snapshot?.displayInputTokens ?? 0)
    }

    private var centerSubtitle: String {
        guard let snapshot else {
            return text.tokenUnitSuffix
        }
        return text.percentOf(formatPercent(snapshot.displayUsageRatio), formatTokens(snapshot.contextWindow))
    }

    private var snapshot: ContextSnapshot? {
        state.snapshot
    }

    private var compressButtonTitle: String {
        state.compressionStatus == .compressing ? text.compressingSession : text.compressCurrentSession
    }

    private var sessionName: String {
        snapshot?.session?.name ?? snapshot?.session.map { shortID($0.id) } ?? text.codexContext
    }

    private var workspaceLine: String {
        if let cwd = snapshot?.session?.cwd {
            return abbreviateHome(cwd)
        }
        return state.isLoading ? text.loadingWorkspace : text.noActiveUserSessionFound
    }

    private var updatedLine: String {
        guard let date = snapshot?.generatedAt else {
            return state.isLoading ? text.updating : text.notUpdated
        }
        return text.updatedAt(formattedTime(date))
    }

    private var actualUsageDetail: String {
        guard let snapshot, snapshot.contextWindow > 0 else {
            return text.waitingForTokenData
        }
        return text.percentOf(formatPercent(snapshot.usageRatio), formatTokens(snapshot.contextWindow))
    }

    private var displayUsageDetail: String {
        guard let snapshot, snapshot.contextWindow > 0 else {
            return text.waitingForTokenData
        }
        let detail = text.percentOf(formatPercent(snapshot.displayUsageRatio), formatTokens(snapshot.contextWindow))
        return snapshot.baseline == nil ? detail : "\(text.sinceDisplayBaseline): \(detail)"
    }

    private var windowDetail: String {
        guard let contextWindow = snapshot?.contextWindow, contextWindow > 0 else {
            return text.unknownMax
        }
        return "\(formatTokens(contextWindow)) \(text.maxSuffix)"
    }

    private var cachedInputDetail: String {
        guard let snapshot else {
            return text.waitingForTokenData
        }
        return text.percentOf(formatPercent(cacheHitRatio(snapshot)), formatTokens(snapshot.displayInputTokens))
    }

    private var cacheHitRateValue: String {
        guard let snapshot else {
            return text.notUpdated
        }
        return formatPercent(cacheHitRatio(snapshot))
    }

    private var cacheHitRateDetail: String {
        guard let snapshot else {
            return text.waitingForTokenData
        }
        return text.cacheHitRateDetail(formatTokens(snapshot.displayCachedInputTokens), formatTokens(snapshot.displayInputTokens))
    }

    private func cacheHitRatio(_ snapshot: ContextSnapshot) -> Double {
        guard snapshot.displayInputTokens > 0 else {
            return 0
        }
        return min(1, Double(snapshot.displayCachedInputTokens) / Double(snapshot.displayInputTokens))
    }

    private var usageStatus: ContextUsageStatus? {
        guard let snapshot, snapshot.contextWindow > 0 else {
            return nil
        }
        return ContextUsageStatus(ratio: snapshot.usageRatio)
    }

    private func color(for kind: ContextCategoryKind) -> Color {
        switch kind {
        case .instructions: .blueAccent
        case .skills: .violetAccent
        case .mcp: .greenAccent
        case .files: .orangeAccent
        case .messages: .coralAccent
        case .toolCalls: .tealAccent
        case .toolOutput: .steelAccent
        case .reasoning: .purpleAccent
        case .other: .grayAccent
        }
    }

    private func compressionStatusSymbol(_ status: CompressionStatus) -> String {
        switch status {
        case .compressing:
            "hourglass"
        case .copied:
            "checkmark.circle.fill"
        case .failed:
            "exclamationmark.triangle.fill"
        }
    }

    private func compressionStatusColor(_ status: CompressionStatus) -> Color {
        switch status {
        case .compressing:
            .blueAccent
        case .copied:
            .greenAccent
        case .failed:
            .redAccent
        }
    }

    private func compressionStatusTitle(_ status: CompressionStatus) -> String {
        switch status {
        case .compressing:
            text.compressionInProgressTitle
        case .copied:
            text.compressionCopiedTitle
        case .failed:
            text.compressionFailedTitle
        }
    }

    private func compressionStatusDetail(_ status: CompressionStatus) -> String {
        switch status {
        case .compressing:
            text.compressionInProgressDetail
        case .copied(let date, let tokenEstimate):
            text.compressionCopiedDetail(formatTokens(tokenEstimate), formattedTime(date))
        case .failed(let message):
            text.compressionFailedDetail(message)
        }
    }

}

private struct DonutChartView: View {
    let segments: [ChartSegment]
    @Binding var hoveredID: String?
    let selectedID: String?
    let centerTitle: String
    let centerSubtitle: String
    let onSelect: (ChartSegment) -> Void
    private let text = AppText.current

    var body: some View {
        GeometryReader { proxy in
            let size = min(proxy.size.width, proxy.size.height)
            let rect = CGRect(
                x: (proxy.size.width - size) / 2,
                y: (proxy.size.height - size) / 2,
                width: size,
                height: size
            )
            let ringWidth = size * 0.26
            let entries = chartEntries

            ZStack {
                ForEach(entries) { entry in
                    let isActive = entry.segment.id == hoveredID || entry.segment.id == selectedID
                    DonutSlice(startAngle: entry.startAngle, endAngle: entry.endAngle, inset: ringWidth)
                        .fill(entry.segment.color)
                        .scaleEffect(isActive ? 1.055 : 1.0, anchor: .center)
                        .shadow(color: isActive ? entry.segment.color.opacity(0.26) : .clear, radius: 10, x: 0, y: 5)
                        .animation(.spring(response: 0.24, dampingFraction: 0.78), value: hoveredID)
                        .overlay(
                            DonutSlice(startAngle: entry.startAngle, endAngle: entry.endAngle, inset: ringWidth)
                                .stroke(Color.white.opacity(0.95), lineWidth: 1.2)
                        )

                    sliceLabel(for: entry, in: rect, ringWidth: ringWidth)
                }

                Circle()
                    .fill(Color.panelBackground)
                    .frame(width: size * 0.45, height: size * 0.45)
                    .shadow(color: .black.opacity(0.06), radius: 7, x: 0, y: 2)

                VStack(spacing: 4) {
                    Text(centerTitle)
                        .font(.system(size: 27, weight: .semibold))
                        .foregroundStyle(Color.primaryText)
                        .monospacedDigit()
                        .lineLimit(1)
                        .minimumScaleFactor(0.78)
                    Text(centerSubtitle)
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(Color.secondaryText)
                        .lineLimit(1)
                }
                .frame(width: size * 0.36)

                if let hovered = entries.first(where: { $0.segment.id == hoveredID }) {
                    tooltip(for: hovered.segment)
                        .offset(x: size * 0.18, y: size * 0.28)
                        .transition(.opacity.combined(with: .scale(scale: 0.96)))
                }

                interactionSurface(in: rect, ringWidth: ringWidth, entries: entries)
            }
        }
    }

    private var chartEntries: [ChartEntry] {
        let totalRatio = segments.reduce(0) { $0 + $1.ratio }
        guard totalRatio > 0 else {
            return []
        }

        var start = Angle.degrees(-90)
        return segments.enumerated().map { index, segment in
            let normalizedRatio = segment.ratio / totalRatio
            let end = index == segments.count - 1 ? Angle.degrees(270) : start + Angle.degrees(normalizedRatio * 360)
            let entry = ChartEntry(
                segment: segment,
                startAngle: start,
                endAngle: end,
                normalizedStartDegrees: normalizedDegrees(start.degrees),
                normalizedEndDegrees: normalizedDegrees(end.degrees)
            )
            start = end
            return entry
        }
    }

    private func segment(at point: CGPoint, in rect: CGRect, ringWidth: CGFloat, entries: [ChartEntry]) -> ChartSegment? {
        guard !entries.isEmpty else {
            return nil
        }

        let center = CGPoint(x: rect.midX, y: rect.midY)
        let outerRadius = rect.width / 2
        let innerRadius = max(0, outerRadius - ringWidth)
        let dx = point.x - center.x
        let dy = point.y - center.y
        let distance = sqrt(dx * dx + dy * dy)

        guard distance >= innerRadius, distance <= outerRadius else {
            return nil
        }

        let degrees = normalizedDegrees(atan2(dy, dx) * 180 / .pi)
        return entries.first { $0.contains(normalizedDegrees: degrees) }?.segment
    }

    private func interactionSurface(in rect: CGRect, ringWidth: CGFloat, entries: [ChartEntry]) -> some View {
        let hitRect = CGRect(origin: .zero, size: rect.size)
        return Color.clear
            .frame(width: rect.width, height: rect.height)
            .contentShape(Rectangle())
            .onContinuousHover { phase in
                switch phase {
                case .active(let location):
                    hoveredID = segment(at: location, in: hitRect, ringWidth: ringWidth, entries: entries)?.id
                case .ended:
                    hoveredID = nil
                }
            }
            .gesture(
                SpatialTapGesture()
                    .onEnded { value in
                        if let segment = segment(at: value.location, in: hitRect, ringWidth: ringWidth, entries: entries) {
                            onSelect(segment)
                        }
                    }
            )
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onEnded { value in
                        if let segment = segment(at: value.location, in: hitRect, ringWidth: ringWidth, entries: entries) {
                            onSelect(segment)
                        }
                    }
            )
            .position(x: rect.midX, y: rect.midY)
    }

    @ViewBuilder
    private func sliceLabel(for entry: ChartEntry, in rect: CGRect, ringWidth: CGFloat) -> some View {
        if entry.segment.ratio >= 0.045 {
            let angle = (entry.startAngle.radians + entry.endAngle.radians) / 2
            let radius = rect.width / 2 - ringWidth / 2
            let x = cos(angle) * radius
            let y = sin(angle) * radius

            Text(formatPercent(entry.segment.ratio))
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(Color.white)
                .shadow(color: .black.opacity(0.18), radius: 2, x: 0, y: 1)
                .position(x: rect.midX + x, y: rect.midY + y)
                .allowsHitTesting(false)
        }
    }

    private func tooltip(for segment: ChartSegment) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack(spacing: 8) {
                Circle()
                    .fill(segment.color)
                    .frame(width: 10, height: 10)
                Text(segment.title)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(Color.primaryText)
                    .lineLimit(1)
            }

            HStack(spacing: 10) {
                Text(formatPercent(segment.ratio))
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(Color.primaryText)
                Text(text.tokenCount(formatTokens(segment.tokens)))
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(Color.secondaryText)
            }

            Text(segment.subtitle ?? text.itemCount(segment.count))
                .font(.system(size: 12))
                .foregroundStyle(Color.secondaryText)
                .lineLimit(1)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .frame(width: 186, alignment: .leading)
        .background(Color.panelBackground)
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(Color.hairline, lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.16), radius: 18, x: 0, y: 8)
    }
}

private struct DonutSlice: Shape {
    let startAngle: Angle
    let endAngle: Angle
    let inset: CGFloat

    func path(in rect: CGRect) -> Path {
        let center = CGPoint(x: rect.midX, y: rect.midY)
        let radius = min(rect.width, rect.height) / 2
        let innerRadius = max(0, radius - inset)

        var path = Path()
        path.addArc(center: center, radius: radius, startAngle: startAngle, endAngle: endAngle, clockwise: false)
        path.addArc(center: center, radius: innerRadius, startAngle: endAngle, endAngle: startAngle, clockwise: true)
        path.closeSubpath()
        return path
    }
}

private struct ChartEntry: Identifiable {
    let id = UUID()
    let segment: ChartSegment
    let startAngle: Angle
    let endAngle: Angle
    let normalizedStartDegrees: Double
    let normalizedEndDegrees: Double

    func contains(normalizedDegrees degrees: Double) -> Bool {
        if normalizedStartDegrees <= normalizedEndDegrees {
            return degrees >= normalizedStartDegrees && degrees < normalizedEndDegrees
        }
        return degrees >= normalizedStartDegrees || degrees < normalizedEndDegrees
    }
}

private struct ChartSegment: Identifiable {
    let id: String
    let title: String
    let subtitle: String?
    let tokens: Int
    let ratio: Double
    let color: Color
    let kind: ContextCategoryKind?
    let count: Int
}

private enum ContextUsageStatus {
    case healthy
    case normal
    case heavy
    case highRisk

    init(ratio: Double) {
        if ratio <= 0.25 {
            self = .healthy
        } else if ratio <= 0.50 {
            self = .normal
        } else if ratio < 0.70 {
            self = .heavy
        } else {
            self = .highRisk
        }
    }

    var color: Color {
        switch self {
        case .healthy:
            .greenAccent
        case .normal:
            .blueAccent
        case .heavy:
            .amberAccent
        case .highRisk:
            .redAccent
        }
    }

    var symbol: String {
        switch self {
        case .healthy:
            "checkmark.circle.fill"
        case .normal:
            "circle.fill"
        case .heavy:
            "exclamationmark.triangle.fill"
        case .highRisk:
            "exclamationmark.octagon.fill"
        }
    }

    func title(_ text: AppText) -> String {
        switch self {
        case .healthy:
            text.contextUsageHealthyTitle
        case .normal:
            text.contextUsageNormalTitle
        case .heavy:
            text.contextUsageHeavyTitle
        case .highRisk:
            text.contextUsageHighRiskTitle
        }
    }

    func message(_ text: AppText) -> String {
        switch self {
        case .healthy:
            text.contextUsageHealthyMessage
        case .normal:
            text.contextUsageNormalMessage
        case .heavy:
            text.contextUsageHeavyMessage
        case .highRisk:
            text.contextUsageHighRiskMessage
        }
    }
}

private struct PrimaryToolbarButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 14, weight: .medium))
            .foregroundStyle(Color.primaryText)
            .padding(.horizontal, 14)
            .frame(height: 38)
            .background(configuration.isPressed ? Color.hairline : Color.panelBackground, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .stroke(Color.hairline, lineWidth: 1)
            )
    }
}

private struct SecondaryToolbarButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 13, weight: .medium))
            .foregroundStyle(Color.primaryText)
            .padding(.horizontal, 12)
            .frame(height: 34)
            .background(configuration.isPressed ? Color.hairline : Color.panelBackground, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .stroke(Color.hairline, lineWidth: 1)
            )
    }
}

private struct DestructiveToolbarButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 14, weight: .semibold))
            .foregroundStyle(Color.redAccent)
            .padding(.horizontal, 14)
            .frame(height: 38)
            .background(configuration.isPressed ? Color.redAccent.opacity(0.08) : Color.panelBackground, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .stroke(Color.redAccent.opacity(0.28), lineWidth: 1)
            )
    }
}

private struct IconButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 14, weight: .medium))
            .foregroundStyle(Color.secondaryText)
            .frame(width: 31, height: 31)
            .background(configuration.isPressed ? Color.hairline : Color.panelBackground, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .stroke(Color.hairline, lineWidth: 1)
            )
    }
}

private func formatPercent(_ value: Double) -> String {
    "\(Int((value * 100).rounded()))%"
}

private func normalizedDegrees(_ value: Double) -> Double {
    let remainder = value.truncatingRemainder(dividingBy: 360)
    return remainder < 0 ? remainder + 360 : remainder
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
    let formatter = RelativeDateTimeFormatter()
    formatter.unitsStyle = .short
    formatter.locale = AppText.current.locale
    return formatter.localizedString(for: date, relativeTo: Date())
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

private func formattedDate(_ date: Date) -> String {
    let formatter = DateFormatter()
    formatter.locale = AppText.current.locale
    formatter.dateStyle = .medium
    formatter.timeStyle = .short
    return formatter.string(from: date)
}

private func formattedTime(_ date: Date) -> String {
    let formatter = DateFormatter()
    formatter.locale = AppText.current.locale
    formatter.timeStyle = .medium
    return formatter.string(from: date)
}
