//
//  ChatImageProcessor.swift
//  SpectRoom
//

import Foundation
import UIKit
import ImageIO
import UniformTypeIdentifiers

enum ChatImageValidationError: Error, Equatable {
    case unsupportedFormat
    case fileTooLarge
    case processingFailed

    var alertMessageKey: String {
        switch self {
        case .unsupportedFormat: return "messages.image.error.format"
        case .fileTooLarge: return "messages.image.error.size"
        case .processingFailed: return "messages.image.error.processing"
        }
    }
}

/// Validates and prepares chat images for upload.
/// - Accepts: JPEG, PNG, GIF, HEIC/HEIF
/// - Downscales to max 2048px
/// - Compresses toward ~300KB (WebP preferred, JPEG fallback)
/// - Rejects originals over 5MB and outputs over 5MB
enum ChatImageProcessor {
    static let maxOriginalBytes = 5 * 1024 * 1024
    static let maxUploadBytes = 5 * 1024 * 1024
    static let targetUploadBytes = 300 * 1024
    static let maxDimension: CGFloat = 2048

    static let allowedTypeIdentifiers: [String] = [
        UTType.jpeg.identifier,
        UTType.png.identifier,
        UTType.gif.identifier,
        UTType.heic.identifier,
        UTType.heif.identifier,
        "public.jpeg",
        "public.png",
        "com.compuserve.gif",
        "public.heic",
        "public.heif",
    ]

    static func isAllowedTypeIdentifier(_ identifier: String) -> Bool {
        let lower = identifier.lowercased()
        return allowedTypeIdentifiers.contains { $0.lowercased() == lower }
            || lower.contains("jpeg")
            || lower.contains("jpg")
            || lower.contains("png")
            || lower.contains("gif")
            || lower.contains("heic")
            || lower.contains("heif")
    }

    /// Picks the first allowed type the item provider can supply.
    static func matchingTypeIdentifier(for itemProvider: NSItemProvider) -> String? {
        for id in allowedTypeIdentifiers where itemProvider.hasItemConformingToTypeIdentifier(id) {
            return id
        }
        // Some providers only advertise public.image — still try common subtypes via load later.
        if itemProvider.hasItemConformingToTypeIdentifier(UTType.image.identifier) {
            return UTType.image.identifier
        }
        return nil
    }

    static func validateOriginalData(_ data: Data, typeIdentifier: String?) throws {
        if let typeIdentifier, typeIdentifier != UTType.image.identifier {
            guard isAllowedTypeIdentifier(typeIdentifier) else {
                throw ChatImageValidationError.unsupportedFormat
            }
        }
        guard data.count <= maxOriginalBytes else {
            throw ChatImageValidationError.fileTooLarge
        }
    }

    /// Downscale + encode for Storage (WebP when possible, else JPEG). HEIC is decoded via UIImage.
    static func prepareForUpload(_ image: UIImage) throws -> (data: Data, contentType: String, fileExtension: String) {
        let normalized = image.normalizedUpOrientation()
        let scaled = normalized.scaledToMaxDimension(maxDimension)

        if let webP = encodeWebP(scaled, targetBytes: targetUploadBytes),
           webP.count <= maxUploadBytes {
            return (webP, "image/webp", "webp")
        }

        guard let jpeg = encodeJPEG(scaled, targetBytes: targetUploadBytes),
              jpeg.count <= maxUploadBytes else {
            throw ChatImageValidationError.fileTooLarge
        }
        return (jpeg, "image/jpeg", "jpg")
    }
}

// MARK: - Encoding

private extension ChatImageProcessor {
    static func encodeWebP(_ image: UIImage, targetBytes: Int) -> Data? {
        guard let cgImage = image.cgImage else { return nil }
        var quality: CGFloat = 0.82
        var best: Data?
        for _ in 0..<8 {
            guard let data = cgImageData(cgImage, type: .webP, quality: quality) else { break }
            best = data
            if data.count <= targetBytes { return data }
            quality = max(0.35, quality - 0.08)
        }
        return best
    }

    static func encodeJPEG(_ image: UIImage, targetBytes: Int) -> Data? {
        var quality: CGFloat = 0.82
        var best: Data?
        for _ in 0..<8 {
            guard let data = image.jpegData(compressionQuality: quality) else { break }
            best = data
            if data.count <= targetBytes { return data }
            quality = max(0.35, quality - 0.08)
        }
        return best
    }

    static func cgImageData(_ image: CGImage, type: UTType, quality: CGFloat) -> Data? {
        let data = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(
            data,
            type.identifier as CFString,
            1,
            nil
        ) else { return nil }
        let options: [CFString: Any] = [
            kCGImageDestinationLossyCompressionQuality: quality
        ]
        CGImageDestinationAddImage(destination, image, options as CFDictionary)
        guard CGImageDestinationFinalize(destination) else { return nil }
        return data as Data
    }
}

// MARK: - UIImage helpers

extension UIImage {
    func normalizedUpOrientation() -> UIImage {
        guard imageOrientation != .up else { return self }
        let format = UIGraphicsImageRendererFormat.default()
        format.scale = scale
        format.opaque = false
        let renderer = UIGraphicsImageRenderer(size: size, format: format)
        return renderer.image { _ in
            draw(in: CGRect(origin: .zero, size: size))
        }
    }

    func scaledToMaxDimension(_ maxDimension: CGFloat) -> UIImage {
        let width = size.width
        let height = size.height
        let longest = max(width, height)
        guard longest > maxDimension, longest > 0 else { return self }

        let scale = maxDimension / longest
        let newSize = CGSize(width: floor(width * scale), height: floor(height * scale))
        let format = UIGraphicsImageRendererFormat.default()
        format.scale = 1
        format.opaque = false
        let renderer = UIGraphicsImageRenderer(size: newSize, format: format)
        return renderer.image { _ in
            draw(in: CGRect(origin: .zero, size: newSize))
        }
    }
}
