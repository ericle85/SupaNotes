import Foundation

enum QAEnvironment {
    static let isUITestMode = ProcessInfo.processInfo.arguments.contains("-UITEST")
}
