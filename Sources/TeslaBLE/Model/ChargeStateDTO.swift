import Foundation

public struct ChargeStateDTO: Sendable, Equatable {
    public var batteryLevel: Int?
    public var batteryRangeMiles: Double?
    public var estBatteryRangeMiles: Double?
    public var chargingStatus: ChargingStatus?
    public var chargerVoltage: Int?
    public var chargerCurrent: Int?
    public var chargerPower: Int?
    public var chargeLimitPercent: Int?
    public var minutesToFullCharge: Int?
    public var chargeRateMph: Double?
    public var chargePortOpen: Bool?
    public var chargePortLatched: Bool?

    public enum ChargingStatus: Sendable, Equatable {
        case disconnected
        case charging
        case complete
        case stopped
        case starting
    }

    public init(
        batteryLevel: Int? = nil,
        batteryRangeMiles: Double? = nil,
        estBatteryRangeMiles: Double? = nil,
        chargingStatus: ChargingStatus? = nil,
        chargerVoltage: Int? = nil,
        chargerCurrent: Int? = nil,
        chargerPower: Int? = nil,
        chargeLimitPercent: Int? = nil,
        minutesToFullCharge: Int? = nil,
        chargeRateMph: Double? = nil,
        chargePortOpen: Bool? = nil,
        chargePortLatched: Bool? = nil,
    ) {
        self.batteryLevel = batteryLevel
        self.batteryRangeMiles = batteryRangeMiles
        self.estBatteryRangeMiles = estBatteryRangeMiles
        self.chargingStatus = chargingStatus
        self.chargerVoltage = chargerVoltage
        self.chargerCurrent = chargerCurrent
        self.chargerPower = chargerPower
        self.chargeLimitPercent = chargeLimitPercent
        self.minutesToFullCharge = minutesToFullCharge
        self.chargeRateMph = chargeRateMph
        self.chargePortOpen = chargePortOpen
        self.chargePortLatched = chargePortLatched
    }
}
