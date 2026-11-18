import SwiftUI
import UIKit

enum StudyTypography {
    static let title = Font.largeTitle.bold()
    static let headline = Font.headline
    static var bodyFont: UIFont { .preferredFont(forTextStyle: .body) }
}
