import CoreGraphics
import Foundation
import UIKit

enum OCRFixtureExportError: LocalizedError {
    case noStrokes
    case invalidCanvasSize
    case pngEncodingFailed

    var errorDescription: String? {
        switch self {
        case .noStrokes:
            "Draw at least one stroke before saving an OCR fixture."
        case .invalidCanvasSize:
            "The canvas size is invalid, so the fixture could not be rendered."
        case .pngEncodingFailed:
            "The rendered fixture image could not be encoded as PNG."
        }
    }
}

enum OCRFixtureExporter {
    static func export(strokes: [Stroke], canvasSize: CGSize, screenScale: CGFloat) throws -> URL {
        guard !strokes.isEmpty else { throw OCRFixtureExportError.noStrokes }
        guard canvasSize.width > 0, canvasSize.height > 0 else {
            throw OCRFixtureExportError.invalidCanvasSize
        }

        let fileManager = FileManager.default
        let fixtureDirectory = try makeFixtureDirectory(fileManager: fileManager)
        let fixture = makeFixture(strokes: strokes, canvasSize: canvasSize)

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]

        let strokesURL = fixtureDirectory.appendingPathComponent("strokes.json")
        try encoder.encode(fixture).write(to: strokesURL, options: .atomic)

        let image = render(strokes: strokes, canvasSize: canvasSize, screenScale: screenScale)
        guard let pngData = image.pngData() else { throw OCRFixtureExportError.pngEncodingFailed }
        let imageURL = fixtureDirectory.appendingPathComponent("rendered.png")
        try pngData.write(to: imageURL, options: .atomic)

        let notesURL = fixtureDirectory.appendingPathComponent("notes.md")
        try makeNotes(for: fixtureDirectory.lastPathComponent)
            .write(to: notesURL, atomically: true, encoding: .utf8)

        return fixtureDirectory
    }

    private static func makeFixtureDirectory(fileManager: FileManager) throws -> URL {
        let documentsURL = fileManager.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let rootURL = documentsURL.appendingPathComponent("OCRFixtures", isDirectory: true)
        try fileManager.createDirectory(at: rootURL, withIntermediateDirectories: true)

        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "yyyyMMdd_HHmmss"

        let baseName = "case_\(formatter.string(from: Date()))"
        var candidateURL = rootURL.appendingPathComponent(baseName, isDirectory: true)
        var suffix = 2
        while fileManager.fileExists(atPath: candidateURL.path) {
            candidateURL = rootURL.appendingPathComponent("\(baseName)_\(suffix)", isDirectory: true)
            suffix += 1
        }
        try fileManager.createDirectory(at: candidateURL, withIntermediateDirectories: true)
        return candidateURL
    }

    private static func makeFixture(strokes: [Stroke], canvasSize: CGSize) -> OCRFixtureFile {
        let createdAt = ISO8601DateFormatter().string(from: Date())
        let exportedStrokes = strokes.enumerated().map { index, stroke in
            OCRFixtureStroke(
                id: String(format: "stroke_%04d", index + 1),
                color: stroke.color.hexRGBA,
                width: Double(stroke.width),
                bbox: stroke.boundingBox?.exportedArray,
                points: stroke.points.map { point in
                    OCRFixturePoint(
                        xCoordinate: Double(point.location.x),
                        yCoordinate: Double(point.location.y),
                        timestamp: point.timestamp,
                        force: Double(point.force),
                        azimuth: Double(point.azimuth),
                        altitude: Double(point.altitude)
                    )
                }
            )
        }

        return OCRFixtureFile(
            schemaVersion: 1,
            createdAt: createdAt,
            platform: "iOS",
            device: OCRFixtureDevice(
                model: UIDevice.current.model,
                name: UIDevice.current.name,
                systemName: UIDevice.current.systemName,
                systemVersion: UIDevice.current.systemVersion
            ),
            app: OCRFixtureApp(
                bundleIdentifier: Bundle.main.bundleIdentifier,
                version: Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String,
                build: Bundle.main.infoDictionary?["CFBundleVersion"] as? String
            ),
            canvas: OCRFixtureCanvas(
                width: Double(canvasSize.width),
                height: Double(canvasSize.height),
                coordinateSpace: "canvasPoints",
                origin: "topLeft"
            ),
            strokes: exportedStrokes
        )
    }

    private static func render(strokes: [Stroke], canvasSize: CGSize, screenScale: CGFloat) -> UIImage {
        let format = UIGraphicsImageRendererFormat()
        format.scale = screenScale
        format.opaque = true

        return UIGraphicsImageRenderer(size: canvasSize, format: format).image { rendererContext in
            UIColor.white.setFill()
            rendererContext.fill(CGRect(origin: .zero, size: canvasSize))
            StrokeRenderer.draw(strokes, active: nil, in: rendererContext.cgContext)
        }
    }

    private static func makeNotes(for fixtureName: String) -> String {
        """
        # \(fixtureName)

        `strokes.json` is the raw fixture input for the OCR pipeline.
        """
    }
}

private struct OCRFixtureFile: Codable {
    let schemaVersion: Int
    let createdAt: String
    let platform: String
    let device: OCRFixtureDevice
    let app: OCRFixtureApp
    let canvas: OCRFixtureCanvas
    let strokes: [OCRFixtureStroke]
}

private struct OCRFixtureDevice: Codable {
    let model: String
    let name: String
    let systemName: String
    let systemVersion: String
}

private struct OCRFixtureApp: Codable {
    let bundleIdentifier: String?
    let version: String?
    let build: String?
}

private struct OCRFixtureCanvas: Codable {
    let width: Double
    let height: Double
    let coordinateSpace: String
    let origin: String
}

private struct OCRFixtureStroke: Codable {
    let id: String
    let color: String
    let width: Double
    let bbox: [Double]?
    let points: [OCRFixturePoint]
}

private struct OCRFixturePoint: Codable {
    let xCoordinate: Double
    let yCoordinate: Double
    let timestamp: TimeInterval
    let force: Double
    let azimuth: Double
    let altitude: Double

    enum CodingKeys: String, CodingKey {
        case xCoordinate = "x"
        case yCoordinate = "y"
        case timestamp = "t"
        case force
        case azimuth
        case altitude
    }
}

private extension Stroke {
    var boundingBox: CGRect? {
        guard let first = points.first else { return nil }
        return points.dropFirst().reduce(CGRect(origin: first.location, size: .zero)) { box, point in
            box.union(CGRect(origin: point.location, size: .zero))
        }
    }
}

private extension CGRect {
    var exportedArray: [Double] {
        [
            Double(minX),
            Double(minY),
            Double(maxX),
            Double(maxY)
        ]
    }
}

private extension UIColor {
    var hexRGBA: String {
        var red: CGFloat = 0
        var green: CGFloat = 0
        var blue: CGFloat = 0
        var alpha: CGFloat = 0
        getRed(&red, green: &green, blue: &blue, alpha: &alpha)
        return String(
            format: "#%02X%02X%02X%02X",
            Int(red * 255),
            Int(green * 255),
            Int(blue * 255),
            Int(alpha * 255)
        )
    }
}
