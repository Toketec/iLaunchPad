import AppKit
import SwiftUI

struct AppIconView: View {
    let app: LaunchApp
    var size: CGFloat = 92

    var body: some View {
        Image(nsImage: icon)
            .resizable()
            .interpolation(.high)
            .aspectRatio(contentMode: .fit)
            .frame(width: size, height: size)
            .opacity(iconExists ? 1 : 0.45)
    }

    private var iconExists: Bool {
        ApplicationIconCache.shared.isAvailable(app)
    }

    private var icon: NSImage {
        return ApplicationIconCache.shared.image(for: app)
    }
}

struct FolderIconView: View {
    let folder: LaunchGroup
    var size: CGFloat = 92

    private let columns = Array(repeating: GridItem(.fixed(22), spacing: 3), count: 3)

    var body: some View {
        ZStack {
            LazyVGrid(columns: columns, spacing: 3) {
                ForEach(Array(folder.apps.prefix(9))) { app in
                    AppIconView(app: app, size: 22)
                        .shadow(radius: 0)
                }
            }
            .padding(8)
        }
        .frame(width: size, height: size)
        .glassEffect(.regular, in: RoundedRectangle(cornerRadius: size * 0.24, style: .continuous))
    }
}
