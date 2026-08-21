import Foundation

final class AutocompleteModelCache {
    static let shared = AutocompleteModelCache()

    private(set) var classifier: ClassifierModelInference?
    private(set) var ctcModel: CTCModelInference?
    private(set) var googleRecognizer: CachedDigitalInkRecognizer?

    private init() {}

    func prepare() async throws {
        if classifier != nil, ctcModel != nil, googleRecognizer != nil {
            return
        }

        classifier = try ClassifierModelInference()

        ctcModel = try CTCModelInference()

        try await downloadDigitalInkModelIfNeeded()
        googleRecognizer = try makeDigitalInkRecognizer()
    }
}
