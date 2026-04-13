import Foundation

public struct ParentalControlsStateDTO: Sendable, Equatable {
    public var active: Bool?
    public var pinSet: Bool?

    public init(active: Bool? = nil, pinSet: Bool? = nil) {
        self.active = active
        self.pinSet = pinSet
    }
}
