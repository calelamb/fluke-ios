import Foundation
import os

/// A URLProtocol subclass for hijacking requests in tests.
/// Install a closure that returns
/// `(HTTPURLResponse, Data)` per request URL.
final class MockURLProtocol: URLProtocol {
  typealias Handler = @Sendable (URLRequest) throws -> (HTTPURLResponse, Data)
  private static let handler = OSAllocatedUnfairLock<Handler?>(initialState: nil)

  static func install(_ newHandler: @escaping Handler) {
    handler.withLock { storedHandler in
      storedHandler = newHandler
    }
  }

  static func reset() {
    handler.withLock { storedHandler in
      storedHandler = nil
    }
  }

  override class func canInit(with request: URLRequest) -> Bool { true }
  override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

  override func startLoading() {
    guard let handler = Self.handler.withLock({ $0 }) else {
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
