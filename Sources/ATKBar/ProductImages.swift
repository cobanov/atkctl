import AppKit

/// Product images from ATK's CDN, the same files ATK Hub shows, kept in the user's cache folder.
@MainActor
final class ProductImages: ObservableObject {
    static let shared = ProductImages()

    @Published private var loaded: [String: NSImage] = [:]
    private var pending: Set<String> = []

    nonisolated private static let cdn = URL(string: "https://bpcdn.atkgear.com/device/ossAssets/")!
    nonisolated private static let folder = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
        .appendingPathComponent("dev.cobanov.atkbar/images", isDirectory: true)

    /// The image if it is at hand; otherwise starts fetching it and returns nil until it arrives.
    func image(_ path: String) -> NSImage? {
        if let image = loaded[path] { return image }
        if let image = Self.cached(path) {
            DispatchQueue.main.async { self.loaded[path] = image }
            return image
        }
        guard !pending.contains(path) else { return nil }
        pending.insert(path)
        URLSession.shared.dataTask(with: Self.cdn.appendingPathComponent(path)) { data, response, _ in
            guard let data, (response as? HTTPURLResponse)?.statusCode == 200, let image = NSImage(data: data) else { return }
            try? FileManager.default.createDirectory(at: Self.folder, withIntermediateDirectories: true)
            try? data.write(to: Self.file(path))
            DispatchQueue.main.async {
                self.pending.remove(path)
                self.loaded[path] = image
            }
        }.resume()
        return nil
    }

    /// Waits for the image; for `--render-preview`, which draws once and exits.
    nonisolated static func load(_ path: String) -> NSImage? {
        if let image = cached(path) { return image }
        guard let data = try? Data(contentsOf: cdn.appendingPathComponent(path)), let image = NSImage(data: data) else {
            return nil
        }
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try? data.write(to: file(path))
        return image
    }

    nonisolated private static func cached(_ path: String) -> NSImage? {
        NSImage(contentsOf: file(path))
    }

    nonisolated private static func file(_ path: String) -> URL {
        folder.appendingPathComponent(path.replacingOccurrences(of: "/", with: "_"))
    }
}

/// Which colour of a model the user has; ATK Hub asks the same, as the mouse cannot tell.
enum SkinChoice {
    static func current(for pid: Int, look: ModelLook) -> (name: String, path: String)? {
        let name = UserDefaults.standard.string(forKey: key(pid))
        return look.skins.first { $0.name == name } ?? look.skins.first
    }

    static func set(_ name: String, for pid: Int) {
        UserDefaults.standard.set(name, forKey: key(pid))
    }

    private static func key(_ pid: Int) -> String { "skin.\(String(format: "%04X", pid))" }
}
