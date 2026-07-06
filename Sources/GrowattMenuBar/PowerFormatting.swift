import Foundation

enum PowerFormatting {
    static func kilowatts(_ watts: Double, digits: Int = 2) -> String {
        let value = watts / 1000
        return "\(value.formatted(.number.precision(.fractionLength(digits)))) kW"
    }

    static func watts(_ watts: Double) -> String {
        "\(watts.formatted(.number.precision(.fractionLength(0)))) W"
    }

    static func number(_ value: Double, digits: Int = 1) -> String {
        value.formatted(.number.precision(.fractionLength(digits)))
    }
}
