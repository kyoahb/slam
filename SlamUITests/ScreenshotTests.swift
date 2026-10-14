import XCTest

/// Opens each screen with demo data and keeps a screenshot of it.
final class ScreenshotTests: XCTestCase {
    static let screens = ["routines", "workout", "weight", "reps", "rest", "save", "picker", "routine",
                          "history", "detail", "profile", "stats", "exercises", "exercise", "calendar", "photos", "settings"]

    override func setUp() {
        continueAfterFailure = true
    }

    @MainActor
    func testScreens() {
        let device = ProcessInfo.processInfo.environment["SIMULATOR_DEVICE_NAME"] ?? "device"
        for screen in Self.screens {
            let app = XCUIApplication()
            app.launchArguments = ["-demo", "-screen", screen]
            app.launch()
            _ = app.wait(for: .runningForeground, timeout: 10)
            Thread.sleep(forTimeInterval: 2.5)
            let shot = XCTAttachment(screenshot: app.screenshot())
            shot.name = "\(device) \(screen)"
            shot.lifetime = .keepAlways
            add(shot)
            app.terminate()
        }
    }
}
