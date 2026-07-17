import Foundation
import Testing

@testable import FlukeKit

@Suite("Resilient API client")
struct ResilientAPIClientTests {
    @Test("Canonical remote errors never retain the raw body")
    func safeRemoteError() async throws {
        let body = Data(#"{"code":"UPSTREAM_UNAVAILABLE","message":"Try again later.","retryable":true,"requestId":"req-safe-1","secret":"do-not-leak"}"#.utf8)
        let transport = ScriptedTransport(.response(status: 503, body: body))
        let client = APIClient(
            baseURL: URL(string: "https://api.fluke.test")!,
            transport: transport
        )

        do {
            let _: HealthResponse = try await client.get("/api/v1/health")
            Issue.record("Expected the request to fail")
        } catch let error as APIError {
            #expect(error == .remote(
                status: 503,
                code: "UPSTREAM_UNAVAILABLE",
                message: "Try again later.",
                retryable: true,
                requestId: "req-safe-1"
            ))
            #expect(!error.localizedDescription.contains("do-not-leak"))
        }
    }

    @Test("Malformed remote errors become a generic safe failure")
    func malformedRemoteError() async throws {
        let transport = ScriptedTransport(.response(
            status: 500,
            body: Data("database password is secret".utf8)
        ))
        let client = APIClient(
            baseURL: URL(string: "https://api.fluke.test")!,
            transport: transport
        )

        do {
            let _: HealthResponse = try await client.get("/api/v1/health")
            Issue.record("Expected the request to fail")
        } catch let error as APIError {
            #expect(error == .remote(
                status: 500,
                code: "REMOTE_ERROR",
                message: "The service could not complete the request.",
                retryable: true,
                requestId: nil
            ))
            #expect(!error.localizedDescription.contains("password"))
        }
    }

    @Test("Structurally valid but unsafe error strings fall back to generic copy")
    func boundedSafeError() async throws {
        let transport = ScriptedTransport(.response(
            status: 500,
            body: Data(#"{"code":"","message":"   ","retryable":true,"requestId":"req-1"}"#.utf8)
        ))
        let client = APIClient(
            baseURL: URL(string: "https://api.fluke.test")!,
            transport: transport
        )

        await #expect(throws: APIError.remote(
            status: 500,
            code: "REMOTE_ERROR",
            message: "The service could not complete the request.",
            retryable: true,
            requestId: nil
        )) {
            let _: HealthResponse = try await client.get("/api/v1/health")
        }
    }

    @Test("Query items have deterministic encoding")
    func deterministicQuery() throws {
        let request = APIRequest(
            path: "/api/v1/sightings/historical",
            queryItems: [
                URLQueryItem(name: "whaleId", value: "whale a&b"),
                URLQueryItem(name: "pod", value: "J"),
            ]
        )

        let url = try request.url(relativeTo: URL(string: "https://api.fluke.test")!)

        #expect(url.absoluteString == "https://api.fluke.test/api/v1/sightings/historical?whaleId=whale%20a%26b&pod=J")
    }

    @Test("Request deadlines cancel slow transports")
    func requestDeadline() async throws {
        let transport = ScriptedTransport(.delayed(seconds: 5))
        let client = APIClient(
            baseURL: URL(string: "https://api.fluke.test")!,
            transport: transport,
            requestTimeout: .milliseconds(10)
        )

        await #expect(throws: APIError.timeout) {
            let _: HealthResponse = try await client.get("/api/v1/health")
        }
        #expect(await transport.wasCancelled)
    }

    @Test("Request deadline returns even when an injected transport ignores cancellation")
    func hardRequestDeadline() async throws {
        let transport = IgnoringCancellationTransport()
        let client = APIClient(
            baseURL: URL(string: "https://api.fluke.test")!,
            transport: transport,
            requestTimeout: .milliseconds(10)
        )
        Task {
            try await Task.sleep(for: .milliseconds(500))
            await transport.release()
        }
        let clock = ContinuousClock()
        let startedAt = clock.now

        await #expect(throws: APIError.timeout) {
            let _: HealthResponse = try await client.get("/api/v1/health")
        }

        #expect(startedAt.duration(to: clock.now) < .milliseconds(100))
        await transport.release()
    }

    @Test("Caller cancellation remains CancellationError")
    func callerCancellation() async throws {
        let transport = ScriptedTransport(.delayed(seconds: 5))
        let client = APIClient(
            baseURL: URL(string: "https://api.fluke.test")!,
            transport: transport,
            requestTimeout: .seconds(10)
        )
        let task = Task<HealthResponse, Error> {
            try await client.get("/api/v1/health")
        }
        await Task.yield()
        task.cancel()

        await #expect(throws: CancellationError.self) {
            try await task.value
        }
    }
}

private actor IgnoringCancellationTransport: HTTPTransport {
    private var continuation: CheckedContinuation<(Data, HTTPURLResponse), Never>?

    func data(for request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        await withCheckedContinuation { continuation in
            self.continuation = continuation
        }
    }

    func release() {
        continuation?.resume(returning: (
            Data(#"{"status":"ok","timestamp":"2026-07-16T00:00:00.000Z"}"#.utf8),
            HTTPURLResponse(
                url: URL(string: "https://api.fluke.test/api/v1/health")!,
                statusCode: 200,
                httpVersion: nil,
                headerFields: nil
            )!
        ))
        continuation = nil
    }
}

private actor ScriptedTransport: HTTPTransport {
    enum Script: Sendable {
        case response(status: Int, body: Data)
        case delayed(seconds: UInt64)
    }

    private let script: Script
    private(set) var wasCancelled = false

    init(_ script: Script) {
        self.script = script
    }

    func data(for request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        switch script {
        case .response(let status, let body):
            return (
                body,
                HTTPURLResponse(
                    url: request.url!,
                    statusCode: status,
                    httpVersion: nil,
                    headerFields: nil
                )!
            )
        case .delayed(let seconds):
            do {
                try await Task.sleep(for: .seconds(seconds))
            } catch {
                wasCancelled = true
                throw error
            }
            return (
                Data(),
                HTTPURLResponse(
                    url: request.url!,
                    statusCode: 200,
                    httpVersion: nil,
                    headerFields: nil
                )!
            )
        }
    }
}
