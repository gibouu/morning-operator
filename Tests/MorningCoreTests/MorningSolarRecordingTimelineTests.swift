#if DEBUG
import Testing
@testable import MorningCore

@Suite("Filming solar time is bounded and separate from real time")
struct MorningSolarRecordingTimelineTests {
    @Test func recordingRequiresAnExplicitDuration() {
        #expect(MorningSolarRecordingTimeline.from(arguments: []) == nil)
        #expect(MorningSolarRecordingTimeline.from(arguments: ["--theme-recording-start-hour=7"]) == nil)
    }

    @Test func fiveMinuteDayHasExactEndpointsAndDoesNotLoop() throws {
        let timeline = try #require(MorningSolarRecordingTimeline.from(arguments: ["--theme-recording-seconds=300"]))
        #expect(timeline.minute(atElapsed: 0) == 6 * 60)
        #expect(timeline.minute(atElapsed: 150) == 14.5 * 60)
        #expect(timeline.minute(atElapsed: 300) == 23 * 60)
        #expect(timeline.minute(atElapsed: 600) == 23 * 60)
        #expect(timeline.minute(atElapsed: -5) == 6 * 60)
        #expect(timeline.minute(atElapsed: .nan) == 6 * 60)
        #expect(timeline.minute(atElapsed: .infinity) == 23 * 60)
        #expect(timeline.minute(atElapsed: -.infinity) == 6 * 60)
    }

    @Test func customHoursReachTheExistingSunAndMoonScenes() throws {
        let timeline = try #require(MorningSolarRecordingTimeline.from(arguments: [
            "--theme-recording-seconds=170", "--theme-recording-start-hour=9", "--theme-recording-end-hour=23"
        ]))
        let start = timeline.minute(atElapsed: 0)
        let finish = timeline.minute(atElapsed: 170)
        #expect(MorningCelestialClock.scene(atMinute: start).sun.opacity == 1)
        #expect(MorningCelestialClock.scene(atMinute: finish).moon.opacity == 1)
        #expect(MorningDayClock.blend(atMinute: start).dominant == .morning)
        #expect(MorningDayClock.blend(atMinute: finish).dominant == .night)
        #expect(timeline.minute(atElapsed: 0.1) > start)
        #expect(timeline.minute(atElapsed: 0.1) - start < 1)
    }

    @Test func malformedNonFiniteAndOutOfBoundsOptionsDisableTheOverride() {
        for invalid in ["", "0", "9", "1801", "-10", "nan", "inf", "invalid"] {
            #expect(MorningSolarRecordingTimeline.from(arguments: ["--theme-recording-seconds=\(invalid)"]) == nil)
        }
        for option in ["--theme-recording-start-hour=-1", "--theme-recording-start-hour=25",
                       "--theme-recording-start-hour=nan", "--theme-recording-end-hour=25",
                       "--theme-recording-end-hour=6", "--theme-recording-end-hour=invalid"] {
            #expect(MorningSolarRecordingTimeline.from(arguments: ["--theme-recording-seconds=300", option]) == nil)
        }
        #expect(MorningSolarRecordingTimeline.from(arguments: [
            "--theme-recording-seconds=300", "--theme-recording-seconds=300"
        ]) == nil)
        #expect(MorningSolarRecordingTimeline.from(arguments: [
            "--theme-recording-seconds=300", "--theme-recording-start-hour=7", "--theme-recording-start-hour=8"
        ]) == nil)
    }
}
#endif
