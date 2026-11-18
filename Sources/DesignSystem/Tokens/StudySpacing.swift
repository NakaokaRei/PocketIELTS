import CoreGraphics

/// Point values match the spacing scale on the Figma design-system page.
enum StudySpacing {
    static let related: CGFloat = 8
    static let contentInset: CGFloat = 16
    static let screenInset: CGFloat = 20
    static let section: CGFloat = 24
}

extension StudySpacing {
    static let gridGap: CGFloat = 10
    static let cardRadius: CGFloat = 21
    static let cardHeight: CGFloat = 127
}
