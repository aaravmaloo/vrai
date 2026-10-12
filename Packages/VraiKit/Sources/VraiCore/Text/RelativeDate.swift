import Foundation
import Synchronization

public enum RelativeDate {
    private static let formatters = Mutex<[String: DateFormatter]>([:])
    private static let calendars = Mutex<[String: Calendar]>([:])

    static let minute = 60.0
    static let hour = 3600.0
    static let day = 86400.0

    public static func ago(_ date: Date, now: Date = Date(), timeZone: TimeZone = .current) -> String {
        let seconds = max(0, jsRound(now.timeIntervalSince1970 - date.timeIntervalSince1970))
        if seconds < 45 { return String(localized: "just now", bundle: .module) }
        if seconds < hour { return String(localized: "\(Int(jsRound(seconds / minute)))m ago", bundle: .module) }
        if seconds < day { return String(localized: "\(Int(jsRound(seconds / hour)))h ago", bundle: .module) }
        if seconds < 7 * day { return String(localized: "\(Int(jsRound(seconds / day)))d ago", bundle: .module) }
        let calendar = gregorian(timeZone)
        let sameYear = calendar.component(.year, from: date) == calendar.component(.year, from: now)
        let pattern = sameYear ? "MMM d" : "MMM d, y"
        return format(date, key: pattern, timeZone: timeZone) { $0.dateFormat = pattern }
    }

    static func gregorian(_ timeZone: TimeZone) -> Calendar {
        calendars.withLock { cache in
            if let calendar = cache[timeZone.identifier] { return calendar }
            var calendar = Calendar(identifier: .gregorian)
            calendar.timeZone = timeZone
            cache[timeZone.identifier] = calendar
            return calendar
        }
    }

    static func format(_ date: Date, key: String, timeZone: TimeZone, configure: (DateFormatter) -> Void) -> String {
        formatters.withLock { cache in
            let id = key + "|" + timeZone.identifier
            if let formatter = cache[id] { return formatter.string(from: date) }
            let formatter = DateFormatter()
            formatter.locale = Locale(identifier: "en_US")
            formatter.timeZone = timeZone
            configure(formatter)
            cache[id] = formatter
            return formatter.string(from: date)
        }
    }

    static func jsRound(_ value: Double) -> Double { (value + 0.5).rounded(.down) }

    public static func full(_ date: Date, timeZone: TimeZone = .current) -> String {
        format(date, key: "full", timeZone: timeZone) { formatter in
            formatter.dateStyle = .full
            formatter.timeStyle = .short
        }
    }
}

public func ago(_ date: Date, now: Date = Date()) -> String {
    RelativeDate.ago(date, now: now)
}
