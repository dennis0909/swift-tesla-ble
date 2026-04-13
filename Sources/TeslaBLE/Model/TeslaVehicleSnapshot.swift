import Foundation

public struct TeslaVehicleSnapshot: Sendable, Equatable {
    public var charge: ChargeStateDTO?
    public var climate: ClimateStateDTO?
    public var drive: DriveStateDTO?
    public var closures: ClosuresStateDTO?
    public var tirePressure: TirePressureStateDTO?
    public var media: MediaStateDTO?
    public var mediaDetail: MediaDetailStateDTO?
    public var softwareUpdate: SoftwareUpdateStateDTO?
    public var chargeSchedule: ChargeScheduleStateDTO?
    public var preconditionSchedule: PreconditionScheduleStateDTO?
    public var parentalControls: ParentalControlsStateDTO?

    public init(
        charge: ChargeStateDTO? = nil,
        climate: ClimateStateDTO? = nil,
        drive: DriveStateDTO? = nil,
        closures: ClosuresStateDTO? = nil,
        tirePressure: TirePressureStateDTO? = nil,
        media: MediaStateDTO? = nil,
        mediaDetail: MediaDetailStateDTO? = nil,
        softwareUpdate: SoftwareUpdateStateDTO? = nil,
        chargeSchedule: ChargeScheduleStateDTO? = nil,
        preconditionSchedule: PreconditionScheduleStateDTO? = nil,
        parentalControls: ParentalControlsStateDTO? = nil,
    ) {
        self.charge = charge
        self.climate = climate
        self.drive = drive
        self.closures = closures
        self.tirePressure = tirePressure
        self.media = media
        self.mediaDetail = mediaDetail
        self.softwareUpdate = softwareUpdate
        self.chargeSchedule = chargeSchedule
        self.preconditionSchedule = preconditionSchedule
        self.parentalControls = parentalControls
    }
}
