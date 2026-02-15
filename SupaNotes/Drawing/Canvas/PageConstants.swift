import Foundation

enum PageConstants {
    // US Letter at 72 DPI (logical/display size)
    static let pageWidth: CGFloat = 612
    static let pageHeight: CGFloat = 792
    static let pageGap: CGFloat = 24

    // 2x internal resolution for crisper PencilKit strokes
    static let renderScale: CGFloat = 2.0

    static let internalWidth: CGFloat = pageWidth * renderScale
    static let internalHeight: CGFloat = pageHeight * renderScale
    static let internalGap: CGFloat = pageGap * renderScale
}
