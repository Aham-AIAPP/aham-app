import XCTest
import SwiftUI
import AppKit
@testable import Aham_Survey

@MainActor
final class UIRegressionTests: XCTestCase {
    func testDisabledControlsIgnorePointerState() {
        for pressed in [false, true] {
            for hovered in [false, true] {
                XCTAssertEqual(AHControlState.resolve(enabled: false, pressed: pressed, hovered: hovered), .disabled)
            }
        }
        XCTAssertEqual(AHControlState.resolve(enabled: true, pressed: true, hovered: true), .pressed)
        XCTAssertEqual(AHControlState.resolve(enabled: true, pressed: false, hovered: true), .hover)
    }

    func testPrimaryPairsRemainReadableInBothAppearances() throws {
        for appearance in [NSAppearance.Name.aqua, .darkAqua] {
            let mode = try XCTUnwrap(NSAppearance(named: appearance))
            mode.performAsCurrentDrawingAppearance {
                for background in [Color.ahAction, .ahActionHover, .ahActionPress] {
                    XCTAssertGreaterThanOrEqual(contrast(.ahOnAccent, background), 4.5)
                }
                XCTAssertGreaterThanOrEqual(contrast(.ahInk, .ahPaper), 4.5)
                XCTAssertGreaterThanOrEqual(contrast(.ahInk60, .ahButton), 4.5)
                XCTAssertGreaterThanOrEqual(contrast(.ahInputBorder, .ahPaper), 3.0)
            }
        }
    }

    func testButtonSizeDoesNotChangeWhenDisabled() {
        for scheme in [ColorScheme.light, .dark] {
            let enabled = NSHostingView(rootView: Button("保存更改") {}.buttonStyle(.ahPrimary).environment(\.colorScheme, scheme))
            let disabled = NSHostingView(rootView: Button("保存更改") {}.buttonStyle(.ahPrimary).disabled(true).environment(\.colorScheme, scheme))
            XCTAssertEqual(enabled.fittingSize, disabled.fittingSize)
            XCTAssertGreaterThanOrEqual(enabled.fittingSize.height, AHLayout.control)
        }
    }

    func testTestingSettingsDoNotLoadProductionCredentials() {
        XCTAssertEqual(ProcessInfo.processInfo.environment["AHAM_TEST_IN_MEMORY"], "1")
        let settings = SettingsManager()
        XCTAssertEqual(settings.llmConfig, .default)
        XCTAssertFalse(settings.isLLMConfigured)
    }

    private func contrast(_ foreground: Color, _ background: Color) -> Double {
        func luminance(_ color: Color) -> Double {
            let c = NSColor(color).usingColorSpace(.sRGB)!
            func linear(_ value: CGFloat) -> Double {
                let v = Double(value)
                return v <= 0.04045 ? v / 12.92 : pow((v + 0.055) / 1.055, 2.4)
            }
            return 0.2126 * linear(c.redComponent) + 0.7152 * linear(c.greenComponent) + 0.0722 * linear(c.blueComponent)
        }
        let f = luminance(foreground), b = luminance(background)
        return (max(f, b) + 0.05) / (min(f, b) + 0.05)
    }
}
