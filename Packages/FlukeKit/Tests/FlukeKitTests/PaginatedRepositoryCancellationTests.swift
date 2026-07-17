import Foundation
import Testing

@testable import FlukeKit

@Suite("Paginated repository cancellation")
struct PaginatedRepositoryCancellationTests {
    @Test("A task cancelled before loading never starts a request")
    func preCancelledTaskDoesNotRequest() async {
        let transport = CountingPageTransport()
        let api = APIClient(
            baseURL: URL(string: "https://api.fluke.app")!,
            transport: transport
        )

        let task = Task {
            withUnsafeCurrentTask { $0?.cancel() }
            let items: [String] = try await PaginatedRepository.fetchAll(
                api: api,
                endpoint: "/api/v1/items"
            )
            return items
        }

        await #expect(throws: CancellationError.self) {
            try await task.value
        }
        #expect(await transport.requestCount == 0)
    }

    @Test("Pagination rejects more than ten thousand items")
    func itemLimit() async {
        let transport = OversizedPageTransport()
        let api = APIClient(
            baseURL: URL(string: "https://api.fluke.app")!,
            transport: transport
        )

        await #expect(throws: APIError.invalidPagination) {
            let _: [Int] = try await PaginatedRepository.fetchAll(
                api: api,
                endpoint: "/api/v1/items"
            )
        }
        #expect(await transport.requestCount == 1)
    }

    @Test("Pagination has one absolute deadline across all pages")
    func overallDeadline() async {
        let transport = SlowPagedTransport()
        let api = APIClient(
            baseURL: URL(string: "https://api.fluke.app")!,
            transport: transport,
            requestTimeout: .seconds(1)
        )

        await #expect(throws: APIError.timeout) {
            let _: [Int] = try await PaginatedRepository.fetchAll(
                api: api,
                endpoint: "/api/v1/items",
                operationTimeout: .milliseconds(20)
            )
        }
        #expect(await transport.requestCount <= 2)
    }
}

private actor CountingPageTransport: HTTPTransport {
    private(set) var requestCount = 0

    func data(for request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        requestCount += 1
        let response = HTTPURLResponse(
            url: request.url!,
            statusCode: 200,
            httpVersion: nil,
            headerFields: nil
        )!
        return (
            Data(#"{"items":[],"page":{"hasMore":false,"nextCursor":null}}"#.utf8),
            response
        )
    }
}

private actor OversizedPageTransport: HTTPTransport {
    private(set) var requestCount = 0

    func data(for request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        requestCount += 1
        let items = Array(0...10_000)
        let body = try JSONSerialization.data(withJSONObject: [
            "items": items,
            "page": ["hasMore": false, "nextCursor": NSNull()],
        ])
        return (body, response(for: request))
    }

    private func response(for request: URLRequest) -> HTTPURLResponse {
        HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
    }
}

private actor SlowPagedTransport: HTTPTransport {
    private(set) var requestCount = 0

    func data(for request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        requestCount += 1
        try await Task.sleep(for: .milliseconds(15))
        let body = Data(
            #"{"items":[1],"page":{"hasMore":true,"nextCursor":"next"}}"#.utf8
        )
        return (
            body,
            HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
        )
    }
}
