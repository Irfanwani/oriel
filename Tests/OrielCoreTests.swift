import CoreGraphics
import XCTest
@testable import OrielCore

final class LayoutEngineTests: XCTestCase {
    private let bounds = CGRect(x: 0, y: 0, width: 1440, height: 900)

    private func input(count: Int, ratio: CGFloat = 0.5, gap: CGFloat = 8,
                       isUltrawide: Bool = false, isVertical: Bool = false) -> LayoutEngine.Input {
        LayoutEngine.Input(bounds: bounds, count: count, ratio: ratio, gap: gap,
                           isUltrawide: isUltrawide, isVertical: isVertical)
    }

    func testEveryLayoutProducesRequestedFrameCount() {
        for layout in LayoutKind.allCases {
            let maximum = (layout == .grid || layout == .bento) ? 4 : 5
            for count in 1...maximum {
                let frames = LayoutEngine.frames(for: layout, input: input(
                    count: count,
                    isUltrawide: layout == .side
                ))
                XCTAssertEqual(frames.count, count, "\(layout) with \(count) windows")
            }
        }
    }

    func testFramesStayInsideBoundsAndDoNotOverlap() {
        for layout in LayoutKind.allCases {
            let maximum = (layout == .grid || layout == .bento) ? 4 : 5
            for count in 1...maximum {
                let frames = LayoutEngine.frames(for: layout, input: input(
                    count: count,
                    gap: 8,
                    isUltrawide: layout == .side
                ))
                for frame in frames {
                    XCTAssertGreaterThanOrEqual(frame.minX, bounds.minX + 8 - 0.01, "\(layout) \(count)")
                    XCTAssertGreaterThanOrEqual(frame.minY, bounds.minY + 8 - 0.01, "\(layout) \(count)")
                    XCTAssertLessThanOrEqual(frame.maxX, bounds.maxX - 8 + 0.01, "\(layout) \(count)")
                    XCTAssertLessThanOrEqual(frame.maxY, bounds.maxY - 8 + 0.01, "\(layout) \(count)")
                    XCTAssertGreaterThan(frame.width, 0)
                    XCTAssertGreaterThan(frame.height, 0)
                }
                for first in frames.indices {
                    for second in frames.indices where first < second {
                        let overlap = frames[first].intersection(frames[second])
                        XCTAssertTrue(overlap.isNull || overlap.width < 0.01 || overlap.height < 0.01,
                                      "\(layout) frames \(first) and \(second) overlap")
                    }
                }
            }
        }
    }

    func testGridTwoEqualWindowsAtHalfRatio() {
        let frames = LayoutEngine.frames(for: .grid, input: input(count: 2, ratio: 0.5, gap: 8))
        XCTAssertEqual(frames.count, 2)
        XCTAssertEqual(frames[0].minY, frames[1].minY)
        XCTAssertEqual(frames[0].width, frames[1].width, accuracy: 0.01)
        XCTAssertEqual(frames[0].height, bounds.height - 16, accuracy: 0.01)
        XCTAssertEqual(frames[1].maxX, bounds.maxX - 8, accuracy: 0.01)
    }

    func testColumnsGivesMainWindowMoreSpace() {
        let frames = LayoutEngine.frames(for: .columns, input: input(count: 3, ratio: 0.5, gap: 8))
        XCTAssertEqual(frames.count, 3)
        XCTAssertGreaterThan(frames[0].width, frames[1].width)
        XCTAssertEqual(frames[1].width, frames[2].width, accuracy: 0.01)
        XCTAssertEqual(frames[0].height, frames[1].height, accuracy: 0.01)
    }

    func testRowsStackVertically() {
        let frames = LayoutEngine.frames(for: .rows, input: input(count: 3, ratio: 0.5, gap: 8))
        XCTAssertEqual(frames[0].minX, frames[1].minX)
        XCTAssertEqual(frames[1].minY, frames[2].minY - frames[2].height - 8, accuracy: 0.01)
        XCTAssertGreaterThan(frames[0].height, frames[1].height)
    }

    func testSideCreatesARailOnTheRight() {
        let frames = LayoutEngine.frames(for: .side, input: input(count: 4, ratio: 0.6, gap: 8))
        XCTAssertEqual(frames.count, 4)
        XCTAssertGreaterThan(frames[0].width, frames[1].width)
        XCTAssertEqual(frames[1].minX, frames[2].minX, accuracy: 0.01)
        XCTAssertEqual(frames[2].minX, frames[3].minX, accuracy: 0.01)
    }

    func testUltrawideSideUsesTwoHeroWindows() {
        let frames = LayoutEngine.frames(for: .side, input: input(count: 5, ratio: 0.5, gap: 8, isUltrawide: true))
        XCTAssertEqual(frames.count, 5)
        XCTAssertEqual(frames[0].height, frames[1].height, accuracy: 0.01)
        XCTAssertGreaterThan(frames[0].height, frames[2].height)
    }

    func testBentoIsAsymmetric() {
        let frames = LayoutEngine.frames(for: .bento, input: input(count: 4, gap: 8))
        XCTAssertEqual(frames.count, 4)
        XCTAssertGreaterThan(frames[0].width, frames[1].width)
        XCTAssertGreaterThan(frames[3].width, frames[2].width)
    }

    func testRatioAndGapAreClamped() {
        let wide = LayoutEngine.frames(for: .grid, input: input(count: 2, ratio: 5, gap: 500))
        XCTAssertEqual(wide[0].width / (wide[0].width + wide[1].width), 0.75, accuracy: 0.02)
        XCTAssertEqual(wide[0].minX, bounds.minX + 32, accuracy: 0.01)

        let narrow = LayoutEngine.frames(for: .grid, input: input(count: 2, ratio: 0.01, gap: 0))
        XCTAssertEqual(narrow[0].width / (narrow[0].width + narrow[1].width), 0.34, accuracy: 0.02)
    }

    func testTinyBoundsFallBackSafely() {
        let tiny = CGRect(x: 10, y: 10, width: 20, height: 20)
        let frames = LayoutEngine.frames(for: .grid, input: LayoutEngine.Input(
            bounds: tiny, count: 3, ratio: 0.5, gap: 8, isUltrawide: false, isVertical: false
        ))
        XCTAssertEqual(frames.count, 3)
        XCTAssertTrue(frames.allSatisfy { $0 == tiny })
    }

    func testVerticalDisplayGridUsesTopHeavySplit() {
        let frames = LayoutEngine.frames(for: .grid, input: input(count: 3, ratio: 0.6, gap: 8, isVertical: true))
        XCTAssertEqual(frames.count, 3)
        XCTAssertGreaterThan(frames[0].height, frames[1].height)
        XCTAssertEqual(frames[1].minY, frames[2].minY, accuracy: 0.01)
    }
}

final class SettingsTests: XCTestCase {
    func testPartialSettingsUseDefaults() throws {
        let json = """
        {"layout":"bento","capacity":4,"gap":14,"noPeekBlur":true,"futureKey":42}
        """.data(using: .utf8)!
        let settings = try JSONDecoder().decode(AppSettings.self, from: json)
        XCTAssertEqual(settings.layout, .bento)
        XCTAssertEqual(settings.capacity, 4)
        XCTAssertEqual(settings.gap, 14)
        XCTAssertTrue(settings.isEnabled)
        XCTAssertEqual(settings.ratio, 0.5)
        XCTAssertTrue(settings.shortcutsEnabled)
    }

    func testSceneRoundTripsFloatingFrame() throws {
        let scene = SavedScene(
            name: "Deep work",
            windows: [
                SceneWindow(bundleID: "com.apple.Safari", appName: "Safari",
                            displayUUID: "display", order: 0, floating: true,
                            frame: CGRect(x: 100, y: 120, width: 800, height: 600))
            ],
            screenOverrides: ["display": ScreenSetting(layout: .bento, capacity: 4, ratio: 0.6)]
        )
        let data = try JSONEncoder().encode(scene)
        let decoded = try JSONDecoder().decode(SavedScene.self, from: data)
        XCTAssertEqual(decoded, scene)
        XCTAssertEqual(decoded.windows.first?.frame?.width, 800)
    }

    func testEffectiveScreenUsesOverrideOnlyWhenPresent() {
        var settings = AppSettings()
        settings.layout = .columns
        settings.capacity = 2
        let fallback = settings.effectiveScreen(for: "unknown")
        XCTAssertEqual(fallback.layout, .columns)
        XCTAssertFalse(settings.hasOverride(for: "unknown"))

        settings.screenOverrides["external"] = ScreenSetting(layout: .bento, capacity: 4, ratio: 0.66)
        let override = settings.effectiveScreen(for: "external")
        XCTAssertEqual(override.layout, .bento)
        XCTAssertEqual(override.capacity, 4)
        XCTAssertTrue(settings.hasOverride(for: "external"))
    }
}
