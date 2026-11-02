import Foundation

/// 아주 작은 한/영 전환. macOS 선호 언어 첫 번째가 한국어면 한국어, 아니면 영어.
/// (SwiftPM 실행 파일을 손으로 .app 에 묶기 때문에 .lproj 리소스 대신 코드에 둔다.)
enum L {
    static let isKorean: Bool = {
        if let forced = UserDefaults.standard.string(forKey: "language") { return forced == "ko" }
        return Locale.preferredLanguages.first?.hasPrefix("ko") ?? false
    }()

    static var locale: Locale { Locale(identifier: isKorean ? "ko_KR" : "en_US") }

    static func t(_ ko: String, _ en: String) -> String { isKorean ? ko : en }
}
