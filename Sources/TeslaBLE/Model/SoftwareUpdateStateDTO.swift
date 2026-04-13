import Foundation

public struct SoftwareUpdateStateDTO: Sendable, Equatable {
    public var version: String?
    public var downloadPercent: Int?
    public var installPercent: Int?
    public var expectedDurationSeconds: Int?

    public init(
        version: String? = nil,
        downloadPercent: Int? = nil,
        installPercent: Int? = nil,
        expectedDurationSeconds: Int? = nil,
    ) {
        self.version = version
        self.downloadPercent = downloadPercent
        self.installPercent = installPercent
        self.expectedDurationSeconds = expectedDurationSeconds
    }
}
