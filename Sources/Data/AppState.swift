import Foundation

@MainActor
final class AppState: ObservableObject {
    let repository: ClimbRepository
    let bluetooth = BluetoothManager()
    let restTimer = RestTimer()

    @Published var boardInfo: BoardInfo?
    @Published var climbs: [Climb] = []
    @Published var total = 0
    @Published var isLoading = false
    @Published var isDownloadingCatalog = false
    @Published var errorMessage: String?

    @Published var filters: ClimbRepository.Filters
    @Published var page = 0

    let pageSize = 24

    init() {
        let db = TursoClient(url: Secrets.tursoURL, token: Secrets.tursoToken)
        self.repository = ClimbRepository(db: db, catalog: LocalCatalogStore())
        self.filters = ClimbRepository.Filters(minGrade: 1, maxGrade: 99)
    }

    func start() async {
        do {
            isDownloadingCatalog = true
            try await repository.ensureCatalogReady()
            isDownloadingCatalog = false

            let info = try await repository.fetchBoardInfo()
            boardInfo = info
            filters.minGrade = info.minGrade
            filters.maxGrade = info.maxGrade
            warmImageCache(for: info)
            await reload()
        } catch {
            isDownloadingCatalog = false
            errorMessage = "Couldn't load board info: \(error.localizedDescription)"
        }
    }

    /// Decodes the (usually 1-2) board images once in the background right
    /// after launch, off the main thread, so the first climb/plus-one-game
    /// open of the session is an instant cache hit instead of paying the
    /// decode cost right as the user is looking at it.
    private func warmImageCache(for info: BoardInfo) {
        for image in info.images {
            Task.detached(priority: .utility) {
                guard DecodedImageCache.shared.image(for: image.url) == nil else { return }
                guard let data = try? await ImageCache.shared.data(for: image.url), let decoded = PlatformImage(data: data) else { return }
                DecodedImageCache.shared.store(decoded, for: image.url)
            }
        }
    }

    /// Re-downloads the local catalog cache from Turso - use after
    /// re-running the export/sync scripts so new climbs/beta links show up.
    func refreshCatalog() async {
        do {
            isDownloadingCatalog = true
            try await repository.refreshCatalog()
            isDownloadingCatalog = false
            await reload()
        } catch {
            isDownloadingCatalog = false
            errorMessage = "Couldn't refresh catalog: \(error.localizedDescription)"
        }
    }

    func reload() async {
        page = 0
        await loadCurrentPage()
    }

    func loadNextPage() async {
        guard (page + 1) * pageSize < total else { return }
        page += 1
        await loadCurrentPage(append: false)
    }

    func loadPreviousPage() async {
        guard page > 0 else { return }
        page -= 1
        await loadCurrentPage(append: false)
    }

    private func loadCurrentPage(append: Bool = false) async {
        isLoading = true
        errorMessage = nil
        do {
            let result = try await repository.fetchClimbs(filters: filters, page: page, pageSize: pageSize)
            climbs = result.climbs
            total = result.total
        } catch {
            errorMessage = "Couldn't load climbs: \(error.localizedDescription)"
        }
        isLoading = false
    }

    func logTry(for climb: Climb) async {
        guard let index = climbs.firstIndex(where: { $0.id == climb.id }) else { return }
        do {
            let count = try await repository.logTry(uuid: climb.uuid, angle: climb.angle)
            climbs[index].tries = count
        } catch {
            errorMessage = "Couldn't log try: \(error.localizedDescription)"
        }
    }

    func logAscent(for climb: Climb) async {
        guard let index = climbs.firstIndex(where: { $0.id == climb.id }) else { return }
        do {
            let count = try await repository.logAscent(uuid: climb.uuid, angle: climb.angle)
            climbs[index].sent = true
            climbs[index].sendCount = count
        } catch {
            errorMessage = "Couldn't log ascent: \(error.localizedDescription)"
        }
    }

    func toggleFavorite(for climb: Climb) async {
        guard let index = climbs.firstIndex(where: { $0.id == climb.id }) else { return }
        do {
            let favorited = try await repository.toggleFavorite(uuid: climb.uuid, angle: climb.angle)
            climbs[index].favorited = favorited
            if filters.onlyFavorites && !favorited {
                climbs.remove(at: index)
                total -= 1
            }
        } catch {
            errorMessage = "Couldn't update favorite: \(error.localizedDescription)"
        }
    }
}
