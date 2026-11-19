import SwiftUI
import UIKit
import CoreText

enum StudyTypography {
    private static let registerFonts: Void = {
        for name in ["ZenMaruGothic-Black", "ZenMaruGothic-Regular", "ZenMaruGothic-Bold", "Nunito"] {
            guard let url = Bundle.main.url(forResource: name, withExtension: "ttf", subdirectory: "Fonts") else { continue }
            CTFontManagerRegisterFontsForURL(url as CFURL, .process, nil)
        }
    }()

    static func japaneseTitle(_ size: CGFloat, relativeTo style: Font.TextStyle = .title) -> Font {
        _ = registerFonts
        return .custom("ZenMaruGothic-Black", size: size, relativeTo: style)
    }

    static func roundedTitle(_ size: CGFloat, relativeTo style: Font.TextStyle = .title2) -> Font {
        _ = registerFonts
        return .custom("Nunito-Black", size: size, relativeTo: style)
    }

    /// Brand UI roles; IELTS passages retain the native reading font below.
    static func ui(_ size: CGFloat, relativeTo style: Font.TextStyle = .body, bold: Bool = false) -> Font {
        _ = registerFonts
        if Bundle.main.preferredLocalizations.first == "ja" {
            return .custom(bold ? "ZenMaruGothic-Bold" : "ZenMaruGothic-Regular", size: size, relativeTo: style)
        }
        return .custom("Nunito-Regular", size: size, relativeTo: style).weight(bold ? .bold : .regular)
    }
    static var title: Font { ui(28, relativeTo: .title, bold: true) }
    static var heading: Font { ui(22, relativeTo: .title2, bold: true) }
    static var headline: Font { ui(17, relativeTo: .headline, bold: true) }
    static var button: Font { ui(17, relativeTo: .headline, bold: true) }
    static var body: Font { ui(17) }
    static var subheadline: Font { ui(15, relativeTo: .subheadline) }
    static var footnote: Font { ui(13, relativeTo: .footnote) }
    static var caption: Font { ui(12, relativeTo: .caption) }
    static var bodyFont: UIFont { .preferredFont(forTextStyle: .body) }
}
