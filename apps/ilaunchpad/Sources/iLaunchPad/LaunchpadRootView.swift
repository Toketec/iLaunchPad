import SwiftUI
import UniformTypeIdentifiers

struct LaunchpadRootView: View {
    @ObservedObject private var store = LayoutStore.shared
    @ObservedObject private var presentation = LaunchpadPresentation.shared
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @AppStorage("lastPage") private var currentPage = 0
    @AppStorage("iconScale") private var iconScale = 1.0
    @AppStorage("showNames") private var showNames = true
    @AppStorage("returnToFirstPage") private var returnToFirstPage = true
    @State private var searchText = ""
    @State private var focusRequest = 0
    @State private var openFolderID: String?
    @State private var folderExpanded = false
    @State private var folderSource = CGRect.zero
    @State private var folderClosing = false
    @State private var dragging: DragPayload?
    @State private var searchIndex: [ApplicationSearchEntry] = []
    @State private var selectedIndex: Int?
    @State private var folderSelection: Int?
    @State private var retainedPages: Set<Int> = []
    @State private var folderBackgroundGroups: [Int: [LaunchGroup]] = [:]
    @State private var resourceEpoch = 0

    private struct ResourceRequest: Equatable {
        let apps: [LaunchApp]
        let page: Int
        let epoch: Int
    }

    var body: some View {
        inputHandlers.alert("iLaunchPad", isPresented: Binding<Bool>(
            get: { store.lastError != nil },
            set: { if !$0 { store.lastError = nil } }
        )) {
            Button("好", role: .cancel) { store.lastError = nil }
        } message: { Text(store.lastError ?? "") }
    }

    private var canvas: some View {
        GeometryReader { geometry in
            let width = min(1480, geometry.size.width * 0.84)
            let top = max(108, geometry.size.height * 0.115)
            let bottom = max(120, geometry.size.height * 0.12)
            let height = max(320, geometry.size.height - top - bottom)
            let metrics = GridMetrics(width: width, height: height, iconScale: iconScale, showNames: showNames)
            let origin = CGPoint(x: (geometry.size.width - width) / 2, y: top)

            ZStack(alignment: .topLeading) {
                WallpaperBackdropView()
                    .ignoresSafeArea()
                    .overlay(Color.black.opacity(folderExpanded ? 0.14 : 0))
                    .contentShape(Rectangle())
                    .onTapGesture(perform: backgroundTapped)
                    .contextMenu { backgroundMenu }
                    .onDrop(of: [UTType.text.identifier], isTargeted: nil) { _ in
                        guard let payload = dragging else { return false }
                        return DragTracking.drop(NSEvent.mouseLocation, store: store, payload: payload)
                    }

                ZStack {
                    if searchText.isEmpty {
                        pagedGrid(metrics: metrics, origin: origin, viewportWidth: geometry.size.width)
                            .transition(.opacity)
                    } else {
                        searchGrid(metrics: metrics)
                            .transition(.opacity.combined(with: .scale(scale: 0.98)))
                    }
                }
                .frame(width: geometry.size.width, height: height)
                .position(x: geometry.size.width / 2, y: top + height / 2)
                .allowsHitTesting(!folderExpanded)

                searchBar
                    .position(x: geometry.size.width / 2, y: max(54, top * 0.46))
                    .opacity(folderExpanded ? 0 : 1)
                    .allowsHitTesting(openFolderID == nil)

                pageIndicator
                    .position(x: geometry.size.width / 2, y: geometry.size.height - bottom + 28)
                    .opacity(searchText.isEmpty && !folderExpanded ? 1 : 0)
                    .allowsHitTesting(searchText.isEmpty && openFolderID == nil)

                if store.isEditing {
                    Button("完成") { store.isEditing = false }
                        .buttonStyle(.plain)
                        .padding(.horizontal, 20).padding(.vertical, 10)
                        .glassEffect(.regular.interactive(), in: Capsule())
                        .position(x: geometry.size.width - 80, y: max(54, top * 0.46))
                        .zIndex(6)
                }

                if let folderID = openFolderID {
                    VisualEffectView(withinWindow: true)
                        .ignoresSafeArea()
                        .opacity(folderExpanded ? 1 : 0)
                        .allowsHitTesting(false)
                        .zIndex(3)
                    FolderOverlay(folderID: folderID, currentPage: currentPage,
                                  dragging: $dragging, expanded: folderExpanded,
                                  sourceFrame: folderSource,
                                  keyboardSelection: folderSelection,
                                  onClose: closeFolder,
                                  onCollapsed: { finishClosingFolder(folderID) }, onOpenApp: openApp)
                        .zIndex(4)
                }
                DragPageTracking(page: currentPage, count: store.pageCount) { currentPage = $0 }
                    .frame(width: geometry.size.width, height: geometry.size.height)
                    .allowsHitTesting(false)
            }
            .scaleEffect(reduceMotion ? 1 : 0.93 + 0.07 * presentation.progress)
            .opacity(presentation.progress)
            .onAppear {
                if returnToFirstPage { currentPage = 0 }
                clampPage()
            }
            .onReceive(NotificationCenter.default.publisher(for: Notification.Name("iLaunchPad.openSelectedFolder"))) { event in
                if let id = event.object as? String { openFolder(id, metrics: metrics, origin: origin) }
            }
        }
    }

    private var lifecycleHandlers: some View {
        canvas.preferredColorScheme(.dark)
        .task(id: store.allApps().sorted { $0.id < $1.id }) {
            let apps = store.allApps().filter { !$0.hidden }
            let index = await Task.detached(priority: .userInitiated) {
                apps.map { ApplicationSearchEntry(app: $0) }
            }.value
            guard !Task.isCancelled else { return }
            searchIndex = index
        }
        .task(id: ResourceRequest(apps: store.allApps().sorted { $0.id < $1.id }, page: currentPage, epoch: resourceEpoch)) {
            let pages = Array(store.layout.pages.indices).sorted {
                abs($0 - currentPage) < abs($1 - currentPage)
            }
            let apps = pages.flatMap { store.groups(on: $0).flatMap(\.apps) }.filter { !$0.hidden }
            await ApplicationIconCache.shared.warm(apps, revalidate: true)
        }
        .onChange(of: searchText) { _, _ in
            selectedIndex = searchResults.isEmpty ? nil : 0
            updatePagingEligibility()
        }
        .onChange(of: openFolderID) { _, _ in updatePagingEligibility() }
        .onChange(of: dragging != nil) { _, _ in
            updatePagingEligibility()
        }
        .onChange(of: store.pageCount) { _, _ in clampPage() }
        .onReceive(NotificationCenter.default.publisher(for: .launchpadWillPresent)) { event in
            var transaction = Transaction(animation: nil)
            transaction.disablesAnimations = true
            withTransaction(transaction) {
                store.isEditing = false
                if let page = event.object as? NSNumber { currentPage = page.intValue }
                searchText = ""
                openFolderID = nil
                store.dragOpenFolderID = nil
                folderExpanded = false
                folderClosing = false
                folderBackgroundGroups = [:]
                selectedIndex = nil
                updatePagingEligibility()
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .launchpadPresented)) { _ in
            resourceEpoch += 1
            focusRequest += 1
        }
        .onReceive(NotificationCenter.default.publisher(for: .launchpadDismissed)) { _ in
            store.finishDragPreview(commit: false)
            store.cancelFolderNamingRequest()
            dragging = nil
            store.isEditing = false
        }
    }

    private var inputHandlers: some View {
        lifecycleHandlers
        .onReceive(NotificationCenter.default.publisher(for: .launchpadEscape)) { _ in escape() }
        .onReceive(NotificationCenter.default.publisher(for: .launchpadPreviousPage)) { _ in changePage(-1) }
        .onReceive(NotificationCenter.default.publisher(for: .launchpadNextPage)) { _ in changePage(1) }
        .onReceive(NotificationCenter.default.publisher(for: .launchpadNavigate)) { event in
            if let code = event.object as? NSNumber { navigate(code.intValue) }
        }
        .onReceive(NotificationCenter.default.publisher(for: .launchpadActivate)) { _ in activateSelection() }
    }

    private var searchBar: some View {
        HStack(spacing: 5) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 13, weight: .regular))
                .foregroundStyle(.white.opacity(0.7))
                .accessibilityHidden(true)
            NativeSearchField(text: $searchText, onSubmit: activateSelection,
                              focusRequest: focusRequest, enabled: openFolderID == nil)
                .frame(width: 195, height: 22)
            Rectangle().fill(.white.opacity(0.15)).frame(width: 0.5, height: 14)
            Menu { backgroundMenu } label: {
                Image(systemName: "ellipsis.circle")
                    .font(.system(size: 15, weight: .regular))
                    .foregroundStyle(.white.opacity(0.8))
                    .frame(width: 22, height: 24)
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .fixedSize()
        }
        .padding(.horizontal, 11)
        .padding(.vertical, 7)
        .glassEffect(.regular, in: Capsule())
        .fixedSize()
    }

    @ViewBuilder private var backgroundMenu: some View {
        SettingsLink { Label("设置…", systemImage: "gearshape") }
            .keyboardShortcut(",", modifiers: .command)
        Divider()
        Button("刷新应用列表", systemImage: "arrow.clockwise") {
            ApplicationIconCache.shared.clear()
            store.refreshInstalledApplications()
        }
        Button("显示全部隐藏应用", systemImage: "eye") { store.showAllHiddenApps() }
        Divider()
        Button("退出 iLaunchPad", systemImage: "power") { NSApp.terminate(nil) }
    }

    private func pagedGrid(metrics: GridMetrics, origin: CGPoint, viewportWidth: CGFloat) -> some View {
        PagingSurface(currentPage: $currentPage, pageCount: store.pageCount, width: viewportWidth, height: metrics.height,
                      enabled: canPage, onSettled: { selectedIndex = nil; focusRequest += 1 }) {
        HStack(spacing: 0) {
            ForEach(0..<store.pageCount, id: \.self) { page in
                Group {
                if PageRealization.shouldRealize(page, current: currentPage, retained: retainedPages) {
                // While a folder is open, keep the page below the full-screen
                // blur visually stable. Group-internal reorder only updates the
                // foreground panel instead of invalidating the blurred backdrop.
                let groups = openFolderID == nil
                    ? store.groups(on: page)
                    : (folderBackgroundGroups[page] ?? store.groups(on: page))
                NativeLaunchGrid(groups: groups, store: store, allowsReordering: true,
                                 dragging: $dragging,
                                 onOpenFolder: { id in openFolder(id, metrics: metrics, origin: origin) },
                                 onOpenApp: openApp, metrics: metrics,
                                 keyboardSelection: page == currentPage ? selectedGroupID(groups) : nil,
                                 onBackgroundClick: backgroundTapped, folderDestinationPage: page)
                    .frame(width: metrics.width, height: metrics.height)
                    .onAppear { retainedPages.insert(page) }
                } else {
                    Color.clear.frame(width: metrics.width, height: metrics.height)
                }
                }
                // Retain realized pages for native drag source/receiver lifetime and
                // interrupted page animations; unvisited pages are geometry only.
                .frame(width: viewportWidth, height: metrics.height)
            }
        }
        }
    }

    private func searchGrid(metrics: GridMetrics) -> some View {
        let groups = searchResults.map { LaunchGroup(id: "search-" + $0.id, name: "", isFolder: false, apps: [$0]) }
        return NativeLaunchGrid(groups: groups, store: store, allowsReordering: false,
                                dragging: $dragging, onOpenFolder: { _ in }, onOpenApp: openApp,
                                metrics: metrics, keyboardSelection: selectedGroupID(groups),
                                onBackgroundClick: backgroundTapped)
            .frame(width: metrics.width, height: metrics.height)
            .overlay {
                if groups.isEmpty {
                    VStack(spacing: 12) {
                        Image(systemName: "magnifyingglass").font(.system(size: 34, weight: .light))
                        Text("没有找到应用").font(.system(size: 17))
                    }.foregroundStyle(.white.opacity(0.65))
                }
            }
    }

    private var searchResults: [LaunchApp] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
            .folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current)
        guard !query.isEmpty else { return [] }
        return searchIndex.compactMap { entry -> (LaunchApp, Int)? in
            entry.score(for: query).map { (entry.app, $0) }
        }.sorted { $0.1 < $1.1 }.map(\.0)
    }

    private var pageIndicator: some View {
        HStack(spacing: 2) {
            ForEach(0..<store.pageCount, id: \.self) { page in
                Button { goToPage(page) } label: {
                    Circle().fill(.white.opacity(page == currentPage ? 1 : 0.35))
                        .frame(width: 6, height: 6)
                        .frame(width: 20, height: 22)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("第 \(page + 1) 页")
            }
        }
        .padding(.horizontal, 8).padding(.vertical, 3)
        .glassEffect(.regular.interactive(), in: Capsule())
        .fixedSize()
    }

    @ViewBuilder private var pageEdgeDropZones: some View {
        if dragging != nil, openFolderID == nil, searchText.isEmpty {
            HStack {
                edgeDropZone(page: max(0, currentPage - 1))
                Spacer()
                edgeDropZone(page: min(store.pageCount - 1, currentPage + 1))
            }
            .padding(.horizontal, 5).padding(.vertical, 100)
        }
    }

    private func edgeDropZone(page: Int) -> some View {
        Color.white.opacity(0.001).frame(width: 40)
            .onDrop(of: [UTType.text.identifier],
                    delegate: PageDropDelegate(targetPage: page, store: store, currentPage: $currentPage, dragging: $dragging))
    }

    private var canPage: Bool { dragging == nil && openFolderID == nil && searchText.isEmpty }

    private func selectedGroupID(_ groups: [LaunchGroup]) -> String? {
        guard let index = selectedIndex, groups.indices.contains(index) else { return nil }
        return groups[index].id
    }

    private func updatePagingEligibility() { presentation.pagingEnabled = canPage }
    private func clampPage() { currentPage = min(max(currentPage, 0), store.pageCount - 1) }

    private func openFolder(_ id: String, metrics: GridMetrics, origin: CGPoint) {
        guard openFolderID == nil,
              let index = store.groups(on: currentPage).firstIndex(where: { $0.id == id }) else { return }
        var rect = store.temporaryFolderID == id
            ? (store.mergePreviewSourceFrame ?? metrics.iconRect(at: index))
            : metrics.iconRect(at: index)
        rect.origin.x += origin.x
        rect.origin.y += origin.y
        folderSource = rect.insetBy(dx: rect.width * 0.09, dy: rect.height * 0.09)
        folderClosing = false
        folderSelection = nil
        folderBackgroundGroups[currentPage] = store.groups(on: currentPage)
        openFolderID = id
        store.dragOpenFolderID = id
        store.dragRoutingPausedUntil = ProcessInfo.processInfo.systemUptime + LaunchpadMotion.folderDuration
        folderExpanded = false
        DispatchQueue.main.async {
            guard openFolderID == id, !folderClosing else { return }
            withAnimation(reduceMotion ? .easeOut(duration: 0.15) : LaunchpadMotion.folder) { folderExpanded = true }
        }
    }

    private func closeFolder() {
        guard let id = openFolderID, !folderClosing else { return }
        store.cancelFolderNamingRequest(folderID: id)
        folderClosing = true
        store.dragOpenFolderID = nil
        store.dragRoutingPausedUntil = ProcessInfo.processInfo.systemUptime + LaunchpadMotion.folderDuration
        guard folderExpanded else { finishClosingFolder(id); return }
        withAnimation(reduceMotion ? .easeOut(duration: 0.15) : LaunchpadMotion.folder) { folderExpanded = false }
    }

    private func finishClosingFolder(_ id: String) {
        guard openFolderID == id, folderClosing, !folderExpanded else { return }
        openFolderID = nil
        folderClosing = false
        folderBackgroundGroups = [:]
        store.dragRoutingPausedUntil = 0
        focusRequest += 1
    }

    private func openApp(_ app: LaunchApp) {
        store.open(app)
        LaunchpadWindowController.shared.hide()
    }

    private func backgroundTapped() {
        if store.isEditing { store.isEditing = false }
        else if openFolderID != nil { closeFolder() }
        else if !searchText.isEmpty { withAnimation(.easeOut(duration: 0.18)) { searchText = "" } }
        else { LaunchpadWindowController.shared.hide() }
    }

    private func escape() {
        if dragging != nil { store.finishDragPreview(commit: false); dragging = nil; return }
        if let editor = NSApp.keyWindow?.firstResponder as? NSTextView,
           editor.delegate is NSTextField, !(editor.delegate is NSSearchField) {
            NSApp.keyWindow?.makeFirstResponder(nil)
            return
        }
        backgroundTapped()
    }

    private func goToPage(_ page: Int) {
        guard canPage else { return }
        currentPage = min(max(page, 0), store.pageCount - 1)
        selectedIndex = nil
        focusRequest += 1
    }
    private func changePage(_ amount: Int) { goToPage(currentPage + amount) }

    private func navigate(_ code: Int) {
        let step = code == 123 ? -1 : code == 124 ? 1 : code == 126 ? -7 : 7
        if let folderID = openFolderID, let folder = store.group(id: folderID) {
            folderSelection = min(max((folderSelection ?? (step > 0 ? -step : 0)) + step, 0), folder.apps.count - 1)
            return
        }
        let count = searchText.isEmpty ? store.groups(on: currentPage).count : searchResults.count
        guard count > 0 else { return }
        let next = (selectedIndex ?? (step > 0 ? -step : 0)) + step
        if searchText.isEmpty && next >= count && currentPage + 1 < store.pageCount {
            changePage(1); selectedIndex = 0
        } else if searchText.isEmpty && next < 0 && currentPage > 0 {
            changePage(-1); selectedIndex = max(0, store.groups(on: currentPage).count - 1)
        } else {
            selectedIndex = min(max(next, 0), count - 1)
        }
    }

    private func activateSelection() {
        guard !store.isEditing else { return }
        if let folderID = openFolderID, let folder = store.group(id: folderID) {
            let index = folderSelection ?? 0
            if folder.apps.indices.contains(index) { openApp(folder.apps[index]) }
        } else if !searchText.isEmpty {
            let results = searchResults
            let index = selectedIndex ?? 0
            if results.indices.contains(index) { openApp(results[index]) }
        } else if let index = selectedIndex {
            let groups = store.groups(on: currentPage)
            guard groups.indices.contains(index) else { return }
            if let app = groups[index].apps.first, !groups[index].isFolder { openApp(app) }
            else {
                // The visible native collection supplies the same measured source frame as mouse activation.
                NotificationCenter.default.post(name: Notification.Name("iLaunchPad.openSelectedFolder"), object: groups[index].id)
            }
        }
    }
}
