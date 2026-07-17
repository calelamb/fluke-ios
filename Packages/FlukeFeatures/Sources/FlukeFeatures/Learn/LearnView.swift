import FlukeUI
import SwiftUI

public struct LearnView: View {
    public init() {}

    public var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 14) {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Field notes for curious watchers")
                        .font(.flukeDisplayMedium)
                        .foregroundStyle(Color.abyss)
                        .accessibilityAddTraits(.isHeader)
                    Text("Read the public catalog with context, follow the evidence, and give wildlife room.")
                        .font(.flukeBody)
                        .foregroundStyle(Color.deep)
                }
                .padding(.bottom, 8)

                ForEach(LearnContent.articles) { article in
                    NavigationLink {
                        LearnArticleView(article: article)
                    } label: {
                        VStack(alignment: .leading, spacing: 7) {
                            Text(article.title)
                                .font(.flukeDisplaySmall)
                                .foregroundStyle(Color.abyss)
                            Text(article.summary)
                                .font(.flukeBody)
                                .foregroundStyle(Color.deep)
                                .multilineTextAlignment(.leading)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(16)
                        .background(Color.bone, in: RoundedRectangle(cornerRadius: 16))
                    }
                    .buttonStyle(.plain)
                    .accessibilityElement(children: .combine)
                    .accessibilityHint("Opens article")
                }
            }
            .frame(maxWidth: 680, alignment: .leading)
            .padding(20)
        }
        .background(Color.fog)
        .navigationTitle("Learn")
    }
}

private struct LearnArticleView: View {
    let article: LearnArticle

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                Text(article.summary)
                    .font(.flukeBody)
                    .foregroundStyle(Color.deep)
                    .textSelection(.enabled)
                ForEach(Array(article.sections.enumerated()), id: \.offset) { _, section in
                    VStack(alignment: .leading, spacing: 8) {
                        Text(section.heading)
                            .font(.flukeDisplaySmall)
                            .foregroundStyle(Color.abyss)
                            .accessibilityAddTraits(.isHeader)
                        Text(section.body)
                            .font(.flukeBody)
                            .foregroundStyle(Color.deep)
                            .textSelection(.enabled)
                    }
                }
                if !article.sources.isEmpty {
                    VStack(alignment: .leading, spacing: 10) {
                        Text("Sources")
                            .font(.flukeDisplaySmall)
                            .foregroundStyle(Color.abyss)
                            .accessibilityAddTraits(.isHeader)
                        ForEach(article.sources, id: \.url) { source in
                            Link(source.label, destination: source.url)
                                .font(.flukeBody.weight(.semibold))
                        }
                    }
                }
            }
            .frame(maxWidth: 680, alignment: .leading)
            .padding(20)
        }
        .background(Color.fog)
        .navigationTitle(article.title)
    }
}
