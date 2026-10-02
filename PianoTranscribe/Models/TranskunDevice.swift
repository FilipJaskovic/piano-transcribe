import Foundation

enum TranskunDevice: String, CaseIterable, Identifiable, Sendable {
    case cpu
    case mpsExperimental = "mps"

    var id: String { rawValue }

    var label: String {
        switch self {
        case .cpu:
            "CPU"
        case .mpsExperimental:
            "MPS / Metal (Experimental)"
        }
    }
}
