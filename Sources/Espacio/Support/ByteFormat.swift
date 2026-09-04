import Foundation

enum ByteFormat {
    private static let formatter: NumberFormatter = {
        let f = NumberFormatter()
        f.locale = Locale.current
        f.numberStyle = .decimal
        f.minimumFractionDigits = 0
        f.maximumFractionDigits = 2
        return f
    }()

    static func string(_ bytes: Int64) -> String {
        formatter.locale = AppLanguage.current.locale
        let b = Double(max(bytes, 0))
        let units = ["bytes", "KB", "MB", "GB", "TB"]
        var value = b
        var unit = 0
        while value >= 1000 && unit < units.count - 1 {
            value /= 1000
            unit += 1
        }
        let digits: Int
        switch unit {
        case 0: digits = 0
        case 1: digits = 0
        case 2: digits = value < 10 ? 1 : 0
        default: digits = value < 10 ? 2 : (value < 100 ? 1 : 0)
        }
        formatter.maximumFractionDigits = digits
        formatter.minimumFractionDigits = 0
        let num = formatter.string(from: NSNumber(value: value)) ?? "\(Int(value))"
        return "\(num) \(units[unit])"
    }

    static func count(_ n: Int64) -> String {
        formatter.locale = AppLanguage.current.locale
        formatter.maximumFractionDigits = 0
        return formatter.string(from: NSNumber(value: n)) ?? "\(n)"
    }

    static func duration(_ s: TimeInterval) -> String {
        s < 1 ? String(format: "%.0f ms", locale: AppLanguage.current.locale, s * 1000)
              : String(format: "%.1f s", locale: AppLanguage.current.locale, s)
    }
}
