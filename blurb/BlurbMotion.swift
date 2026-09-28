import SwiftUI

enum BlurbMotion {
    static let quick = Animation.smooth(duration: 0.18)
    static let standard = Animation.smooth(duration: 0.26)
    static let page = Animation.smooth(duration: 0.32)
    static let interactive = Animation.spring(response: 0.34, dampingFraction: 0.88)
}

struct BlurbAsyncImage<Content: View, Placeholder: View>: View {
    let url: URL?
    private let content: (Image) -> Content
    private let placeholder: () -> Placeholder

    init(
        url: URL?,
        @ViewBuilder content: @escaping (Image) -> Content,
        @ViewBuilder placeholder: @escaping () -> Placeholder
    ) {
        self.url = url
        self.content = content
        self.placeholder = placeholder
    }

    var body: some View {
        AsyncImage(url: url) { phase in
            switch phase {
            case .success(let image):
                content(image)
            default:
                placeholder()
            }
        }
    }
}
