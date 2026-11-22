import Foundation
import SwiftUI

struct LogEntry: Identifiable, Equatable {
    enum Level: String, CaseIterable, Identifiable {
        case info, success, warning, error
        var id: String { rawValue }

        var title: String {
            switch self {
            case .info: "Инфо"
            case .success: "Успех"
            case .warning: "Внимание"
            case .error: "Ошибка"
            }
        }

        var systemImage: String {
            switch self {
            case .info: "info.circle.fill"
            case .success: "checkmark.circle.fill"
            case .warning: "exclamationmark.triangle.fill"
            case .error: "xmark.octagon.fill"
            }
        }

        var color: Color {
            switch self {
            case .info: Theme.accent
            case .success: Theme.success
            case .warning: Theme.warning
            case .error: Theme.danger
            }
        }
    }

    let id = UUID()
    let date: Date
    let level: Level
    let message: String

    var exportLine: String {
        "\(Formatters.logTimestamp.string(from: date)) [\(level.rawValue.uppercased())] \(message)"
    }
}

struct AppAlert: Identifiable {
    let id = UUID()
    let title: String
    let message: String
}
