import Foundation
import Testing
@testable import CodexContextMonitor

@Test func updaterParsesLatestReleaseRedirectTag() {
    let latestReleaseURL = URL(string: "https://github.com/harmonarch/codex-context-viewer/releases/tag/v0.1.4")!

    #expect(AppUpdater.releaseTag(from: latestReleaseURL) == "v0.1.4")
    #expect(AppUpdater.releaseTag(from: URL(string: "https://github.com/harmonarch/codex-context-viewer/releases/latest")) == nil)
}

@Test func updaterBuildsReleaseAndAssetURLsWithoutGitHubAPI() {
    let releaseURL = AppUpdater.releaseURL(tagName: "v0.1.4")
    let assetURL = AppUpdater.assetDownloadURL(tagName: "v0.1.4")

    #expect(releaseURL.absoluteString == "https://github.com/harmonarch/codex-context-viewer/releases/tag/v0.1.4")
    #expect(assetURL.absoluteString == "https://github.com/harmonarch/codex-context-viewer/releases/download/v0.1.4/Codex-Context-Monitor.dmg")
    #expect(!releaseURL.absoluteString.contains("api.github.com"))
    #expect(!assetURL.absoluteString.contains("api.github.com"))
}
