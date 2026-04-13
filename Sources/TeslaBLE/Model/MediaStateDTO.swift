import Foundation

public struct MediaStateDTO: Sendable, Equatable {
    public var nowPlayingArtist: String?
    public var nowPlayingTitle: String?
    public var audioVolume: Double?
    public var audioVolumeMax: Double?
    public var remoteControlEnabled: Bool?

    public init(
        nowPlayingArtist: String? = nil,
        nowPlayingTitle: String? = nil,
        audioVolume: Double? = nil,
        audioVolumeMax: Double? = nil,
        remoteControlEnabled: Bool? = nil,
    ) {
        self.nowPlayingArtist = nowPlayingArtist
        self.nowPlayingTitle = nowPlayingTitle
        self.audioVolume = audioVolume
        self.audioVolumeMax = audioVolumeMax
        self.remoteControlEnabled = remoteControlEnabled
    }
}
