import SwiftUI
import UIKit
import CoreText

enum StudyTypography {
    private static let registerFonts: Void = {
        for name in ["ZenMaruGothic-Black", "Nunito"] {
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

    static let title = Font.largeTitle.bold()
    static let headline = Font.headline
    static var bodyFont: UIFont { .preferredFont(forTextStyle: .body) }
}
