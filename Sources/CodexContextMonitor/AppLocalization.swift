import CodexContextCore
import Foundation

enum AppLanguage {
    case english
    case chinese

    static var current: AppLanguage {
        if Locale.preferredLanguages.first?.lowercased().hasPrefix("zh") == true {
            return .chinese
        }
        return .english
    }

    var locale: Locale {
        switch self {
        case .english:
            Locale(identifier: "en")
        case .chinese:
            Locale(identifier: "zh-Hans")
        }
    }
}

struct AppText {
    static let current = AppText(language: .current)

    let language: AppLanguage

    var locale: Locale {
        language.locale
    }

    func value(_ english: String, _ chinese: String) -> String {
        switch language {
        case .english:
            english
        case .chinese:
            chinese
        }
    }

    var codexContext: String { value("Codex Context", "Codex 上下文") }
    var windowTitle: String { value("Codex Context Manager", "Codex 上下文管理器") }
    var session: String { value("Session", "会话") }
    var mode: String { value("Mode", "模式") }
    var auto: String { value("Auto", "自动") }
    var pinned: String { value("Pinned", "固定") }
    var autoLatest: String { value("Auto latest", "自动最新") }
    var autoLatestTitle: String { value("Auto Latest", "自动最新") }
    var baselineSet: String { value("Display baseline set", "已设置显示基准") }
    var workspace: String { value("Workspace", "工作区") }
    var updated: String { value("Updated", "已更新") }
    var status: String { value("Status", "状态") }
    var loading: String { value("Loading", "正在加载") }
    var loadingSessionData: String { value("Loading session data", "正在加载会话资料") }
    var noActiveUserSessionFound: String { value("No active user session found", "未找到活跃的用户会话") }
    var context: String { value("Context", "上下文") }
    var lastInput: String { value("Last input", "上次输入") }
    var displayedInput: String { value("Displayed input", "显示输入") }
    var cachedInput: String { value("Cached input", "缓存输入") }
    var displayedCachedInput: String { value("Displayed cached input", "显示缓存输入") }
    var runTotal: String { value("Run total", "本次总量") }
    var displayedRunTotal: String { value("Displayed run total", "显示本次总量") }
    var actualContext: String { value("Actual context usage", "实际上下文用量") }
    var loadingBreakdown: String { value("Loading breakdown", "正在加载明细") }
    var noBreakdownAvailableYet: String { value("No breakdown available yet", "暂无明细") }
    var openDashboard: String { value("Open Dashboard", "打开面板") }
    var theme: String { value("Theme", "主题") }
    var lightTheme: String { value("Light", "浅色") }
    var darkTheme: String { value("Dark", "深色") }
    var resetDisplayBaseline: String { value("Reset Display Baseline", "重置显示基准") }
    var undoDisplayBaselineReset: String { value("Undo Display Baseline Reset", "撤销显示基准重置") }
    var revealSessionFile: String { value("Reveal Session File", "显示会话文件") }
    var quit: String { value("Quit", "退出") }
    var checkForUpdates: String { value("Check for Updates", "检查更新") }
    var checkingForUpdates: String { value("Checking for Updates", "正在检查更新") }
    var downloadingUpdate: String { value("Downloading Update", "正在下载更新") }
    var downloadAndOpenUpdate: String { value("Download and Open", "下载并打开") }
    var openInstaller: String { value("Open Installer", "打开安装包") }
    var viewRelease: String { value("View Release", "查看发布页") }
    var sessions: String { value("Sessions", "会话") }
    var loadingSessions: String { value("Loading sessions", "正在加载会话") }
    var noSessionsFound: String { value("No sessions found", "未找到会话") }
    var waitingForTokenData: String { value("Waiting for token data", "正在等待 token 资料") }
    var refreshing: String { value("Refreshing", "正在刷新") }
    var resetDisplayBaselineShort: String { value("Reset Display Baseline", "重置显示基准") }
    var compressCurrentSession: String { value("Copy Session Summary", "复制会话摘要") }
    var compressingSession: String { value("Copying", "正在复制") }
    var totalContextUsed: String { value("Total Context Used", "已用上下文") }
    var contextWindow: String { value("Context Window", "上下文窗口") }
    var cacheHitRate: String { value("Cache Hit Rate", "缓存命中率") }
    var sinceDisplayBaseline: String { value("Since Display Baseline", "显示基准后") }
    var hoverOverviewHint: String {
        value(
            "Hover a slice to see details.",
            "悬停切片查看明细。"
        )
    }
    var hoverDetailHint: String {
        value(
            "Hover a slice to compare contributors. Use Back to Overview to return.",
            "悬停比较来源，使用返回概览回到总览。"
        )
    }
    var contextUsageHealthyTitle: String { value("Healthy", "健康") }
    var contextUsageHealthyMessage: String {
        value(
            "Ideal state. The model can usually stay focused.",
            "最理想，模型比较容易抓住重点"
        )
    }
    var contextUsageNormalTitle: String { value("Normal", "正常") }
    var contextUsageNormalMessage: String {
        value(
            "Still usable, but avoid adding too much unrelated context.",
            "仍然可用，但要避免堆太多无关内容"
        )
    }
    var contextUsageHeavyTitle: String { value("Heavy", "偏重") }
    var contextUsageHeavyMessage: String {
        value(
            "Details may start getting missed. Consider organizing the session or starting a new one.",
            "容易开始漏掉细节，建议整理或开新会话"
        )
    }
    var contextUsageHighRiskTitle: String { value("High Risk", "高风险") }
    var contextUsageHighRiskMessage: String {
        value(
            "High risk of confusion, omissions, and interference from old information.",
            "容易混淆、遗漏、受旧信息干扰"
        )
    }
    var localSessionFilesHere: String {
        value("Codex local session files will appear here.", "Codex 本机会话文件会显示在这里。")
    }
    var backToOverview: String { value("Back to Overview", "返回概览") }
    var overview: String { value("Overview", "概览") }
    var overviewDescription: String {
        value(
            "Context is grouped by the information currently taking space in this Codex session.",
            "上下文会按当前会话中占用空间的资料类型分组。"
        )
    }
    var topContributors: String { value("Top Contributors", "主要来源") }
    var autoRefreshIsOn: String { value("Auto-refresh is on", "自动刷新已开启") }
    var name: String { value("Name", "名称") }
    var tokensTitle: String { value("Tokens", "Tokens") }
    var loadingContext: String { value("Loading context", "正在加载上下文") }
    var noBreakdownYet: String { value("No breakdown yet", "暂无明细") }
    var loadingWorkspace: String { value("Loading workspace", "正在加载工作区") }
    var updating: String { value("Updating", "正在更新") }
    var notUpdated: String { value("Not updated", "尚未更新") }
    var unknownMax: String { value("Unknown max", "未知上限") }
    var fullSessionView: String { value("Full session view", "完整会话视图") }
    var sinceBaseline: String { value("Since baseline", "基准后") }
    var displayContextUsed: String { value("Displayed Since Baseline", "基准后显示用量") }
    var actualContextUsed: String { value("Actual Context Used", "实际用量") }
    var actualContextDetail: String {
        value("Codex still has this much context in the session.", "Codex 当前会话实际仍占用这么多上下文。")
    }
    var displayResetHint: String {
        value(
            "This is only a monitor display baseline. The active Codex conversation and its actual context are unchanged.",
            "这只是监控器的显示基准，不会改变当前 Codex 对话和实际上下文。"
        )
    }
    var loadingContextData: String { value("Loading context data", "正在加载上下文资料") }
    var noActiveContextData: String { value("No active context data", "没有活跃的上下文资料") }
    var usageOver25: String {
        value("Context usage is over 25% of the window.", "上下文用量已超过窗口的 25%。")
    }
    var contextUsageNotificationTitle: String { value("Actual context usage is over 50%", "实际上下文用量已超过 50%") }
    func contextUsageNotificationBody(_ percent: String) -> String {
        value(
            "Current session is using \(percent) of the context window. Display baseline resets do not change this.",
            "当前会话已使用上下文窗口的 \(percent)。重置显示基准不会改变这个数字。"
        )
    }
    var usageWithinRange: String {
        value("Context usage is within the expected range.", "上下文用量在预期范围内。")
    }
    var waitingForCodexUserSession: String {
        value("Waiting for a Codex user session.", "正在等待 Codex 用户会话。")
    }
    var valuesMayBeIncomplete: String {
        value(
            "Some values may be incomplete until Codex records a fresh token count.",
            "Codex 记录新的 token 数前，部分数值可能不完整。"
        )
    }
    var clearOldContextHint: String {
        value(
            "Reset the display baseline when older local records are no longer useful in this monitor. This does not clear Codex context.",
            "旧记录不再需要显示时，可以重置监控器的显示基准。这不会清空 Codex 上下文。"
        )
    }
    var readingLocalData: String {
        value("The monitor is reading local Codex session data.", "监控器正在读取本机 Codex 会话资料。")
    }
    var compressionInProgressTitle: String { value("Copying session summary", "正在复制会话摘要") }
    var compressionInProgressDetail: String {
        value(
            "The summary is being built from the local session file.",
            "正在从本机会话文件生成摘要。"
        )
    }
    var compressionCopiedTitle: String { value("Summary copied", "摘要已复制") }
    var compressionFailedTitle: String { value("Copy failed", "复制失败") }
    var updateCheckingTitle: String { value("Checking for updates", "正在检查更新") }
    var updateCheckingDetail: String {
        value("The app is checking the latest GitHub Release.", "正在检查最新的 GitHub Release。")
    }
    var updateUpToDateTitle: String { value("You are up to date", "已是最新版") }
    func updateUpToDateDetail(_ time: String) -> String {
        value("Checked at \(time).", "\(time) 已检查。")
    }
    func updateAvailableTitle(_ version: String) -> String {
        value("Version \(version) is available", "发现 \(version) 版本")
    }
    func updateAvailableDetail(_ assetName: String) -> String {
        value("Download \(assetName), then open the installer.", "下载 \(assetName)，然后打开安装包。")
    }
    var updateDownloadingTitle: String { value("Downloading update", "正在下载更新") }
    func updateDownloadingDetail(_ assetName: String) -> String {
        value("Saving \(assetName) to Downloads.", "正在把 \(assetName) 存到下载文件夹。")
    }
    func updateDownloadedTitle(_ version: String) -> String {
        value("Version \(version) downloaded", "\(version) 版本已下载")
    }
    func updateDownloadedDetail(_ fileName: String) -> String {
        value("\(fileName) is in Downloads. The installer has been opened.", "\(fileName) 已存到下载文件夹，并已打开安装包。")
    }
    var updateFailedTitle: String { value("Update failed", "更新失败") }
    func updateFailedDetail(_ message: String) -> String {
        value("Reason: \(translateWarning(message))", "原因：\(translateWarning(message))")
    }
    func downloadUpdateVersion(_ version: String) -> String {
        value("Download \(version)", "下载 \(version)")
    }
    var compressionDocumentTitle: String { value("# Codex Session Summary", "# Codex 会话摘要") }
    var compressionDocumentIntro: String {
        value(
            "Use this summary to continue the session with less context.",
            "使用这份摘要，可以用更少上下文继续当前会话。"
        )
    }
    var compressionSectionSession: String { value("Session", "会话") }
    var compressionSectionLatestUserRequests: String { value("Latest User Requests", "最近的用户要求") }
    var compressionSectionRecentConversation: String { value("Recent Conversation", "近期对话") }
    var compressionSectionReferencedFiles: String { value("Referenced Files", "引用文件") }
    var compressionSectionRecentToolActivity: String { value("Recent Tool Activity", "最近工具活动") }
    var compressionSourceLines: String { value("Source lines", "来源行数") }
    var compressionSourceTokens: String { value("Source token estimate", "来源 token 估算") }
    var compressionNoLatestUserRequests: String { value("No recent user request was found.", "未找到最近的用户要求。") }
    var compressionNoRecentConversation: String { value("No recent conversation was found.", "未找到近期对话。") }
    var compressionNoReferencedFiles: String { value("No referenced files were found.", "未找到引用文件。") }
    var compressionNoToolActivity: String { value("No recent tool activity was found.", "未找到最近工具活动。") }
    var tokenUnitSuffix: String { value("tokens", "个 token") }
    var maxSuffix: String { value("max", "上限") }
    var window: String { value("window", "窗口") }

    func tokenCount(_ formattedCount: String) -> String {
        value("\(formattedCount) tokens", "\(formattedCount) 个 token")
    }

    func itemCount(_ count: Int) -> String {
        value("\(count) items", "\(count) 项")
    }

    func cacheHitRateDetail(_ cached: String, _ input: String) -> String {
        value("\(cached) of \(input) cached", "\(input) 中 \(cached) 命中缓存")
    }

    func moreItems(_ count: Int) -> String {
        value("\(count) more items", "还有 \(count) 项")
    }

    func percentOf(_ percent: String, _ total: String) -> String {
        value("\(percent) of \(total)", "\(percent) / \(total)")
    }

    func updatedAt(_ time: String) -> String {
        value("Updated \(time)", "\(time) 更新")
    }

    func warning(_ message: String) -> String {
        value("Warning: \(translateWarning(message))", "警告：\(translateWarning(message))")
    }

    func compressionCopiedDetail(_ tokenEstimate: String, _ time: String) -> String {
        value(
            "Copied at \(time). Summary size is about \(tokenEstimate) tokens.",
            "\(time) 已复制。摘要约 \(tokenEstimate) 个 token。"
        )
    }

    func compressionFailedDetail(_ message: String) -> String {
        value("Reason: \(translateWarning(message))", "原因：\(translateWarning(message))")
    }

    func compressionOmittedMessages(_ count: Int) -> String {
        value("\(count) earlier messages omitted.", "已省略前面 \(count) 条消息。")
    }

    func compressionOmittedToolActivities(_ count: Int) -> String {
        value("\(count) earlier tool activities omitted.", "已省略前面 \(count) 条工具活动。")
    }

    func compressionRoleName(_ role: String) -> String {
        switch role {
        case "user":
            value("User", "用户")
        case "assistant":
            value("Assistant", "助手")
        default:
            role
        }
    }

    func percentOfCategory(_ category: ContextCategoryKind) -> String {
        value("% of \(categoryName(category))", "占\(categoryName(category))")
    }

    func categoryName(_ kind: ContextCategoryKind) -> String {
        switch kind {
        case .instructions:
            value("Instructions", "指令")
        case .skills:
            value("Skills", "技能")
        case .mcp:
            "MCP"
        case .files:
            value("Files", "文件")
        case .messages:
            value("Messages", "消息")
        case .toolCalls:
            value("Tool Calls", "工具调用")
        case .toolOutput:
            value("Tool Output", "工具输出")
        case .reasoning:
            value("Reasoning", "推理")
        case .other:
            value("Other", "其他")
        }
    }

    func remainingCategory(_ category: ContextCategoryKind) -> String {
        value("Remaining \(categoryName(category))", "剩余\(categoryName(category))")
    }

    func displayItemTitle(_ title: String) -> String {
        guard language == .chinese else {
            return title
        }

        switch title {
        case "Base instructions":
            return "基础指令"
        case "User":
            return "用户"
        case "Assistant":
            return "助手"
        case "Developer":
            return "开发者"
        case "System":
            return "系统"
        case "Reasoning":
            return "推理"
        case "function_call_output":
            return "函数调用结果"
        case "tool_search_output":
            return "工具搜索结果"
        case "tool_search":
            return "工具搜索"
        default:
            return title
        }
    }

    func displayItemSubtitle(_ subtitle: String?) -> String? {
        guard let subtitle else {
            return nil
        }

        if let kind = ContextCategoryKind(rawValue: subtitle) {
            return categoryName(kind)
        }

        guard language == .chinese else {
            return subtitle
        }

        switch subtitle {
        case "available tool":
            return "可用工具"
        case "call":
            return "调用"
        case "call result":
            return "调用结果"
        case "tool namespace":
            return "工具命名空间"
        case "tool definition":
            return "工具定义"
        default:
            return subtitle
        }
    }

    func translateWarning(_ message: String) -> String {
        guard language == .chinese else {
            return message
        }

        switch message {
        case "No token_count event has been recorded for this session yet.":
            return "这个会话还没有记录 token 数。"
        case "Selected session is no longer available. Showing latest session.":
            return "选中的会话已不可用，正在显示最新会话。"
        case "The update server returned an unreadable response.":
            return "更新服务器返回的内容无法读取。"
        case "The latest release does not include a DMG installer.":
            return "最新版本没有包含 DMG 安装包。"
        case "The installer could not be downloaded.":
            return "安装包无法下载。"
        default:
            break
        }

        let knownPrefixes: [(String, String)] = [
            ("Codex folder was not found at ", "未找到 Codex 文件夹："),
            ("No Codex session files were found under ", "未找到 Codex 会话文件："),
            ("The selected Codex session could not be read: ", "无法读取选中的 Codex 会话：")
        ]

        for (englishPrefix, chinesePrefix) in knownPrefixes where message.hasPrefix(englishPrefix) {
            let path = message
                .dropFirst(englishPrefix.count)
                .trimmingCharacters(in: CharacterSet(charactersIn: "."))
            return "\(chinesePrefix)\(path)。"
        }

        return message
    }
}
