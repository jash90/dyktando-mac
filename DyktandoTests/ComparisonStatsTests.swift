import XCTest
@testable import Dyktando

final class ComparisonStatsTests: XCTestCase {
    private func tmpUrl() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("stats-\(UUID()).json")
    }

    func test_majorityWinnerOver10Picks_triggersNudge() async {
        let stats = ComparisonStats(url: tmpUrl())
        for _ in 0..<8 {
            await stats.record(chosen: .parakeetTDTv3, language: Locale(identifier: "pl-PL"))
        }
        for _ in 0..<2 {
            await stats.record(chosen: .whisperLargeV3, language: Locale(identifier: "pl-PL"))
        }
        let nudge = await stats.nudgeIfApplicable(for: Locale(identifier: "pl-PL"))
        XCTAssertEqual(nudge?.winner, .parakeetTDTv3)
        XCTAssertEqual(nudge?.winRate ?? 0, 0.8, accuracy: 0.0001)
    }

    func test_underTenPicks_noNudge() async {
        let stats = ComparisonStats(url: tmpUrl())
        for _ in 0..<5 {
            await stats.record(chosen: .parakeetTDTv3, language: Locale(identifier: "pl-PL"))
        }
        let nudge = await stats.nudgeIfApplicable(for: Locale(identifier: "pl-PL"))
        XCTAssertNil(nudge)
    }

    func test_belowSeventyPercentMajority_noNudge() async {
        let stats = ComparisonStats(url: tmpUrl())
        for _ in 0..<6 {
            await stats.record(chosen: .parakeetTDTv3, language: Locale(identifier: "pl-PL"))
        }
        for _ in 0..<4 {
            await stats.record(chosen: .whisperLargeV3, language: Locale(identifier: "pl-PL"))
        }
        let nudge = await stats.nudgeIfApplicable(for: Locale(identifier: "pl-PL"))
        XCTAssertNil(nudge)
    }

    func test_persistAndRestore() async {
        let url = tmpUrl()
        let stats1 = ComparisonStats(url: url)
        await stats1.record(chosen: .parakeetTDTv3, language: Locale(identifier: "pl-PL"))

        let stats2 = ComparisonStats(url: url)
        let entries = await stats2.allEntries()
        XCTAssertEqual(entries.count, 1)
        XCTAssertEqual(entries.first?.chosen, .parakeetTDTv3)
    }
}
