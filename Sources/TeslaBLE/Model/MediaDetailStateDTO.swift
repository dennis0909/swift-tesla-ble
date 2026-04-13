import Foundation

public struct MediaDetailStateDTO: Sendable, Equatable {
    public var nowPlayingDurationSeconds: Double?
    public var nowPlayingElapsedSeconds: Double?
    public var nowPlayingAlbum: String?
    public var nowPlayingStation: String?
    public var nowPlayingSource: String?
    public var a2dpSourceName: String?

    public init(
        nowPlayingDurationSeconds: Double? = nil,
        nowPlayingElapsedSeconds: Double? = nil,
        nowPlayingAlbum: String? = nil,
        nowPlayingStation: String? = nil,
        nowPlayingSource: String? = nil,
        a2dpSourceName: String? = nil,
    ) {
        self.nowPlayingDurationSeconds = nowPlayingDurationSeconds
        self.nowPlayingElapsedSeconds = nowPlayingElapsedSeconds
        self.nowPlayingAlbum = nowPlayingAlbum
        self.nowPlayingStation = nowPlayingStation
        self.nowPlayingSource = nowPlayingSource
        self.a2dpSourceName = a2dpSourceName
    }
}
