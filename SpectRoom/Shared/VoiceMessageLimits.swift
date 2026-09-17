//
//  VoiceMessageLimits.swift
//  SpectRoom
//

import Foundation
import AVFoundation

/// Voice note limits for chat recordings.
enum VoiceMessageLimits {
    /// Maximum recording length (1 minute).
    static let maxDuration: TimeInterval = 60

    /// Target: a full minute should generally stay under ~1 MB.
    static let targetMaxBytes = 1 * 1024 * 1024

    /// AAC in an `.m4a` container — widely supported and efficient at speech bitrates.
    static var recorderSettings: [String: Any] {
        [
            AVFormatIDKey: Int(kAudioFormatMPEG4AAC),
            AVSampleRateKey: 24_000,
            AVNumberOfChannelsKey: 1,
            AVEncoderBitRateKey: 64_000, // ~480 KB/min mono
            AVEncoderAudioQualityKey: AVAudioQuality.medium.rawValue
        ]
    }
}
