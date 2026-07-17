import Foundation
import Testing

@testable import FlukeFeatures

@Suite("Learn editorial content")
struct LearnContentTests {
    @Test("Articles have stable unique identity and complete reading content")
    func completeArticles() {
        let articles = LearnContent.articles
        #expect(articles.count >= 5)
        #expect(Set(articles.map(\.id)).count == articles.count)
        for article in articles {
            #expect(!article.id.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            #expect(!article.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            #expect(!article.summary.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            #expect(!article.sections.isEmpty)
            for section in article.sections {
                #expect(!section.heading.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                #expect(!section.body.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
    }

    @Test("Sources use labeled HTTPS links")
    func secureSources() {
        let sources = LearnContent.articles.flatMap(\.sources)
        #expect(!sources.isEmpty)
        for source in sources {
            #expect(!source.label.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            #expect(source.url.scheme == "https")
            #expect(source.url.host != nil)
        }
    }

    @Test("Release A reading copy makes no mutation or model promises")
    func readOnlyScope() {
        let copy = LearnContent.articles.flatMap { article in
            [article.title, article.summary]
                + article.sections.flatMap { [$0.heading, $0.body] }
        }.joined(separator: " ").lowercased()
        for forbidden in ["sign in", "account", "submit a sighting", "photo identification", "identify a whale"] {
            #expect(!copy.contains(forbidden))
        }
    }
}
