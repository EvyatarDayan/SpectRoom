//
//  ChatVideoProcessor.swift
//  SpectRoom
//

import Foundation
import UIKit
import AVFoundation
import UniformTypeIdentifiers
import Photos
import PhotosUI

enum ChatVideoValidationError: Error, Equatable {
    case unsupportedFormat
    case fileTooLarge(maxMB: Int)
    case tooLong
    case processingFailed

    var alertTitleKey: String {
        switch self {
        case .unsupportedFormat: return "messages.video.error.format.title"
        case .fileTooLarge: return "messages.video.error.size.title"
        case .tooLong: return "messages.video.error.duration.title"
        case .processingFailed: return "messages.video.error.processing.title"
        }
    }

    var alertMessageKey: String {
        switch self {
        case .unsupportedFormat: return "messages.video.error.format"
        case .fileTooLarge: return "messages.video.error.size"
        case .tooLong: return "messages.video.error.duration"
        case .processingFailed: return "messages.video.error.processing"
        }
    }

    func alertMessage(planName: String, maxMB: Int = 10, canUpgrade: Bool = true) -> String {
        switch self {
        case .fileTooLarge(let mb):
            if canUpgrade {
                return String(format: "messages.video.error.size".localized, planName, mb)
            }
            return String(format: "messages.video.error.size.premium".localized, mb)
        default:
            return alertMessageKey.localized
        }
    }
}

struct PreparedChatVideo {
    let videoFileURL: URL
    let thumbnailJPEGData: Data
    let thumbnailImage: UIImage
    let duration: TimeInterval
    let fileExtension: String
    let contentType: String
}

/// Validates and compresses chat videos on-device before upload.
/// Plan byte caps apply to the **picked file** and the compressed upload (same idea as chat images).
enum ChatVideoProcessor {
    static let maxDuration: TimeInterval = 3 * 60
    static let maxExportHeight: CGFloat = 1080

    static let allowedTypeIdentifiers: Set<String> = [
        UTType.mpeg4Movie.identifier,
        UTType.quickTimeMovie.identifier,
        "public.mpeg-4",
        "com.apple.quicktime-movie",
        "org.webmproject.webm",
    ]

    static func maxBytes(for plan: PlanTier) -> Int {
        plan.maxVideoUploadBytes
    }

    static func isAllowedTypeIdentifier(_ identifier: String) -> Bool {
        let lower = identifier.lowercased()
        if allowedTypeIdentifiers.contains(where: { $0.lowercased() == lower }) { return true }
        return lower.contains("mpeg-4")
            || lower.contains("quicktime")
            || lower.hasSuffix(".mp4")
            || lower.hasSuffix(".mov")
            || lower.contains("webm")
    }

    static func matchingTypeIdentifier(for itemProvider: NSItemProvider) -> String? {
        for id in [
            UTType.mpeg4Movie.identifier,
            UTType.quickTimeMovie.identifier,
            "public.mpeg-4",
            "com.apple.quicktime-movie",
        ] where itemProvider.hasItemConformingToTypeIdentifier(id) {
            return id
        }
        if itemProvider.hasItemConformingToTypeIdentifier(UTType.movie.identifier) {
            return UTType.movie.identifier
        }
        return nil
    }

    private static func fileSizeBytes(at url: URL) -> Int? {
        guard let attrs = try? FileManager.default.attributesOfItem(atPath: url.path),
              let size = attrs[.size] as? NSNumber else {
            return nil
        }
        return size.intValue
    }

    /// Copy / export a picked video into a compressed MP4 under plan size + duration limits.
    static func prepareForUpload(
        sourceURL: URL,
        declaredTypeIdentifier: String?,
        plan: PlanTier
    ) async throws -> PreparedChatVideo {
        if let declaredTypeIdentifier,
           declaredTypeIdentifier != UTType.movie.identifier,
           !isAllowedTypeIdentifier(declaredTypeIdentifier) {
            throw ChatVideoValidationError.unsupportedFormat
        }

        let ext = sourceURL.pathExtension.lowercased()
        if !ext.isEmpty, !["mp4", "mov", "m4v", "webm"].contains(ext) {
            throw ChatVideoValidationError.unsupportedFormat
        }

        let maxBytes = maxBytes(for: plan)
        let maxMB = max(1, maxBytes / (1024 * 1024))

        // Enforce plan cap on the picked file (matches chat image original-size policy).
        guard let originalSize = fileSizeBytes(at: sourceURL), originalSize > 0 else {
            throw ChatVideoValidationError.processingFailed
        }
        guard originalSize <= maxBytes else {
            throw ChatVideoValidationError.fileTooLarge(maxMB: maxMB)
        }

        let asset = AVURLAsset(url: sourceURL)
        let duration = try await asset.load(.duration).seconds
        guard duration.isFinite, duration > 0.2 else {
            throw ChatVideoValidationError.processingFailed
        }
        guard duration <= maxDuration + 0.25 else {
            throw ChatVideoValidationError.tooLong
        }

        let thumbnail = try await makeThumbnail(from: asset)
        guard var thumbData = thumbnail.jpegData(compressionQuality: 0.55),
              thumbData.count > 0 else {
            throw ChatVideoValidationError.processingFailed
        }
        // Prefer ~20KB preview thumbnails for fast bubble load.
        var quality: CGFloat = 0.5
        while thumbData.count > 22 * 1024, quality > 0.25 {
            quality -= 0.08
            if let smaller = thumbnail.jpegData(compressionQuality: quality) {
                thumbData = smaller
            } else {
                break
            }
        }
        let thumbImage = UIImage(data: thumbData) ?? thumbnail

        let exportedURL = try await exportCompressedMP4(asset: asset, maxBytes: maxBytes)
        guard let exportedSize = fileSizeBytes(at: exportedURL),
              exportedSize > 0,
              exportedSize <= maxBytes else {
            try? FileManager.default.removeItem(at: exportedURL)
            throw ChatVideoValidationError.fileTooLarge(maxMB: maxMB)
        }

        return PreparedChatVideo(
            videoFileURL: exportedURL,
            thumbnailJPEGData: thumbData,
            thumbnailImage: thumbImage,
            duration: duration,
            fileExtension: "mp4",
            contentType: "video/mp4"
        )
    }

    private static func makeThumbnail(from asset: AVAsset) async throws -> UIImage {
        let generator = AVAssetImageGenerator(asset: asset)
        generator.appliesPreferredTrackTransform = true
        generator.maximumSize = CGSize(width: 480, height: 480)
        let time = CMTime(seconds: 0.05, preferredTimescale: 600)
        let cgImage = try await generator.image(at: time).image
        let image = UIImage(cgImage: cgImage)
        // Aim ~20KB: re-encode small JPEG
        if let data = image.jpegData(compressionQuality: 0.45),
           let compressed = UIImage(data: data) {
            return compressed
        }
        return image
    }

    private static func exportCompressedMP4(asset: AVAsset, maxBytes: Int) async throws -> URL {
        // Prefer ≤1080p, then step down until under the plan byte cap.
        let presets = [
            AVAssetExportPreset1920x1080,
            AVAssetExportPreset1280x720,
            AVAssetExportPreset960x540,
            AVAssetExportPreset640x480,
            AVAssetExportPresetMediumQuality,
            AVAssetExportPresetLowQuality,
        ]

        var sawOversizedExport = false
        var lastError: Error = ChatVideoValidationError.processingFailed
        for preset in presets {
            guard AVAssetExportSession.allExportPresets().contains(preset) else { continue }
            do {
                let url = try await exportOnce(asset: asset, preset: preset)
                let size = fileSizeBytes(at: url) ?? Int.max
                if size <= maxBytes {
                    return url
                }
                sawOversizedExport = true
                try? FileManager.default.removeItem(at: url)
            } catch {
                lastError = error
            }
        }
        let maxMB = max(1, maxBytes / (1024 * 1024))
        if sawOversizedExport {
            throw ChatVideoValidationError.fileTooLarge(maxMB: maxMB)
        }
        throw lastError
    }

    private static func exportOnce(asset: AVAsset, preset: String) async throws -> URL {
        guard let session = AVAssetExportSession(asset: asset, presetName: preset) else {
            throw ChatVideoValidationError.processingFailed
        }
        let outURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("chat_video_\(UUID().uuidString).mp4")
        try? FileManager.default.removeItem(at: outURL)
        session.outputURL = outURL
        session.outputFileType = .mp4
        session.shouldOptimizeForNetworkUse = true

        await session.export()
        switch session.status {
        case .completed:
            return outURL
        default:
            throw session.error ?? ChatVideoValidationError.processingFailed
        }
    }
}
