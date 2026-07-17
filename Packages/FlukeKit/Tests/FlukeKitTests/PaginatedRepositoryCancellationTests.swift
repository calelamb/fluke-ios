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
