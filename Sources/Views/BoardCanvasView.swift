import SwiftUI

/// Renders the board image(s) with holds overlaid as colored circles.
/// `litHolds`: placementId -> hex color (with "#") to highlight; anything
/// not in this map is invisible, same behavior as the web app's SVG.
struct BoardCanvasView: View {
    let images: [BoardImage]
    let edgeLeft: Int
    let edgeRight: Int
    let edgeBottom: Int
    let edgeTop: Int
    let litHolds: [Int: Color]
    var onTapHold: ((Int) -> Void)?

    var body: some View {
        GeometryReader { geometry in
            ZStack {
                ForEach(images) { image in
                    CachedBoardImage(urlString: image.url)
                        .frame(width: geometry.size.width, height: geometry.size.height)
                }
                ForEach(images) { image in
                    ForEach(image.holds) { hold in
                        holdView(hold, in: geometry.size)
                    }
                }
            }
        }
        .aspectRatio(imageAspectRatio, contentMode: .fit)
    }

    private var imageAspectRatio: CGFloat {
        CGFloat(edgeRight - edgeLeft) / CGFloat(edgeTop - edgeBottom)
    }

    private func holdView(_ hold: BoardHold, in size: CGSize) -> some View {
        let xSpacing = size.width / CGFloat(edgeRight - edgeLeft)
        let ySpacing = size.height / CGFloat(edgeTop - edgeBottom)
        let cx = CGFloat(hold.x - edgeLeft) * xSpacing
        let cy = size.height - CGFloat(hold.y - edgeBottom) * ySpacing
        let radius = xSpacing * 4
        let color = litHolds[hold.placementId]

        return Circle()
            .strokeBorder(color ?? .clear, lineWidth: 3)
            .frame(width: radius * 2, height: radius * 2)
            .contentShape(Circle())
            .position(x: cx, y: cy)
            .onTapGesture { onTapHold?(hold.placementId) }
    }
}

#if os(macOS)
typealias PlatformImage = NSImage
#else
typealias PlatformImage = UIImage
#endif

/// Decoding a full-resolution board photo from raw bytes isn't free - doing
/// it on every single appearance of CachedBoardImage below (every climb
/// opened, every +1 Game tab visit) is what caused the still-noticeable
/// delay even after ImageCache made the raw bytes disk-cached. This keeps
/// the already-decoded image in memory for the rest of the session, so
/// every appearance after the first is a synchronous cache hit with zero
/// decode cost and no flash-then-pop-in.
final class DecodedImageCache {
    static let shared = DecodedImageCache()
    private let cache = NSCache<NSString, PlatformImage>()

    func image(for key: String) -> PlatformImage? {
        cache.object(forKey: key as NSString)
    }

    func store(_ image: PlatformImage, for key: String) {
        cache.setObject(image, forKey: key as NSString)
    }
}

/// Loads a board image through ImageCache (disk-backed bytes) and
/// DecodedImageCache (in-memory decoded image) instead of AsyncImage's
/// network-and-decode-every-time behavior.
struct CachedBoardImage: View {
    let urlString: String
    @State private var image: PlatformImage?

    init(urlString: String) {
        self.urlString = urlString
        _image = State(initialValue: DecodedImageCache.shared.image(for: urlString))
    }

    var body: some View {
        Group {
            if let image {
                #if os(macOS)
                Image(nsImage: image).resizable()
                #else
                Image(uiImage: image).resizable()
                #endif
            } else {
                Color.clear
            }
        }
        .task(id: urlString) {
            guard image == nil else { return }
            guard let data = try? await ImageCache.shared.data(for: urlString), let decoded = PlatformImage(data: data) else { return }
            DecodedImageCache.shared.store(decoded, for: urlString)
            image = decoded
        }
    }
}
