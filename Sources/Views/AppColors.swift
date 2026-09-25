import SwiftUI

/// Mirrors the CSS custom properties in static/style.css (the web app's
/// palette) so the native app looks like the same product, not a reskin.
enum AppColors {
    static let bg = Color(hex: "f6f5f2")
    static let surface = Color(hex: "ffffff")
    static let surface2 = Color(hex: "fbfaf7")
    static let border = Color(hex: "e7e4dc")
    static let ink = Color(hex: "23211c")
    static let inkSoft = Color(hex: "6b6659")
    static let accent = Color(hex: "b5502e")
    static let accentSoft = Color(hex: "f3e2d8")
    static let gold = Color(hex: "b8862f")
    static let success = Color(hex: "2f9e52")
    static let successSoft = Color(hex: "eef9f0")
    static let sentBorder = Color(hex: "a9dcb4")
    static let projectBorder = Color(hex: "d8c98a")
    static let favorite = Color(hex: "d6336c")
    static let triesText = Color(hex: "8a6d1f")
    static let triesBg = Color(hex: "f4e9c9")
    static let plusOneDot = Color(hex: "2563eb")
}
