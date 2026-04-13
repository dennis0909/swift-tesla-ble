import Foundation

public struct DriveStateDTO: Sendable, Equatable {
    public var shiftState: ShiftState?
    public var speedMph: Double?
    public var powerKW: Int?
    public var odometerHundredthsMile: Int?
    public var activeRouteDestination: String?
    public var activeRouteMinutesToArrival: Double?
    public var activeRouteMilesToArrival: Double?

    public enum ShiftState: Sendable, Equatable {
        case park
        case reverse
        case neutral
        case drive
    }

    public init(
        shiftState: ShiftState? = nil,
        speedMph: Double? = nil,
        powerKW: Int? = nil,
        odometerHundredthsMile: Int? = nil,
        activeRouteDestination: String? = nil,
        activeRouteMinutesToArrival: Double? = nil,
        activeRouteMilesToArrival: Double? = nil,
    ) {
        self.shiftState = shiftState
        self.speedMph = speedMph
        self.powerKW = powerKW
        self.odometerHundredthsMile = odometerHundredthsMile
        self.activeRouteDestination = activeRouteDestination
        self.activeRouteMinutesToArrival = activeRouteMinutesToArrival
        self.activeRouteMilesToArrival = activeRouteMilesToArrival
    }
}
