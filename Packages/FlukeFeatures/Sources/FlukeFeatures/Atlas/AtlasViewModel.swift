import Foundation
import Observation

@MainActor
@Observable
public final class AtlasViewModel {
    public enum SubView: String, CaseIterable, Identifiable {
        case timeline = "Timeline"
        case range = "Range"
        case trace = "Trace"
        case predict = "Predict"

        public var id: String { rawValue }
    }

    public var activeSubView: SubView = .timeline
}
