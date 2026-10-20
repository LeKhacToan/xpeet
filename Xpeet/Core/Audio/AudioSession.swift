import AVFoundation

/// The shared audio session for listening and playing at once (specs/engine-sound-clip R9).
enum AudioSession {
    /// Play-and-record that mixes with the user's music and plays through the speaker or a car/Bluetooth output.
    /// No hands-free Bluetooth (HFP): that would switch the car into "call" mode and take over the input.
    static func activate() throws {
        let session = AVAudioSession.sharedInstance()
        try session.setCategory(.playAndRecord, mode: .default, options: [.mixWithOthers, .defaultToSpeaker, .allowBluetoothA2DP])
        try session.setActive(true)
        if let builtInMic = session.availableInputs?.first(where: { $0.portType == .builtInMic }) {
            try? session.setPreferredInput(builtInMic)
        }
    }

    static func deactivate() {
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }
}
