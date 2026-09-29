import Foundation

/// How far along a document is, as the library shows it.
nonisolated enum ReadingStatus: Equatable {
    case new
    /// A whole percentage, at least 1 so a started document never reads 0%.
    case inProgress(percent: Int)
    case finished

    init(progress: Double) {
        if progress >= 1 {
            self = .finished
        } else if progress <= 0 {
            self = .new
        } else {
            self = .inProgress(percent: max(1, Int(progress * 100)))
        }
    }

    var label: String {
        switch self {
        case .new: "New"
        case .inProgress(let percent): "\(percent)%"
        case .finished: "Finished"
        }
    }

    var isInProgress: Bool {
        if case .inProgress = self { return true }
        return false
    }
}
