import Foundation

enum QAEnvironment {
    static let isUITestMode = ProcessInfo.processInfo.arguments.contains("-UITEST")

    static let uiTestFlag = "-UITEST"
}
