import SwiftProtobuf
@testable import TeslaBLE
import XCTest

final class VehicleSnapshotMapperTests: XCTestCase {
    func testEmptyVehicleDataProducesAllNils() {
        let data = CarServer_VehicleData()
        let snapshot = VehicleSnapshotMapper.map(data)
        XCTAssertNil(snapshot.charge)
        XCTAssertNil(snapshot.climate)
        XCTAssertNil(snapshot.drive)
        XCTAssertNil(snapshot.closures)
        XCTAssertNil(snapshot.tirePressure)
        XCTAssertNil(snapshot.media)
        XCTAssertNil(snapshot.mediaDetail)
        XCTAssertNil(snapshot.softwareUpdate)
        XCTAssertNil(snapshot.chargeSchedule)
        XCTAssertNil(snapshot.preconditionSchedule)
        XCTAssertNil(snapshot.parentalControls)
    }

    func testChargeStateMapping() {
        var data = CarServer_VehicleData()
        var charge = CarServer_ChargeState()
        charge.batteryLevel = 75
        charge.batteryRange = 250.5
        charge.estBatteryRange = 240.0
        charge.chargerVoltage = 240
        charge.chargerActualCurrent = 32
        charge.chargerPower = 7
        charge.chargeLimitSoc = 90
        charge.minutesToFullCharge = 120
        charge.chargeRateMph = 30
        charge.chargePortDoorOpen = true
        data.chargeState = charge

        let snapshot = VehicleSnapshotMapper.map(data)
        XCTAssertEqual(snapshot.charge?.batteryLevel, 75)
        XCTAssertEqual(snapshot.charge?.batteryRangeMiles ?? 0, Double(Float(250.5)), accuracy: 0.01)
        XCTAssertEqual(snapshot.charge?.estBatteryRangeMiles ?? 0, Double(Float(240.0)), accuracy: 0.01)
        XCTAssertEqual(snapshot.charge?.chargerVoltage, 240)
        XCTAssertEqual(snapshot.charge?.chargerCurrent, 32)
        XCTAssertEqual(snapshot.charge?.chargerPower, 7)
        XCTAssertEqual(snapshot.charge?.chargeLimitPercent, 90)
        XCTAssertEqual(snapshot.charge?.minutesToFullCharge, 120)
        XCTAssertEqual(snapshot.charge?.chargeRateMph, 30.0)
        XCTAssertEqual(snapshot.charge?.chargePortOpen, true)
    }

    func testDriveStateShiftMapping() {
        var data = CarServer_VehicleData()
        var drive = CarServer_DriveState()
        var shift = CarServer_ShiftState()
        shift.type = .d(CarServer_Void())
        drive.shiftState = shift
        drive.speedFloat = 42.0
        data.driveState = drive

        let snapshot = VehicleSnapshotMapper.map(data)
        XCTAssertEqual(snapshot.drive?.shiftState, .drive)
        XCTAssertEqual(snapshot.drive?.speedMph ?? 0, 42.0, accuracy: 0.001)
    }

    func testMapDriveOnlyReturnsDriveDTO() {
        var data = CarServer_VehicleData()
        var drive = CarServer_DriveState()
        var shift = CarServer_ShiftState()
        shift.type = .p(CarServer_Void())
        drive.shiftState = shift
        data.driveState = drive

        let result = VehicleSnapshotMapper.mapDrive(data)
        XCTAssertEqual(result.shiftState, .park)
    }
}
