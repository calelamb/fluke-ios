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
  private var loop: PollingLoop?
  private var retirement: PollingLoop?
  private var lifecycleLease: UUID?

  public init(
    refresh: @escaping Refresh,
    sleep: @escaping Sleep = { try await Task.sleep(for: $0) }
  ) {
    self.refresh = refresh
    self.sleep = sleep
  }

  public var hasActiveLoop: Bool { loop != nil }

  public func setLifecycle(visible: Bool, foreground: Bool) async {
    self.visible = visible
    self.foreground = foreground
    await reconcileLoop()
  }

  public func maintainLifecycle(visible: Bool, foreground: Bool) async {
    let lease = UUID()
    lifecycleLease = lease
    await setLifecycle(visible: visible, foreground: foreground)
    do {
      try await Task.sleep(for: .seconds(31_536_000))
    } catch {
      // SwiftUI cancels the structured lifecycle task when its identity changes.
    }
    guard lifecycleLease == lease else { return }
    lifecycleLease = nil
    await setLifecycle(visible: false, foreground: false)
  }

  private func reconcileLoop() async {
    guard foreground && visible else {
      guard let current = loop else { return }
      loop = nil
      retirement = current
      current.task.cancel()
      await current.task.value
      if retirement?.id == current.id { retirement = nil }
      return
    }
    guard loop == nil else { return }
    if let retirement {
      await retirement.task.value
      if self.retirement?.id == retirement.id { self.retirement = nil }
    }
    guard foreground && visible && loop == nil else { return }
    let id = UUID()
    let task = Task {
      await run()
      loopDidFinish(id)
    }
    loop = PollingLoop(id: id, task: task)
  }

  private func loopDidFinish(_ id: UUID) {
    if loop?.id == id { loop = nil }
    if retirement?.id == id { retirement = nil }
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

private struct PollingLoop {
  let id: UUID
  let task: Task<Void, Never>
}
