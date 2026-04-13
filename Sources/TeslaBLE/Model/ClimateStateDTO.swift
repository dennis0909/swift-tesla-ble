import Foundation

public struct ClimateStateDTO: Sendable, Equatable {
    public var insideTempCelsius: Double?
    public var outsideTempCelsius: Double?
    public var driverTempSettingCelsius: Double?
    public var passengerTempSettingCelsius: Double?
    public var fanStatus: Int?
    public var isClimateOn: Bool?
    public var seatHeaterFrontLeft: SeatHeaterLevel?
    public var seatHeaterFrontRight: SeatHeaterLevel?
    public var seatHeaterRearLeft: SeatHeaterLevel?
    public var seatHeaterRearCenter: SeatHeaterLevel?
    public var seatHeaterRearRight: SeatHeaterLevel?
    public var steeringWheelHeater: Bool?
    public var isBatteryHeaterOn: Bool?
    public var defrostOn: Bool?
    public var bioweaponMode: Bool?

    public enum SeatHeaterLevel: Int, Sendable, Equatable {
        case off = 0
        case low = 1
        case medium = 2
        case high = 3
    }

    public init(
        insideTempCelsius: Double? = nil,
        outsideTempCelsius: Double? = nil,
        driverTempSettingCelsius: Double? = nil,
        passengerTempSettingCelsius: Double? = nil,
        fanStatus: Int? = nil,
        isClimateOn: Bool? = nil,
        seatHeaterFrontLeft: SeatHeaterLevel? = nil,
        seatHeaterFrontRight: SeatHeaterLevel? = nil,
        seatHeaterRearLeft: SeatHeaterLevel? = nil,
        seatHeaterRearCenter: SeatHeaterLevel? = nil,
        seatHeaterRearRight: SeatHeaterLevel? = nil,
        steeringWheelHeater: Bool? = nil,
        isBatteryHeaterOn: Bool? = nil,
        defrostOn: Bool? = nil,
        bioweaponMode: Bool? = nil,
    ) {
        self.insideTempCelsius = insideTempCelsius
        self.outsideTempCelsius = outsideTempCelsius
        self.driverTempSettingCelsius = driverTempSettingCelsius
        self.passengerTempSettingCelsius = passengerTempSettingCelsius
        self.fanStatus = fanStatus
        self.isClimateOn = isClimateOn
        self.seatHeaterFrontLeft = seatHeaterFrontLeft
        self.seatHeaterFrontRight = seatHeaterFrontRight
        self.seatHeaterRearLeft = seatHeaterRearLeft
        self.seatHeaterRearCenter = seatHeaterRearCenter
        self.seatHeaterRearRight = seatHeaterRearRight
        self.steeringWheelHeater = steeringWheelHeater
        self.isBatteryHeaterOn = isBatteryHeaterOn
        self.defrostOn = defrostOn
        self.bioweaponMode = bioweaponMode
    }
}
