import CryptoKit
import Foundation

/// Disk-backed cache for board images. There are only a couple of distinct
/// board photo URLs in the whole app, but plain AsyncImage(url:) was
/// re-fetching (and re-decoding) them from the network every single time a
/// climb was opened or a page changed - this makes that a one-time
/// download per launch (and across launches, since it's on disk).
actor ImageCache {
    static let shared = ImageCache()

    private var memory: [String: Data] = [:]
    private let dir: URL

    init() {
        let base = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first!
            .appendingPathComponent("TensionMirror/images", isDirectory: true)
        try? FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        dir = base
    }

    func data(for urlString: String) async throws -> Data {
        if let cached = memory[urlString] { return cached }

        let file = fileURL(for: urlString)
        if let onDisk = try? Data(contentsOf: file) {
            memory[urlString] = onDisk
            return onDisk
        }

        guard let url = URL(string: urlString) else { throw URLError(.badURL) }
        let (data, _) = try await URLSession.shared.data(from: url)
        try? data.write(to: file)
        memory[urlString] = data
        return data
    }

    private func fileURL(for urlString: String) -> URL {
        let digest = Insecure.MD5.hash(data: Data(urlString.utf8))
        let hex = digest.map { String(format: "%02x", $0) }.joined()
        return dir.appendingPathComponent(hex)
    }
}
