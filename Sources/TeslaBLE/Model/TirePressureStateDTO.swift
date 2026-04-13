import Foundation

public struct TirePressureStateDTO: Sendable, Equatable {
    public struct Tire: Sendable, Equatable {
        public var pressureBar: Double?
        public var hasWarning: Bool?

        public init(pressureBar: Double? = nil, hasWarning: Bool? = nil) {
            self.pressureBar = pressureBar
            self.hasWarning = hasWarning
        }
    }

    public var frontLeft: Tire?
    public var frontRight: Tire?
    public var rearLeft: Tire?
    public var rearRight: Tire?
    public var recommendedColdFrontBar: Double?
    public var recommendedColdRearBar: Double?

    public init(
        frontLeft: Tire? = nil,
        frontRight: Tire? = nil,
        rearLeft: Tire? = nil,
        rearRight: Tire? = nil,
        recommendedColdFrontBar: Double? = nil,
        recommendedColdRearBar: Double? = nil,
    ) {
        self.frontLeft = frontLeft
        self.frontRight = frontRight
        self.rearLeft = rearLeft
        self.rearRight = rearRight
        self.recommendedColdFrontBar = recommendedColdFrontBar
        self.recommendedColdRearBar = recommendedColdRearBar
    }
}
