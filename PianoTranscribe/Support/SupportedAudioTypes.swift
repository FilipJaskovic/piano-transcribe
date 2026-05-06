import UniformTypeIdentifiers

extension UTType {
    static let mp3Audio = UTType(filenameExtension: "mp3") ?? .audio
    static let wavAudio = UTType(filenameExtension: "wav") ?? .audio
    static let aiffAudio = UTType(filenameExtension: "aiff") ?? .audio
    static let aifAudio = UTType(filenameExtension: "aif") ?? .audio
    static let m4aAudio = UTType(filenameExtension: "m4a") ?? .audio
    static let flacAudio = UTType(filenameExtension: "flac") ?? .audio
}

enum SupportedAudioTypes {
    static let extensions: Set<String> = [
        "mp3", "wav", "aif", "aiff", "m4a", "flac"
    ]

    static let importerTypes: [UTType] = [
        .mp3Audio, .wavAudio, .aiffAudio, .aifAudio, .m4aAudio, .flacAudio
    ]
}
