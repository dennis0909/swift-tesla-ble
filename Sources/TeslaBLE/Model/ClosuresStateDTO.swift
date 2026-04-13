import Foundation

public struct ClosuresStateDTO: Sendable, Equatable {
    public var frontDriverDoor: Bool?
    public var frontPassengerDoor: Bool?
    public var rearDriverDoor: Bool?
    public var rearPassengerDoor: Bool?
    public var frontTrunk: Bool?
    public var rearTrunk: Bool?
    public var locked: Bool?
    public var windowDriverFront: Bool?
    public var windowPassengerFront: Bool?
    public var windowDriverRear: Bool?
    public var windowPassengerRear: Bool?
    public var sunroofState: SunroofState?
    public var sunroofPercentOpen: Int?
    public var sentryModeActive: Bool?
    public var valetMode: Bool?
    public var isUserPresent: Bool?

    public enum SunroofState: Sendable, Equatable {
        case closed
        case open
        case vent
        case moving
        case calibrating
        case unknown
    }

    public init(
        frontDriverDoor: Bool? = nil,
        frontPassengerDoor: Bool? = nil,
        rearDriverDoor: Bool? = nil,
        rearPassengerDoor: Bool? = nil,
        frontTrunk: Bool? = nil,
        rearTrunk: Bool? = nil,
        locked: Bool? = nil,
        windowDriverFront: Bool? = nil,
        windowPassengerFront: Bool? = nil,
        windowDriverRear: Bool? = nil,
        windowPassengerRear: Bool? = nil,
        sunroofState: SunroofState? = nil,
        sunroofPercentOpen: Int? = nil,
        sentryModeActive: Bool? = nil,
        valetMode: Bool? = nil,
        isUserPresent: Bool? = nil,
    ) {
        self.frontDriverDoor = frontDriverDoor
        self.frontPassengerDoor = frontPassengerDoor
        self.rearDriverDoor = rearDriverDoor
        self.rearPassengerDoor = rearPassengerDoor
        self.frontTrunk = frontTrunk
        self.rearTrunk = rearTrunk
        self.locked = locked
        self.windowDriverFront = windowDriverFront
        self.windowPassengerFront = windowPassengerFront
        self.windowDriverRear = windowDriverRear
        self.windowPassengerRear = windowPassengerRear
        self.sunroofState = sunroofState
        self.sunroofPercentOpen = sunroofPercentOpen
        self.sentryModeActive = sentryModeActive
        self.valetMode = valetMode
        self.isUserPresent = isUserPresent
    }
}
