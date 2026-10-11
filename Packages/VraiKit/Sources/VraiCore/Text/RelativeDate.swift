import Foundation

public enum RelativeDate {
    static let minute = 60.0
    static let hour = 3600.0
    static let day = 86400.0

    public static func ago(_ date: Date, now: Date = Date(), timeZone: TimeZone = .current) -> String {
        let seconds = max(0, jsRound(now.timeIntervalSince1970 - date.timeIntervalSince1970))
        if seconds < 45 { return String(localized: "just now", bundle: .module) }
        if seconds < hour { return String(localized: "\(Int(jsRound(seconds / minute)))m ago", bundle: .module) }
        if seconds < day { return String(localized: "\(Int(jsRound(seconds / hour)))h ago", bundle: .module) }
        if seconds < 7 * day { return String(localized: "\(Int(jsRound(seconds / day)))d ago", bundle: .module) }
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        let sameYear = calendar.component(.year, from: date) == calendar.component(.year, from: now)
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US")
        formatter.timeZone = timeZone
        formatter.dateFormat = sameYear ? "MMM d" : "MMM d, y"
        return formatter.string(from: date)
    }

    static func jsRound(_ value: Double) -> Double { (value + 0.5).rounded(.down) }

    public static func full(_ date: Date, timeZone: TimeZone = .current) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US")
        formatter.timeZone = timeZone
        formatter.dateStyle = .full
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }
}

public func ago(_ date: Date, now: Date = Date()) -> String {
    RelativeDate.ago(date, now: now)
}
