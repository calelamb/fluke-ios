import Testing

@testable import FlukeFeatures

@Suite("Third-party acknowledgements")
struct ThirdPartyNoticesTests {
    @Test("Fraunces acknowledgement carries its authorship and full license")
    func frauncesNoticeIsComplete() {
        let notice = ThirdPartyNotices.fraunces

        #expect(notice.name == "Fraunces")
        #expect(notice.copyright.contains("The Fraunces Project Authors"))
        #expect(notice.licenseName == "SIL Open Font License, Version 1.1")
        #expect(notice.licenseText.contains("PERMISSION & CONDITIONS"))
        #expect(notice.licenseText.contains("THE FONT SOFTWARE IS PROVIDED \"AS IS\""))
    }
}
