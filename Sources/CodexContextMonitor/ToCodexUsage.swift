import Foundation
import Security

struct ToCodexUsagePeriod: Equatable, Sendable {
    let usedUSD: Double
    let limitUSD: Double?
    let hasUnlimitedLimit: Bool
    let resetAt: Date?

    var ratio: Double? {
        guard let limitUSD, limitUSD > 0 else {
            return nil
        }
        return min(1, usedUSD / limitUSD)
    }

    static let empty = ToCodexUsagePeriod(usedUSD: 0, limitUSD: nil, hasUnlimitedLimit: true, resetAt: nil)
}

enum ToCodexUsagePeriodKind: CaseIterable, Sendable {
    case daily
    case weekly
    case monthly
}

struct ToCodexSubscriptionUsage: Identifiable, Equatable, Sendable {
    let id: String
    let groupName: String
    let status: String
    let daily: ToCodexUsagePeriod
    let weekly: ToCodexUsagePeriod
    let monthly: ToCodexUsagePeriod

    var isActive: Bool {
        status.lowercased() == "active"
    }

    func period(_ kind: ToCodexUsagePeriodKind) -> ToCodexUsagePeriod {
        switch kind {
        case .daily:
            daily
        case .weekly:
            weekly
        case .monthly:
            monthly
        }
    }
}

struct ToCodexUsageSnapshot: Equatable, Sendable {
    let generatedAt: Date
    let subscriptions: [ToCodexSubscriptionUsage]

    var meteredSubscriptions: [ToCodexSubscriptionUsage] {
        let active = subscriptions.filter(\.isActive)
        return active.isEmpty ? subscriptions : active
    }

    var hasSubscriptions: Bool {
        !subscriptions.isEmpty
    }

    func total(for kind: ToCodexUsagePeriodKind) -> ToCodexUsagePeriod {
        let periods = meteredSubscriptions.map { $0.period(kind) }
        guard !periods.isEmpty else {
            return .empty
        }

        let finiteLimits = periods.compactMap(\.limitUSD)
        let resetDates = periods.compactMap(\.resetAt)
        let futureResetAt = resetDates.filter { $0 > generatedAt }.min()
        return ToCodexUsagePeriod(
            usedUSD: periods.reduce(0) { $0 + $1.usedUSD },
            limitUSD: finiteLimits.isEmpty ? nil : finiteLimits.reduce(0, +),
            hasUnlimitedLimit: periods.contains { $0.hasUnlimitedLimit },
            resetAt: futureResetAt ?? resetDates.min()
        )
    }
}

struct ToCodexCredentials: Equatable, Sendable {
    let authToken: String?
    let refreshToken: String?

    var hasUsableToken: Bool {
        normalizedToken(authToken) != nil || normalizedToken(refreshToken) != nil
    }

    var normalized: ToCodexCredentials {
        ToCodexCredentials(
            authToken: normalizedToken(authToken),
            refreshToken: normalizedToken(refreshToken)
        )
    }

    private func normalizedToken(_ value: String?) -> String? {
        guard let value else {
            return nil
        }
        let token = ToCodexUsageClient.normalizedToken(value)
        return token.isEmpty ? nil : token
    }
}

enum ToCodexUsageState: Equatable {
    case notConfigured
    case loading
    case loaded(ToCodexUsageSnapshot)
    case failed(String)
}

struct ToCodexUsageFetchResult: Equatable, Sendable {
    let snapshot: ToCodexUsageSnapshot
    let credentials: ToCodexCredentials
}

enum ToCodexUsageError: LocalizedError, Equatable {
    case notConfigured
    case invalidResponse
    case authenticationFailed
    case twoFactorRequired
    case server(String)

    var errorDescription: String? {
        switch self {
        case .notConfigured:
            "ToCodex login is not configured."
        case .invalidResponse:
            "ToCodex returned an unreadable response."
        case .authenticationFailed:
            "ToCodex login expired. Log in again."
        case .twoFactorRequired:
            "ToCodex account requires two-factor verification."
        case .server(let message):
            message.isEmpty ? "ToCodex request failed." : message
        }
    }
}

struct ToCodexUsageClient {
    private let baseURL: URL
    private let session: URLSession

    init(
        baseURL: URL = URL(string: "https://tocodex.space/api/v1")!,
        session: URLSession = .shared
    ) {
        self.baseURL = baseURL
        self.session = session
    }

    func login(email: String, password: String) async throws -> ToCodexCredentials {
        let email = email.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !email.isEmpty, !password.isEmpty else {
            throw ToCodexUsageError.notConfigured
        }

        let url = baseURL.appendingPathComponent("auth/login")
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("CodexContextMonitor", forHTTPHeaderField: "User-Agent")
        request.httpBody = try JSONSerialization.data(withJSONObject: [
            "email": email,
            "password": password
        ])

        let (data, response) = try await session.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw ToCodexUsageError.invalidResponse
        }

        if httpResponse.statusCode == 401 || httpResponse.statusCode == 403 {
            throw ToCodexUsageError.authenticationFailed
        }

        guard (200..<300).contains(httpResponse.statusCode) else {
            throw ToCodexUsageError.server(Self.serverMessage(from: data))
        }

        return try Self.credentials(from: data)
    }

    func fetchSnapshot(credentials: ToCodexCredentials) async throws -> ToCodexUsageFetchResult {
        let credentials = credentials.normalized
        if let authToken = credentials.authToken {
            do {
                let snapshot = try await fetchSnapshot(authToken: authToken)
                return ToCodexUsageFetchResult(snapshot: snapshot, credentials: credentials)
            } catch ToCodexUsageError.authenticationFailed {
                guard credentials.refreshToken != nil else {
                    throw ToCodexUsageError.authenticationFailed
                }
            }
        }

        guard let refreshToken = credentials.refreshToken else {
            throw ToCodexUsageError.notConfigured
        }

        let refreshedCredentials = try await refreshCredentials(refreshToken: refreshToken)
        guard let authToken = refreshedCredentials.authToken else {
            throw ToCodexUsageError.authenticationFailed
        }

        let snapshot = try await fetchSnapshot(authToken: authToken)
        return ToCodexUsageFetchResult(snapshot: snapshot, credentials: refreshedCredentials)
    }

    func fetchSnapshot(authToken: String) async throws -> ToCodexUsageSnapshot {
        let token = Self.normalizedToken(authToken)
        guard !token.isEmpty else {
            throw ToCodexUsageError.notConfigured
        }

        var components = URLComponents(
            url: baseURL.appendingPathComponent("subscriptions"),
            resolvingAgainstBaseURL: false
        )
        components?.queryItems = [
            URLQueryItem(name: "timezone", value: TimeZone.current.identifier)
        ]

        guard let url = components?.url else {
            throw ToCodexUsageError.invalidResponse
        }

        var request = URLRequest(url: url)
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("CodexContextMonitor", forHTTPHeaderField: "User-Agent")

        let (data, response) = try await session.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw ToCodexUsageError.invalidResponse
        }

        if httpResponse.statusCode == 401 || httpResponse.statusCode == 403 {
            throw ToCodexUsageError.authenticationFailed
        }

        guard (200..<300).contains(httpResponse.statusCode) else {
            throw ToCodexUsageError.server(Self.serverMessage(from: data))
        }

        return try Self.snapshot(from: data, generatedAt: Date())
    }

    func refreshCredentials(refreshToken: String) async throws -> ToCodexCredentials {
        let token = Self.normalizedToken(refreshToken)
        guard !token.isEmpty else {
            throw ToCodexUsageError.notConfigured
        }

        let url = baseURL.appendingPathComponent("auth/refresh")
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("CodexContextMonitor", forHTTPHeaderField: "User-Agent")
        request.httpBody = try JSONSerialization.data(withJSONObject: ["refresh_token": token])

        let (data, response) = try await session.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw ToCodexUsageError.invalidResponse
        }

        if httpResponse.statusCode == 401 || httpResponse.statusCode == 403 {
            throw ToCodexUsageError.authenticationFailed
        }

        guard (200..<300).contains(httpResponse.statusCode) else {
            throw ToCodexUsageError.server(Self.serverMessage(from: data))
        }

        let tokenResponse = try Self.decodeTokenResponse(from: data)
        let authToken = Self.normalizedToken(tokenResponse.accessToken)
        guard !authToken.isEmpty else {
            throw ToCodexUsageError.invalidResponse
        }

        return ToCodexCredentials(
            authToken: authToken,
            refreshToken: tokenResponse.refreshToken.map(Self.normalizedToken) ?? token
        )
    }

    static func snapshot(from data: Data, generatedAt: Date) throws -> ToCodexUsageSnapshot {
        let subscriptions = try decodeSubscriptions(from: data)
        return ToCodexUsageSnapshot(
            generatedAt: generatedAt,
            subscriptions: subscriptions.map(\.usage)
        )
    }

    static func normalizedToken(_ value: String) -> String {
        let token = value.trimmingCharacters(in: .whitespacesAndNewlines)
        if token.lowercased().hasPrefix("bearer ") {
            return String(token.dropFirst("bearer ".count))
                .trimmingCharacters(in: .whitespacesAndNewlines)
        }
        return token
    }

    private static func decodeSubscriptions(from data: Data) throws -> [ToCodexSubscriptionDTO] {
        let decoder = JSONDecoder()
        if let envelope = try? decoder.decode(ToCodexEnvelope<[ToCodexSubscriptionDTO]>.self, from: data),
           envelope.code == nil || envelope.code == 0 {
            return envelope.data ?? []
        }

        if let envelope = try? decoder.decode(ToCodexEnvelope<[ToCodexSubscriptionDTO]>.self, from: data),
           let message = envelope.message {
            if isAuthenticationMessage(message) {
                throw ToCodexUsageError.authenticationFailed
            }
            throw ToCodexUsageError.server(message)
        }

        do {
            return try decoder.decode([ToCodexSubscriptionDTO].self, from: data)
        } catch {
            throw ToCodexUsageError.invalidResponse
        }
    }

    private static func credentials(from data: Data) throws -> ToCodexCredentials {
        let tokenResponse = try decodeTokenResponse(from: data)
        let authToken = normalizedToken(tokenResponse.accessToken)
        guard !authToken.isEmpty else {
            throw ToCodexUsageError.invalidResponse
        }
        return ToCodexCredentials(
            authToken: authToken,
            refreshToken: tokenResponse.refreshToken.map(Self.normalizedToken)
        )
    }

    private static func decodeTokenResponse(from data: Data) throws -> ToCodexTokenResponse {
        let decoder = JSONDecoder()
        if let envelope = try? decoder.decode(ToCodexEnvelope<ToCodexTokenResponse>.self, from: data) {
            if envelope.code == nil || envelope.code == 0 {
                guard let tokenResponse = envelope.data else {
                    throw ToCodexUsageError.invalidResponse
                }
                if tokenResponse.requiresTwoFactor {
                    throw ToCodexUsageError.twoFactorRequired
                }
                return tokenResponse
            }
            if let message = envelope.message, isAuthenticationMessage(message) {
                throw ToCodexUsageError.authenticationFailed
            }
            throw ToCodexUsageError.server(envelope.message ?? "ToCodex request failed.")
        }

        do {
            let tokenResponse = try decoder.decode(ToCodexTokenResponse.self, from: data)
            if tokenResponse.requiresTwoFactor {
                throw ToCodexUsageError.twoFactorRequired
            }
            return tokenResponse
        } catch let error as ToCodexUsageError {
            throw error
        } catch {
            throw ToCodexUsageError.invalidResponse
        }
    }

    private static func serverMessage(from data: Data) -> String {
        guard let envelope = try? JSONDecoder().decode(ToCodexErrorEnvelope.self, from: data),
              let message = envelope.message?.trimmingCharacters(in: .whitespacesAndNewlines),
              !message.isEmpty else {
            return "ToCodex request failed."
        }
        return message
    }

    private static func isAuthenticationMessage(_ message: String) -> Bool {
        let normalized = message.lowercased()
        return normalized.contains("invalid_token")
            || normalized.contains("invalid token")
            || normalized.contains("authorization")
            || normalized.contains("unauthorized")
            || normalized.contains("token expired")
    }
}

private struct ToCodexEnvelope<T: Decodable>: Decodable {
    let code: Int?
    let message: String?
    let data: T?
}

private struct ToCodexErrorEnvelope: Decodable {
    let message: String?
}

private struct ToCodexTokenResponse: Decodable {
    let accessToken: String
    let refreshToken: String?
    let requiresTwoFactor: Bool

    enum CodingKeys: String, CodingKey {
        case accessToken = "access_token"
        case refreshToken = "refresh_token"
        case requiresTwoFactor = "requires_2fa"
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        accessToken = try container.decodeIfPresent(String.self, forKey: .accessToken) ?? ""
        refreshToken = try container.decodeIfPresent(String.self, forKey: .refreshToken)
        requiresTwoFactor = try container.decodeIfPresent(Bool.self, forKey: .requiresTwoFactor) ?? false
    }
}

private struct ToCodexSubscriptionDTO: Decodable {
    let id: String
    let status: String?
    let group: Group?
    let groupID: Int?
    let dailyUsageUSD: Double?
    let weeklyUsageUSD: Double?
    let monthlyUsageUSD: Double?
    let dailyWindowStart: Date?
    let weeklyWindowStart: Date?
    let monthlyWindowStart: Date?
    let startsAt: Date?
    let expiresAt: Date?

    enum CodingKeys: String, CodingKey {
        case id
        case status
        case group
        case groupID = "group_id"
        case dailyUsageUSD = "daily_usage_usd"
        case weeklyUsageUSD = "weekly_usage_usd"
        case monthlyUsageUSD = "monthly_usage_usd"
        case dailyWindowStart = "daily_window_start"
        case weeklyWindowStart = "weekly_window_start"
        case monthlyWindowStart = "monthly_window_start"
        case startsAt = "starts_at"
        case expiresAt = "expires_at"
    }

    struct Group: Decodable {
        let name: String?
        let dailyLimitUSD: Double?
        let weeklyLimitUSD: Double?
        let monthlyLimitUSD: Double?

        enum CodingKeys: String, CodingKey {
            case name
            case dailyLimitUSD = "daily_limit_usd"
            case weeklyLimitUSD = "weekly_limit_usd"
            case monthlyLimitUSD = "monthly_limit_usd"
        }

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            name = try container.decodeIfPresent(String.self, forKey: .name)
            dailyLimitUSD = try container.decodeFlexibleDoubleIfPresent(forKey: .dailyLimitUSD)
            weeklyLimitUSD = try container.decodeFlexibleDoubleIfPresent(forKey: .weeklyLimitUSD)
            monthlyLimitUSD = try container.decodeFlexibleDoubleIfPresent(forKey: .monthlyLimitUSD)
        }
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decodeFlexibleString(forKey: .id)
        status = try container.decodeIfPresent(String.self, forKey: .status)
        group = try container.decodeIfPresent(Group.self, forKey: .group)
        groupID = try container.decodeIfPresent(Int.self, forKey: .groupID)
        dailyUsageUSD = try container.decodeFlexibleDoubleIfPresent(forKey: .dailyUsageUSD)
        weeklyUsageUSD = try container.decodeFlexibleDoubleIfPresent(forKey: .weeklyUsageUSD)
        monthlyUsageUSD = try container.decodeFlexibleDoubleIfPresent(forKey: .monthlyUsageUSD)
        dailyWindowStart = try container.decodeFlexibleDateIfPresent(forKey: .dailyWindowStart)
        weeklyWindowStart = try container.decodeFlexibleDateIfPresent(forKey: .weeklyWindowStart)
        monthlyWindowStart = try container.decodeFlexibleDateIfPresent(forKey: .monthlyWindowStart)
        startsAt = try container.decodeFlexibleDateIfPresent(forKey: .startsAt)
        expiresAt = try container.decodeFlexibleDateIfPresent(forKey: .expiresAt)
    }

    var usage: ToCodexSubscriptionUsage {
        ToCodexSubscriptionUsage(
            id: id,
            groupName: group?.name ?? groupID.map { "Group #\($0)" } ?? "ToCodex",
            status: status ?? "",
            daily: period(usage: dailyUsageUSD, limit: group?.dailyLimitUSD, resetAt: dailyResetAt),
            weekly: period(usage: weeklyUsageUSD, limit: group?.weeklyLimitUSD, resetAt: resetAt(windowStart: weeklyWindowStart, hours: 168)),
            monthly: period(usage: monthlyUsageUSD, limit: group?.monthlyLimitUSD, resetAt: resetAt(windowStart: monthlyWindowStart, hours: 720))
        )
    }

    private var dailyResetAt: Date? {
        if isShortTrialSubscription, let expiresAt {
            return expiresAt
        }
        return resetAt(windowStart: dailyWindowStart, hours: 24)
    }

    private var isShortTrialSubscription: Bool {
        guard let startsAt, let expiresAt else {
            return false
        }
        return expiresAt.timeIntervalSince(startsAt) <= 86_400
    }

    private func resetAt(windowStart: Date?, hours: TimeInterval) -> Date? {
        windowStart?.addingTimeInterval(hours * 60 * 60)
    }

    private func period(usage: Double?, limit: Double?, resetAt: Date?) -> ToCodexUsagePeriod {
        ToCodexUsagePeriod(
            usedUSD: max(0, usage ?? 0),
            limitUSD: limit.flatMap { $0 > 0 ? $0 : nil },
            hasUnlimitedLimit: limit == nil || (limit ?? 0) <= 0,
            resetAt: resetAt
        )
    }
}

private enum ToCodexDateParser {
    static func parse(_ value: String) -> Date? {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return nil
        }

        let fractionalFormatter = ISO8601DateFormatter()
        fractionalFormatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = fractionalFormatter.date(from: trimmed) {
            return date
        }

        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        if let date = formatter.date(from: trimmed) {
            return date
        }

        return nil
    }
}

private extension KeyedDecodingContainer {
    func decodeFlexibleString(forKey key: Key) throws -> String {
        if let value = try? decode(String.self, forKey: key) {
            return value
        }
        if let value = try? decode(Int.self, forKey: key) {
            return String(value)
        }
        if let value = try? decode(Double.self, forKey: key) {
            return String(value)
        }
        throw DecodingError.typeMismatch(
            String.self,
            DecodingError.Context(codingPath: codingPath + [key], debugDescription: "Expected string-compatible value.")
        )
    }

    func decodeFlexibleDoubleIfPresent(forKey key: Key) throws -> Double? {
        guard contains(key) else {
            return nil
        }
        if try decodeNil(forKey: key) {
            return nil
        }
        if let value = try? decode(Double.self, forKey: key) {
            return value
        }
        if let value = try? decode(Int.self, forKey: key) {
            return Double(value)
        }
        if let value = try? decode(String.self, forKey: key) {
            return Double(value.trimmingCharacters(in: .whitespacesAndNewlines))
        }
        return nil
    }

    func decodeFlexibleDateIfPresent(forKey key: Key) throws -> Date? {
        guard contains(key) else {
            return nil
        }
        if try decodeNil(forKey: key) {
            return nil
        }
        if let value = try? decode(String.self, forKey: key) {
            return ToCodexDateParser.parse(value)
        }
        if let value = try? decode(Double.self, forKey: key) {
            return Date(timeIntervalSince1970: normalizedTimestamp(value))
        }
        if let value = try? decode(Int.self, forKey: key) {
            return Date(timeIntervalSince1970: normalizedTimestamp(Double(value)))
        }
        return nil
    }

    private func normalizedTimestamp(_ value: Double) -> TimeInterval {
        value > 1_000_000_000_000 ? value / 1000 : value
    }
}

enum ToCodexCredentialStoreError: LocalizedError {
    case saveFailed(OSStatus)
    case deleteFailed(OSStatus)

    var errorDescription: String? {
        switch self {
        case .saveFailed:
            "Unable to save ToCodex login."
        case .deleteFailed:
            "Unable to delete ToCodex login."
        }
    }
}

struct ToCodexCredentialStore {
    private let service = "CodexContextMonitor.ToCodex"
    private let authTokenAccount = "authToken"
    private let refreshTokenAccount = "refreshToken"

    func loadToken() -> String? {
        loadValue(account: authTokenAccount)
    }

    func loadCredentials() -> ToCodexCredentials {
        ToCodexCredentials(
            authToken: loadValue(account: authTokenAccount),
            refreshToken: loadValue(account: refreshTokenAccount)
        )
    }

    private func loadValue(account: String) -> String? {
        var query = baseQuery(account: account)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne

        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        guard status == errSecSuccess,
              let data = result as? Data,
              let token = String(data: data, encoding: .utf8) else {
            return nil
        }
        return token
    }

    func saveToken(_ token: String) throws {
        try saveValue(token, account: authTokenAccount)
    }

    func saveCredentials(_ credentials: ToCodexCredentials) throws {
        let credentials = credentials.normalized
        if let authToken = credentials.authToken {
            try saveValue(authToken, account: authTokenAccount)
        }
        if let refreshToken = credentials.refreshToken {
            try saveValue(refreshToken, account: refreshTokenAccount)
        }
    }

    private func saveValue(_ value: String, account: String) throws {
        let data = Data(value.utf8)
        let status = SecItemUpdate(
            baseQuery(account: account) as CFDictionary,
            [kSecValueData as String: data] as CFDictionary
        )

        if status == errSecSuccess {
            return
        }

        guard status == errSecItemNotFound else {
            throw ToCodexCredentialStoreError.saveFailed(status)
        }

        var item = baseQuery(account: account)
        item[kSecValueData as String] = data
        let addStatus = SecItemAdd(item as CFDictionary, nil)
        guard addStatus == errSecSuccess else {
            throw ToCodexCredentialStoreError.saveFailed(addStatus)
        }
    }

    func deleteToken() throws {
        try deleteValue(account: authTokenAccount, allowMissing: true)
        try deleteValue(account: refreshTokenAccount, allowMissing: true)
    }

    private func deleteValue(account: String, allowMissing: Bool) throws {
        let status = SecItemDelete(baseQuery(account: account) as CFDictionary)
        guard status == errSecSuccess || (allowMissing && status == errSecItemNotFound) else {
            throw ToCodexCredentialStoreError.deleteFailed(status)
        }
    }

    private func baseQuery(account: String) -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
    }
}
