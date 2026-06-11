import AVFoundation
import Foundation
import os

/// Plays an audio alert when a block happens — **in-process** via
/// AVFoundation.
///
/// Spawning `say`/`afplay` as a subprocess from a background launchd
/// agent does not route to the audio device on macOS. The daemon,
/// however, runs as an NSApplication (accessory) and therefore has a
/// working audio session, so in-process playback works.
///
/// Priority:
///   1. A user recording at Paths.blockAudioFile (m4a/mp3/wav/aiff),
///      played with AVAudioPlayer.
///   2. Fallback spoken phrase via AVSpeechSynthesizer (Hindi voice,
///      since macOS ships no Bengali voice).
///
/// Rate-limited so rapid re-detections don't stack overlapping audio.
@MainActor
public final class AudioAlerter {
    /// Devanagari approximation of the Bengali phrase (macOS has a
    /// Hindi voice, Lekha, but no Bengali one).
    public var fallbackPhrase: String
    /// BCP-47 language for the fallback voice, e.g. "hi-IN".
    public var fallbackLanguage: String
    public var minInterval: TimeInterval

    private let synthesizer = AVSpeechSynthesizer()
    private var player: AVAudioPlayer?
    private var lastPlayed = Date.distantPast
    private let log = Logger(subsystem: "com.selfcontrol.pornblocker", category: "audio")

    public init(
        fallbackPhrase: String = "निजेके कंट्रोल कर बेटा",
        fallbackLanguage: String = "hi-IN",
        minInterval: TimeInterval = 2.0
    ) {
        self.fallbackPhrase = fallbackPhrase
        self.fallbackLanguage = fallbackLanguage
        self.minInterval = minInterval
    }

    public func play() {
        let now = Date()
        guard now.timeIntervalSince(lastPlayed) >= minInterval else { return }
        lastPlayed = now

        if FileManager.default.fileExists(atPath: Paths.blockAudioFile.path) {
            playFile()
        } else {
            speakFallback()
        }
    }

    private func playFile() {
        do {
            let player = try AVAudioPlayer(contentsOf: Paths.blockAudioFile)
            player.prepareToPlay()
            player.play()
            self.player = player // retain until it finishes
            log.info("audio: playing recording")
        } catch {
            log.error("audio: file playback failed (\(String(describing: error))) — speaking fallback")
            speakFallback()
        }
    }

    private func speakFallback() {
        let utterance = AVSpeechUtterance(string: fallbackPhrase)
        utterance.voice = AVSpeechSynthesisVoice(language: fallbackLanguage)
        synthesizer.speak(utterance)
        log.info("audio: speaking fallback phrase")
    }
}
