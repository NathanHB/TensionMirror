import SwiftUI

struct BrowseView: View {
    @EnvironmentObject var appState: AppState
    @State private var showFiltersSheet = false
    @State private var selectedClimb: Climb?

    #if os(iOS)
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    #endif

    private var useSidebarLayout: Bool {
        #if os(macOS)
        true
        #else
        horizontalSizeClass == .regular
        #endif
    }

    private let gridColumns = [GridItem(.adaptive(minimum: 240), spacing: 12)]

    var body: some View {
        Group {
            if useSidebarLayout {
                ScrollView {
                    HStack(alignment: .top, spacing: 24) {
                        FiltersPanel().frame(width: 280)
                        resultsColumn
                    }
                    .padding(24)
                }
            } else {
                NavigationStack {
                    ScrollView { resultsColumn.padding(16) }
                        .background(AppColors.bg)
                        .toolbar {
                            ToolbarItem(placement: .primaryAction) {
                                Button { showFiltersSheet = true } label: {
                                    Image(systemName: "slider.horizontal.3")
                                }
                            }
                        }
                        .sheet(isPresented: $showFiltersSheet) {
                            NavigationStack {
                                ScrollView { FiltersPanel().padding() }
                                    .background(AppColors.bg)
                                    .navigationTitle("Filters")
                                    #if os(iOS)
                                    .navigationBarTitleDisplayMode(.inline)
                                    #endif
                                    .toolbar {
                                        ToolbarItem(placement: .confirmationAction) {
                                            Button("Done") { showFiltersSheet = false }
                                        }
                                    }
                            }
                        }
                }
            }
        }
        .background(AppColors.bg)
        .task { if appState.boardInfo == nil { await appState.start() } }
        .sheet(item: $selectedClimb) { climb in
            ClimbDetailView(climb: climb)
                .environmentObject(appState)
                .environmentObject(appState.bluetooth)
        }
    }

    private var resultsColumn: some View {
        VStack(alignment: .leading, spacing: 14) {
            resultsHeader
            content
        }
        .frame(maxWidth: .infinity)
    }

    private var resultsHeader: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(resultsCountText)
                .font(.system(size: 14))
                .foregroundStyle(AppColors.inkSoft)
            Spacer()
            HStack(spacing: 10) {
                Button {
                    Task { await appState.loadPreviousPage() }
                } label: {
                    Image(systemName: "chevron.left")
                        .frame(width: 30, height: 30)
                        .background(AppColors.surface)
                        .overlay(Circle().stroke(AppColors.border))
                        .clipShape(Circle())
                }
                .buttonStyle(.plain)
                .disabled(appState.page == 0)
                .opacity(appState.page == 0 ? 0.35 : 1)

                Text("Page \(appState.page + 1) of \(totalPages)")
                    .font(.caption)
                    .foregroundStyle(AppColors.inkSoft)

                Button {
                    Task { await appState.loadNextPage() }
                } label: {
                    Image(systemName: "chevron.right")
                        .frame(width: 30, height: 30)
                        .background(AppColors.surface)
                        .overlay(Circle().stroke(AppColors.border))
                        .clipShape(Circle())
                }
                .buttonStyle(.plain)
                .disabled((appState.page + 1) * appState.pageSize >= appState.total)
                .opacity((appState.page + 1) * appState.pageSize >= appState.total ? 0.35 : 1)
            }
        }
    }

    private var totalPages: Int { max(1, Int(ceil(Double(appState.total) / Double(appState.pageSize)))) }

    private var resultsCountText: String {
        if appState.isLoading && appState.climbs.isEmpty { return "Loading climbs…" }
        return appState.total == 1 ? "1 climb" : "\(appState.total) climbs"
    }

    @ViewBuilder
    private var content: some View {
        if let error = appState.errorMessage {
            emptyState("Couldn't load climbs", detail: error)
        } else if appState.isDownloadingCatalog {
            VStack(spacing: 8) {
                ProgressView()
                Text("Downloading board data…").font(.caption).foregroundStyle(AppColors.inkSoft)
            }
            .frame(maxWidth: .infinity, minHeight: 200)
        } else if appState.climbs.isEmpty && appState.isLoading {
            ProgressView().frame(maxWidth: .infinity, minHeight: 200)
        } else if appState.climbs.isEmpty {
            emptyState("No climbs match these filters", detail: nil)
        } else {
            LazyVGrid(columns: gridColumns, spacing: 12) {
                ForEach(appState.climbs) { climb in
                    ClimbCardView(
                        climb: climb,
                        onTap: { selectedClimb = climb },
                        onToggleFavorite: { Task { await appState.toggleFavorite(for: climb) } }
                    )
                }
            }
        }
    }

    private func emptyState(_ title: String, detail: String?) -> some View {
        VStack(spacing: 4) {
            Text(title).font(.headline).foregroundStyle(AppColors.inkSoft)
            if let detail {
                Text(detail).font(.caption).foregroundStyle(AppColors.inkSoft)
            }
        }
        .frame(maxWidth: .infinity, minHeight: 200)
    }
}
