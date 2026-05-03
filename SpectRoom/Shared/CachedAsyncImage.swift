import SwiftUI
import UIKit

final class ImageCacheService {
    static let shared = ImageCacheService()
    private let cache = NSCache<NSString, UIImage>()
    private init() {}

    func image(for url: String) -> UIImage? {
        cache.object(forKey: url as NSString)
    }

    func insert(_ image: UIImage, for url: String) {
        cache.setObject(image, forKey: url as NSString)
    }
}

@MainActor
final class CachedImageLoader: ObservableObject {
    @Published var image: UIImage?
    private let url: URL?
    private var isLoading = false

    init(url: URL?) {
        self.url = url
    }

    func load() {
        guard !isLoading else { return }
        guard image == nil else { return }
        guard let url else { return }

        if let cached = ImageCacheService.shared.image(for: url.absoluteString) {
            image = cached
            return
        }

        isLoading = true

        Task {
            do {
                let (data, _) = try await URLSession.shared.data(from: url)
                if let uiImage = UIImage(data: data) {
                    ImageCacheService.shared.insert(uiImage, for: url.absoluteString)
                    await MainActor.run {
                        self.image = uiImage
                    }
                }
            } catch {
                // Optional: log error
            }

            await MainActor.run {
                self.isLoading = false
            }
        }
    }
}

struct CachedAsyncImage<Content: View, Placeholder: View>: View {
    @StateObject private var loader: CachedImageLoader
    private let content: (Image) -> Content
    private let placeholder: () -> Placeholder

    init(url: URL?, @ViewBuilder content: @escaping (Image) -> Content, @ViewBuilder placeholder: @escaping () -> Placeholder) {
        _loader = StateObject(wrappedValue: CachedImageLoader(url: url))
        self.content = content
        self.placeholder = placeholder
    }

    var body: some View {
        Group {
            if let uiImage = loader.image {
                content(Image(uiImage: uiImage))
            } else {
                placeholder()
            }
        }
        .onAppear {
            loader.load()
        }
    }
}

