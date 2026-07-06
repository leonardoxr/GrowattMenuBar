import Foundation

enum PowerFormatting {
    static func kilowatts(_ watts: Double) -> String {
        let value = watts / 1000
        return "\(value.formatted(.number.precision(.fractionLength(1)))) kW"
    }

    static func number(_ value: Double, digits: Int = 1) -> String {
        value.formatted(.number.precision(.fractionLength(digits)))
    }
}
