import SwiftUI

public struct FlukeCard<Content: View>: View {
    private let content: Content

    public init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    public var body: some View {
        content
            .foregroundStyle(Color.abyss)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(16)
            .background(Color.bone, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .stroke(Color.mist, lineWidth: 1)
            }
    }
}
