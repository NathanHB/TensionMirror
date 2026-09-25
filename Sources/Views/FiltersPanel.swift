import SwiftUI

/// Sidebar filters card, matching the web app's `.filters` column - used
/// both inline (macOS / regular-width iOS) and inside a sheet on compact
/// iPhone widths (see BrowseView).
struct FiltersPanel: View {
    @EnvironmentObject var appState: AppState
    @State private var nameDraft: String = ""
    @State private var nameDebounceTask: Task<Void, Never>?
    @State private var minQualityDraft: Double = 1.0
    @State private var moreExpanded = false

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            card {
                Toggle("Classics only", isOn: boolBinding(\.onlyClassics))
                Toggle("Favorites only", isOn: boolBinding(\.onlyFavorites))

                Divider()

                VStack(alignment: .leading, spacing: 6) {
                    Text("Grade").font(.caption.weight(.semibold))
                    HStack {
                        gradePicker(selection: minGradeBinding)
                        Text("to").font(.caption).foregroundStyle(AppColors.inkSoft)
                        gradePicker(selection: maxGradeBinding)
                    }
                }

                Divider()

                VStack(alignment: .leading, spacing: 6) {
                    Text("Angle").font(.caption.weight(.semibold))
                    FlowLayout(spacing: 6) {
                        ChipButton(label: "Any", isActive: appState.filters.angle == nil) {
                            updateFilters { $0.angle = nil }
                        }
                        if let board = appState.boardInfo {
                            ForEach(board.angles, id: \.self) { angle in
                                ChipButton(label: "\(angle)°", isActive: appState.filters.angle == angle) {
                                    updateFilters { $0.angle = angle }
                                }
                            }
                        }
                    }
                }

                Divider()

                VStack(alignment: .leading, spacing: 6) {
                    Text("Name").font(.caption.weight(.semibold))
                    TextField("Search climbs…", text: $nameDraft)
                        .textFieldStyle(.roundedBorder)
                        .onChange(of: nameDraft) { _, newValue in
                            nameDebounceTask?.cancel()
                            nameDebounceTask = Task {
                                try? await Task.sleep(nanoseconds: 300_000_000)
                                guard !Task.isCancelled else { return }
                                updateFilters { $0.name = newValue }
                            }
                        }
                }

                DisclosureGroup("More filters", isExpanded: $moreExpanded) {
                    VStack(alignment: .leading, spacing: 12) {
                        Stepper(
                            "Min ascents: \(appState.filters.minAscents)",
                            value: intBinding(\.minAscents),
                            in: 0...1000
                        )
                        .font(.caption)

                        VStack(alignment: .leading, spacing: 4) {
                            Text("Min quality: \(String(format: "%.1f", minQualityDraft)) ★")
                                .font(.caption)
                            Slider(value: $minQualityDraft, in: 0...3, step: 0.1) { editing in
                                if !editing {
                                    updateFilters { $0.minQuality = minQualityDraft }
                                }
                            }
                        }
                    }
                    .padding(.top, 8)
                }
                .font(.caption.weight(.semibold))
                .foregroundStyle(AppColors.inkSoft)
                .tint(AppColors.inkSoft)
            }

            card {
                Text("Sort by").font(.caption.weight(.semibold))
                HStack {
                    Picker("", selection: sortByBinding) {
                        Text("Difficulty").tag(ClimbRepository.SortField.difficulty)
                        Text("Ascents").tag(ClimbRepository.SortField.ascents)
                        Text("Quality").tag(ClimbRepository.SortField.quality)
                        Text("Name").tag(ClimbRepository.SortField.name)
                    }
                    .pickerStyle(.menu)
                    .labelsHidden()

                    Button {
                        updateFilters { $0.ascending.toggle() }
                    } label: {
                        Image(systemName: appState.filters.ascending ? "arrow.up" : "arrow.down")
                            .frame(width: 32, height: 32)
                            .background(AppColors.surface2)
                            .overlay(RoundedRectangle(cornerRadius: 8).stroke(AppColors.border))
                            .clipShape(RoundedRectangle(cornerRadius: 8))
                    }
                    .buttonStyle(.plain)
                }
            }

            Button {
                Task { await appState.refreshCatalog() }
            } label: {
                Label("Refresh board data", systemImage: "arrow.clockwise")
                    .font(.caption)
            }
            .buttonStyle(.plain)
            .foregroundStyle(AppColors.inkSoft)
            .disabled(appState.isDownloadingCatalog)
        }
        .onAppear {
            nameDraft = appState.filters.name
            minQualityDraft = appState.filters.minQuality
        }
    }

    private func card<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            content()
        }
        .padding(16)
        .background(AppColors.surface)
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(AppColors.border))
        .clipShape(RoundedRectangle(cornerRadius: 14))
    }

    private func gradePicker(selection: Binding<Int>) -> some View {
        Picker("", selection: selection) {
            if let board = appState.boardInfo {
                ForEach(board.grades, id: \.difficulty) { grade in
                    Text(grade.name).tag(grade.difficulty)
                }
            }
        }
        .pickerStyle(.menu)
        .labelsHidden()
    }

    private func updateFilters(_ mutate: @escaping (inout ClimbRepository.Filters) -> Void) {
        mutate(&appState.filters)
        Task { await appState.reload() }
    }

    private func boolBinding(_ keyPath: WritableKeyPath<ClimbRepository.Filters, Bool>) -> Binding<Bool> {
        Binding(
            get: { appState.filters[keyPath: keyPath] },
            set: { newValue in updateFilters { $0[keyPath: keyPath] = newValue } }
        )
    }

    private func intBinding(_ keyPath: WritableKeyPath<ClimbRepository.Filters, Int>) -> Binding<Int> {
        Binding(
            get: { appState.filters[keyPath: keyPath] },
            set: { newValue in updateFilters { $0[keyPath: keyPath] = newValue } }
        )
    }

    private var minGradeBinding: Binding<Int> {
        Binding(
            get: { appState.filters.minGrade },
            set: { newValue in
                updateFilters {
                    $0.minGrade = newValue
                    if newValue > $0.maxGrade { $0.maxGrade = newValue }
                }
            }
        )
    }

    private var maxGradeBinding: Binding<Int> {
        Binding(
            get: { appState.filters.maxGrade },
            set: { newValue in
                updateFilters {
                    $0.maxGrade = newValue
                    if newValue < $0.minGrade { $0.minGrade = newValue }
                }
            }
        )
    }

    private var sortByBinding: Binding<ClimbRepository.SortField> {
        Binding(
            get: { appState.filters.sortBy },
            set: { newValue in updateFilters { $0.sortBy = newValue } }
        )
    }
}
