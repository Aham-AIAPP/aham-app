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
                    XCTAssertGreaterThanOrEqual(contrast(.ahOnAction, background), 4.5)
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

    func testCardGroupsSiblingViewsWithOnePaddingAndStableWidth() {
        let card = AHCard {
            Color.clear.frame(height: 20)
            Color.clear.frame(height: 40)
        }.frame(width: 400)
        let host = NSHostingView(rootView: card)
        XCTAssertEqual(host.fittingSize.width, 400, accuracy: 1)
        XCTAssertEqual(host.fittingSize.height, 20 + 40 + AHSpacing.m + 2 * AHSpacing.l, accuracy: 1)
    }

    func testSelectingSameRadioDoesNotChangeRevision() throws {
        let f = try WriteIntegrityTests.Fixture()
        _ = try f.commit(f.rows())
        let answer = try f.answer(), store = AppStore(), revision = answer.revision
        XCTAssertFalse(store.selectAnswerOption("__other__", multiple: false, answer: answer, project: f.project, service: f.survey))
        XCTAssertEqual(answer.revision, revision)
        XCTAssertEqual(answer.otherText, "供应商约 60 家")
    }

    func testOtherInputSurvivesToggleButIsNotReportedWhenUnselected() throws {
        let f = try WriteIntegrityTests.Fixture()
        _ = try f.commit(f.rows())
        let answer = try f.answer(), store = AppStore()
        XCTAssertTrue(store.selectAnswerOption("50-200家，活跃率60%-80%", multiple: false, answer: answer, project: f.project, service: f.survey))
        XCTAssertTrue(answer.otherText.isEmpty)
        XCTAssertEqual(answer.textValue, "50-200家，活跃率60%-80%")
        XCTAssertTrue(store.selectAnswerOption("__other__", multiple: false, answer: answer, project: f.project, service: f.survey))
        XCTAssertEqual(answer.otherText, "供应商约 60 家")
        XCTAssertEqual(answer.textValue, "供应商约 60 家")
    }

    func testOtherInputSynchronizesTextAndRejectsStaleDraft() throws {
        let f = try WriteIntegrityTests.Fixture()
        _ = try f.commit(f.rows())
        let answer = try f.answer(), store = AppStore()
        XCTAssertTrue(store.saveAnswerText("供应商约 80 家", at: \Answer.otherText,
                                          answer: answer, project: f.project, service: f.survey))
        XCTAssertEqual(answer.textValue, "供应商约 80 家")
        store.answerTextDrafts[answer.id] = .init(revision: answer.revision, fields: [\Answer.otherText: "本地待重试"])
        _ = try f.commit(f.rows().map { row in var row = row; row["otherText"] = "外部新记录"; return row })
        XCTAssertFalse(store.retryAnswerText(answer: answer, project: f.project, service: f.survey))
        XCTAssertEqual(answer.otherText, "外部新记录")
        XCTAssertEqual(store.answerTextDrafts[answer.id]?.fields[\Answer.otherText], "本地待重试")
        let revision = answer.revision
        XCTAssertFalse(store.selectAnswerOption("__other__", multiple: true, answer: answer, project: f.project, service: f.survey))
        XCTAssertEqual(answer.revision, revision)
    }

    func testFailedInputCanBeRetriedWithoutLosingText() throws {
        let f = try WriteIntegrityTests.Fixture()
        _ = try f.commit(f.rows())
        let answer = try f.answer(), store = AppStore()
        try f.projects.update(f.project, fields: ["status": "archived"])
        XCTAssertFalse(store.saveAnswerText("待保存笔记", at: \Answer.noteText,
                                           answer: answer, project: f.project, service: f.survey))
        XCTAssertEqual(store.answerTextDrafts[answer.id]?.fields[\Answer.noteText], "待保存笔记")
        XCTAssertNotEqual(answer.noteText, "待保存笔记")
        try f.projects.update(f.project, fields: ["status": "inProgress"])
        XCTAssertTrue(store.retryAnswerText(answer: answer, project: f.project, service: f.survey))
        XCTAssertEqual(answer.noteText, "待保存笔记")
        XCTAssertNil(store.answerTextDrafts[answer.id])
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
