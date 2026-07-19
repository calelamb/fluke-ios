import Foundation

public actor FeedPollingActor {
  public typealias Refresh = @Sendable () async throws -> Void
  public typealias Sleep = @Sendable (Duration) async throws -> Void

  private static let delays: [Duration] = [
    .seconds(30), .seconds(60), .seconds(120), .seconds(300),
  ]

  private let refresh: Refresh
  private let sleep: Sleep
  private var foreground = false
  private var visible = false
  private var loop: Task<Void, Never>?

  public init(
    refresh: @escaping Refresh,
    sleep: @escaping Sleep = { try await Task.sleep(for: $0) }
  ) {
    self.refresh = refresh
    self.sleep = sleep
  }

  public var hasActiveLoop: Bool { loop != nil }

  public func setForeground(_ value: Bool) {
    foreground = value
    reconcileLoop()
  }

  public func setVisible(_ value: Bool) {
    visible = value
    reconcileLoop()
  }

  private func reconcileLoop() {
    guard foreground && visible else {
      loop?.cancel()
      loop = nil
      return
    }
    guard loop == nil else { return }
    loop = Task { await run() }
  }

  private func run() async {
    var failureIndex = 0
    while !Task.isCancelled {
      do {
        try await refresh()
        failureIndex = 0
      } catch is CancellationError {
        return
      } catch {
        failureIndex = min(failureIndex + 1, Self.delays.count)
      }
      let delayIndex = failureIndex == 0 ? 0 : failureIndex - 1
      do {
        try await sleep(Self.delays[delayIndex])
      } catch {
        return
      }
    }
  }

}
