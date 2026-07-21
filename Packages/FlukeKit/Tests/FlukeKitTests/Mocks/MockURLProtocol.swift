import Foundation
import os

/// A URLProtocol subclass for hijacking requests in tests.
/// Install a closure that returns
/// `(HTTPURLResponse, Data)` per request URL.
final class MockURLProtocol: URLProtocol {
  typealias Handler = @Sendable (URLRequest) throws -> (HTTPURLResponse, Data)
  fileprivate static let tokenHeader = "X-Fluke-Mock-Session"
  private static let handlers = OSAllocatedUnfairLock<[UUID: Handler]>(initialState: [:])

  fileprivate static func install(_ newHandler: @escaping Handler, for token: UUID) {
    handlers.withLock { storedHandlers in
      storedHandlers = storedHandlers.merging([token: newHandler]) { _, new in new }
    }
  }

  fileprivate static func reset(token: UUID) {
    handlers.withLock { storedHandlers in
      storedHandlers = storedHandlers.filter { $0.key != token }
    }
  }

  override class func canInit(with request: URLRequest) -> Bool { true }
  override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

  override func startLoading() {
    guard
      let rawToken = request.value(forHTTPHeaderField: Self.tokenHeader),
      let token = UUID(uuidString: rawToken),
      let handler = Self.handlers.withLock({ $0[token] })
    else {
      client?.urlProtocol(self, didFailWithError: URLError(.unknown))
      return
    }
    do {
      let (response, data) = try handler(request)
      client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
      client?.urlProtocol(self, didLoad: data)
      client?.urlProtocolDidFinishLoading(self)
    } catch {
      client?.urlProtocol(self, didFailWithError: error)
    }
  }

  override func stopLoading() {}
}

final class MockURLProtocolSession {
  private let token: UUID
  let configuration: URLSessionConfiguration

  init() {
    let token = UUID()
    let configuration = URLSessionConfiguration.ephemeral
    configuration.protocolClasses = [MockURLProtocol.self]
    configuration.httpAdditionalHeaders = [MockURLProtocol.tokenHeader: token.uuidString]
    self.token = token
    self.configuration = configuration
  }

  func install(_ handler: @escaping MockURLProtocol.Handler) {
    MockURLProtocol.install(handler, for: token)
  }

  func reset() {
    MockURLProtocol.reset(token: token)
  }

  deinit {
    reset()
  }
}

final class MockRequestCounter: Sendable {
  private let count = OSAllocatedUnfairLock(initialState: 0)

  @discardableResult
  func increment() -> Int {
    count.withLock { value in
      value += 1
      return value
    }
  }

  var value: Int {
    count.withLock { $0 }
  }
}
