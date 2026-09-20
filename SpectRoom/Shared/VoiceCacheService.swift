//
//  VoiceCacheService.swift
//  SpectRoom
//

import CryptoKit
import Foundation

/// Disk cache for chat voice messages (mirrors image caching so reopen stays instant).
final class VoiceCacheService {
    static let shared = VoiceCacheService()

    private let fileManager = FileManager.default
    private let ioQueue = DispatchQueue(label: "com.spectroom.voice-cache", qos: .utility)
    private var inFlight: [String: Task<URL, Error>] = [:]
    private let lock = NSLock()

    private init() {}

    private var cacheDirectory: URL {
        let dir = fileManager.urls(for: .cachesDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("VoiceMessages", isDirectory: true)
        if !fileManager.fileExists(atPath: dir.path) {
            try? fileManager.createDirectory(at: dir, withIntermediateDirectories: true)
        }
        return dir
    }

    func cachedFileURL(for remoteURL: URL) -> URL? {
        let fileURL = cacheFileURL(for: remoteURL)
        guard fileManager.fileExists(atPath: fileURL.path) else { return nil }
        return fileURL
    }

    /// Returns a local file URL, downloading into the cache when needed.
    func localFileURL(for remoteURL: URL) async throws -> URL {
        if remoteURL.isFileURL {
            return remoteURL
        }

        if let cached = cachedFileURL(for: remoteURL) {
            return cached
        }

        let key = remoteURL.absoluteString
        lock.lock()
        if let existing = inFlight[key] {
            lock.unlock()
            return try await existing.value
        }
        let created = Task {
            defer {
                self.lock.lock()
                self.inFlight[key] = nil
                self.lock.unlock()
            }
            return try await self.downloadAndStore(remoteURL)
        }
        inFlight[key] = created
        lock.unlock()

        return try await created.value
    }

    private func downloadAndStore(_ remoteURL: URL) async throws -> URL {
        if let cached = cachedFileURL(for: remoteURL) {
            return cached
        }

        let (data, response) = try await URLSession.shared.data(from: remoteURL)
        if let http = response as? HTTPURLResponse, !(200...299).contains(http.statusCode) {
            throw URLError(.badServerResponse)
        }
        guard !data.isEmpty else {
            throw URLError(.zeroByteResource)
        }

        let destination = cacheFileURL(for: remoteURL)
        let temp = destination.appendingPathExtension("tmp")
        try data.write(to: temp, options: .atomic)
        if fileManager.fileExists(atPath: destination.path) {
            try? fileManager.removeItem(at: destination)
        }
        try fileManager.moveItem(at: temp, to: destination)
        return destination
    }

    private func cacheFileURL(for remoteURL: URL) -> URL {
        let digest = SHA256.hash(data: Data(remoteURL.absoluteString.utf8))
        let hex = digest.map { String(format: "%02x", $0) }.joined()
        let ext = remoteURL.pathExtension.isEmpty ? "m4a" : remoteURL.pathExtension
        return cacheDirectory.appendingPathComponent("\(hex).\(ext)", isDirectory: false)
    }
}
