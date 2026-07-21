import Foundation
import Testing

@Suite("Mock URL protocol isolation")
struct MockURLProtocolTests {
  @Test("Overlapping sessions route handlers and cleanup independently")
  func overlappingSessions() async throws {
    let firstMock = MockURLProtocolSession()
    let secondMock = MockURLProtocolSession()
    defer {
      firstMock.reset()
      secondMock.reset()
    }
    firstMock.install { request in
      try Self.response(for: request, body: "first")
    }
    secondMock.install { request in
      try Self.response(for: request, body: "second")
    }
    let url = try #require(URL(string: "https://mock.fluke.test/value"))
    let firstSession = URLSession(configuration: firstMock.configuration)
    let secondSession = URLSession(configuration: secondMock.configuration)

    async let firstData = firstSession.data(from: url).0
    async let secondData = secondSession.data(from: url).0
    #expect(try await String(decoding: firstData, as: UTF8.self) == "first")
    #expect(try await String(decoding: secondData, as: UTF8.self) == "second")

    firstMock.reset()
    let survivingData = try await secondSession.data(from: url).0
    #expect(String(decoding: survivingData, as: UTF8.self) == "second")
    await #expect(throws: URLError.self) {
      try await firstSession.data(from: url)
    }
  }

  private static func response(
    for request: URLRequest,
    body: String
  ) throws -> (HTTPURLResponse, Data) {
    let url = try #require(request.url)
    let response = try #require(
      HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: nil)
    )
    return (response, Data(body.utf8))
  }
}
