import Foundation
import Testing
@testable import CodexContextMonitor

@Test func toCodexUsageParsesWrappedSubscriptionResponse() throws {
    let json = """
    {
      "code": 0,
      "data": [
        {
          "id": 42,
          "status": "active",
          "daily_usage_usd": 1.25,
          "weekly_usage_usd": 4.5,
          "monthly_usage_usd": 12.75,
          "group": {
            "name": "Claude Code",
            "daily_limit_usd": 10,
            "weekly_limit_usd": 50,
            "monthly_limit_usd": 150
          }
        }
      ]
    }
    """.data(using: .utf8)!

    let generatedAt = Date(timeIntervalSince1970: 100)
    let snapshot = try ToCodexUsageClient.snapshot(from: json, generatedAt: generatedAt)

    #expect(snapshot.generatedAt == generatedAt)
    #expect(snapshot.subscriptions.count == 1)
    #expect(snapshot.subscriptions[0].id == "42")
    #expect(snapshot.subscriptions[0].groupName == "Claude Code")
    #expect(snapshot.total(for: .daily).usedUSD == 1.25)
    #expect(snapshot.total(for: .weekly).limitUSD == 50)
    #expect(snapshot.total(for: .monthly).ratio == 0.085)
}

@Test func toCodexUsageParsesStringNumbersAndUnlimitedLimits() throws {
    let json = """
    [
      {
        "id": "sub_a",
        "status": "active",
        "daily_usage_usd": "2.5",
        "weekly_usage_usd": "7",
        "monthly_usage_usd": "20",
        "group": {
          "name": "OpenAI",
          "daily_limit_usd": null,
          "weekly_limit_usd": 0,
          "monthly_limit_usd": "100"
        }
      }
    ]
    """.data(using: .utf8)!

    let snapshot = try ToCodexUsageClient.snapshot(from: json, generatedAt: Date())

    #expect(snapshot.total(for: .daily).usedUSD == 2.5)
    #expect(snapshot.total(for: .daily).limitUSD == nil)
    #expect(snapshot.total(for: .daily).hasUnlimitedLimit)
    #expect(snapshot.total(for: .weekly).limitUSD == nil)
    #expect(snapshot.total(for: .monthly).limitUSD == 100)
}

@Test func toCodexUsageParsesResetWindows() throws {
    let json = """
    {
      "code": 0,
      "data": [
        {
          "id": "sub_a",
          "status": "active",
          "daily_usage_usd": 1,
          "weekly_usage_usd": 2,
          "monthly_usage_usd": 3,
          "daily_window_start": "2026-06-16T00:00:00Z",
          "weekly_window_start": "2026-06-15T00:00:00Z",
          "monthly_window_start": "2026-06-01T00:00:00Z",
          "group": {
            "name": "ToCodex",
            "daily_limit_usd": 10,
            "weekly_limit_usd": 20,
            "monthly_limit_usd": 30
          }
        }
      ]
    }
    """.data(using: .utf8)!

    let generatedAt = Date(timeIntervalSince1970: 1_781_611_200)
    let snapshot = try ToCodexUsageClient.snapshot(from: json, generatedAt: generatedAt)

    let formatter = ISO8601DateFormatter()
    #expect(snapshot.total(for: .daily).resetAt == formatter.date(from: "2026-06-17T00:00:00Z"))
    #expect(snapshot.total(for: .weekly).resetAt == formatter.date(from: "2026-06-22T00:00:00Z"))
    #expect(snapshot.total(for: .monthly).resetAt == formatter.date(from: "2026-07-01T00:00:00Z"))
}

@Test func toCodexUsageNormalizesBearerToken() {
    #expect(ToCodexUsageClient.normalizedToken("Bearer abc123") == "abc123")
    #expect(ToCodexUsageClient.normalizedToken("  bearer token-value  ") == "token-value")
    #expect(ToCodexUsageClient.normalizedToken("plain-token") == "plain-token")
}

@Test func toCodexLoginExchangesAccountForCredentials() async throws {
    final class MockURLProtocol: URLProtocol, @unchecked Sendable {
        static let lock = NSLock()
        nonisolated(unsafe) static var requestBody: Data?

        override class func canInit(with request: URLRequest) -> Bool {
            true
        }

        override class func canonicalRequest(for request: URLRequest) -> URLRequest {
            request
        }

        static func reset() {
            lock.lock()
            requestBody = nil
            lock.unlock()
        }

        static func capturedBody() -> Data? {
            lock.lock()
            let body = requestBody
            lock.unlock()
            return body
        }

        private static func bodyData(from request: URLRequest) -> Data? {
            if let body = request.httpBody {
                return body
            }

            guard let stream = request.httpBodyStream else {
                return nil
            }

            stream.open()
            defer { stream.close() }

            var data = Data()
            var buffer = [UInt8](repeating: 0, count: 1024)
            while stream.hasBytesAvailable {
                let count = stream.read(&buffer, maxLength: buffer.count)
                guard count > 0 else {
                    break
                }
                data.append(buffer, count: count)
            }
            return data
        }

        override func startLoading() {
            Self.lock.lock()
            Self.requestBody = Self.bodyData(from: request)
            Self.lock.unlock()

            let body = #"{"code":0,"data":{"access_token":"login-token","refresh_token":"login-refresh","expires_in":3600}}"#
            let response = HTTPURLResponse(
                url: request.url!,
                statusCode: 200,
                httpVersion: nil,
                headerFields: ["Content-Type": "application/json"]
            )!
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: Data(body.utf8))
            client?.urlProtocolDidFinishLoading(self)
        }

        override func stopLoading() {}
    }

    MockURLProtocol.reset()

    let configuration = URLSessionConfiguration.ephemeral
    configuration.protocolClasses = [MockURLProtocol.self]
    let session = URLSession(configuration: configuration)
    let client = ToCodexUsageClient(
        baseURL: URL(string: "https://tocodex.test/api/v1")!,
        session: session
    )

    let credentials = try await client.login(email: " user@example.com ", password: "secret")

    #expect(credentials.authToken == "login-token")
    #expect(credentials.refreshToken == "login-refresh")

    let body = try #require(MockURLProtocol.capturedBody())
    let json = try #require(JSONSerialization.jsonObject(with: body) as? [String: String])
    #expect(json["email"] == "user@example.com")
    #expect(json["password"] == "secret")
}

@Test func toCodexLoginReportsTwoFactorRequirement() async throws {
    final class MockURLProtocol: URLProtocol, @unchecked Sendable {
        override class func canInit(with request: URLRequest) -> Bool {
            true
        }

        override class func canonicalRequest(for request: URLRequest) -> URLRequest {
            request
        }

        override func startLoading() {
            let body = #"{"code":0,"data":{"requires_2fa":true,"temp_token":"temporary"}}"#
            let response = HTTPURLResponse(
                url: request.url!,
                statusCode: 200,
                httpVersion: nil,
                headerFields: ["Content-Type": "application/json"]
            )!
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: Data(body.utf8))
            client?.urlProtocolDidFinishLoading(self)
        }

        override func stopLoading() {}
    }

    let configuration = URLSessionConfiguration.ephemeral
    configuration.protocolClasses = [MockURLProtocol.self]
    let session = URLSession(configuration: configuration)
    let client = ToCodexUsageClient(
        baseURL: URL(string: "https://tocodex.test/api/v1")!,
        session: session
    )

    await #expect(throws: ToCodexUsageError.twoFactorRequired) {
        try await client.login(email: "user@example.com", password: "secret")
    }
}

@Test func toCodexUsageRefreshesExpiredAuthTokenAndRetries() async throws {
    final class MockURLProtocol: URLProtocol, @unchecked Sendable {
        static let lock = NSLock()
        nonisolated(unsafe) static var requests: [URLRequest] = []

        override class func canInit(with request: URLRequest) -> Bool {
            true
        }

        override class func canonicalRequest(for request: URLRequest) -> URLRequest {
            request
        }

        static func resetRequests() {
            lock.lock()
            requests = []
            lock.unlock()
        }

        static func requestPaths() -> [String?] {
            lock.lock()
            let paths = requests.map { $0.url?.path }
            lock.unlock()
            return paths
        }

        override func startLoading() {
            Self.lock.lock()
            Self.requests.append(request)
            let path = request.url?.path ?? ""
            let authorization = request.value(forHTTPHeaderField: "Authorization")
            Self.lock.unlock()

            let statusCode: Int
            let body: String
            if path == "/api/v1/subscriptions", authorization == "Bearer expired" {
                statusCode = 401
                body = #"{"code":401,"message":"INVALID_TOKEN"}"#
            } else if path == "/api/v1/auth/refresh" {
                statusCode = 200
                body = #"{"code":0,"data":{"access_token":"fresh","refresh_token":"fresh-refresh","expires_in":3600}}"#
            } else if path == "/api/v1/subscriptions", authorization == "Bearer fresh" {
                statusCode = 200
                body = """
                {"code":0,"data":[{"id":"sub","status":"active","daily_usage_usd":1,"weekly_usage_usd":2,"monthly_usage_usd":3,"group":{"name":"ToCodex","daily_limit_usd":10,"weekly_limit_usd":20,"monthly_limit_usd":30}}]}
                """
            } else {
                statusCode = 500
                body = #"{"code":500,"message":"unexpected request"}"#
            }

            let response = HTTPURLResponse(
                url: request.url!,
                statusCode: statusCode,
                httpVersion: nil,
                headerFields: ["Content-Type": "application/json"]
            )!
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: Data(body.utf8))
            client?.urlProtocolDidFinishLoading(self)
        }

        override func stopLoading() {}
    }

    MockURLProtocol.resetRequests()

    let configuration = URLSessionConfiguration.ephemeral
    configuration.protocolClasses = [MockURLProtocol.self]
    let session = URLSession(configuration: configuration)
    let client = ToCodexUsageClient(
        baseURL: URL(string: "https://tocodex.test/api/v1")!,
        session: session
    )

    let result = try await client.fetchSnapshot(
        credentials: ToCodexCredentials(authToken: "expired", refreshToken: "refresh")
    )

    #expect(result.snapshot.total(for: .daily).usedUSD == 1)
    #expect(result.credentials.authToken == "fresh")
    #expect(result.credentials.refreshToken == "fresh-refresh")

    #expect(MockURLProtocol.requestPaths() == ["/api/v1/subscriptions", "/api/v1/auth/refresh", "/api/v1/subscriptions"])
}
