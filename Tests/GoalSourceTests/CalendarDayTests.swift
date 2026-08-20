import XCTest
@testable import GoalSource

final class CalendarDayTests: XCTestCase {
    func testDayIntervalFollowsTheCalendarTimeZone() {
        let saoPaulo = Fixture.calendar(timeZone: "America/Sao_Paulo")
        let kiritimati = Fixture.calendar(timeZone: "Pacific/Kiritimati")

        XCTAssertEqual(saoPaulo.goalDayKey(for: Fixture.noon), "2026-08-20")
        XCTAssertEqual(kiritimati.goalDayKey(for: Fixture.noon), "2026-08-21")
    }

    func testDayIntervalIsHalfOpenAndTwentyFourHoursLong() {
        let calendar = Fixture.calendar(timeZone: "America/Sao_Paulo")
        let interval = calendar.goalDayInterval(containing: Fixture.noon)

        XCTAssertEqual(calendar.goalDayKey(for: interval.start), "2026-08-20")
        XCTAssertEqual(interval.duration, 24 * 60 * 60)
        XCTAssertEqual(calendar.component(.hour, from: interval.start), 0)
        XCTAssertEqual(calendar.goalDayKey(for: interval.end), "2026-08-21", "The end belongs to the next day.")
    }

    func testDayIntervalHandlesADaylightSavingShortDay() {
        let santiago = Fixture.calendar(timeZone: "America/Santiago")
        var components = DateComponents()
        components.year = 2026
        components.month = 9
        components.day = 6
        components.hour = 12
        let date = santiago.date(from: components)!

        let interval = santiago.goalDayInterval(containing: date)
        XCTAssertEqual(santiago.goalDayKey(for: interval.start), "2026-09-06")
        XCTAssertEqual(santiago.goalDayKey(for: interval.end.addingTimeInterval(-1)), "2026-09-06")
        XCTAssertLessThanOrEqual(interval.duration, 24 * 60 * 60)
    }

    func testDayKeySortsChronologicallyAsAString() {
        let calendar = Fixture.calendar(timeZone: "UTC")
        let earlier = calendar.goalDayKey(for: Fixture.noon.addingTimeInterval(-40 * 24 * 3600))
        let later = calendar.goalDayKey(for: Fixture.noon)
        XCTAssertLessThan(earlier, later, "Pruning relies on lexicographic order matching real order.")
    }
}
