import Foundation

enum TranskunCheckpoint: String, CaseIterable, Identifiable {
    case packagedDefault = "packaged-default"
    case benchmarkV2 = "benchmark-v2"

    var id: String { rawValue }

    var label: String {
        switch self {
        case .packagedDefault:
            return "Packaged default"
        case .benchmarkV2:
            return "Benchmark V2"
        }
    }

    var detail: String {
        switch self {
        case .packagedDefault:
            return "Transkun V2 No Pedal Ext from the pip package."
        case .benchmarkV2:
            return "Transkun V2 checkpoint from the model card benchmark."
        }
    }
}
