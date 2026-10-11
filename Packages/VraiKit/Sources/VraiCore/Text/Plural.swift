import Foundation

public enum Plural {
    public static func pluralForm(of word: String) -> String {
        if word.wholeMatch(of: #/.*(?:s|x|ch|sh)/#) != nil { return word + "es" }
        if word.wholeMatch(of: #/.*[^aeiou]y/#) != nil { return String(word.dropLast()) + "ies" }
        return word + "s"
    }

    public static func grouped(_ count: Int) -> String {
        let formatter = NumberFormatter()
        formatter.locale = Locale(identifier: "en_US")
        formatter.numberStyle = .decimal
        formatter.usesGroupingSeparator = true
        return formatter.string(from: NSNumber(value: count)) ?? String(count)
    }
}

public func n(_ count: Int, _ word: String, _ plural: String? = nil) -> String {
    Plural.grouped(count) + " " + (count == 1 ? word : (plural ?? Plural.pluralForm(of: word)))
}
