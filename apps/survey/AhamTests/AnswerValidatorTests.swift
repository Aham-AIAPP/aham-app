import XCTest
@testable import Aham_Survey

final class AnswerValidatorTests: XCTestCase {
    func testSingleChoiceRejectsTextWithoutSelection() {
        let question = makeQuestion(type: .singleChoice, options: ["A", "B"])
        let answer = Answer(projectId: UUID(), departmentId: "procurement", questionId: question.id)
        answer.textValue = "A"

        let result = AnswerValidator.evaluate(answer, for: question)

        XCTAssertFalse(result.isValid)
        XCTAssertEqual(result.code, "ANSWER_SINGLE_CHOICE_REQUIRED")
    }

    func testSingleChoiceAcceptsOnlyCatalogOption() {
        let question = makeQuestion(type: .singleChoice, options: ["A", "B"])
        let answer = Answer(projectId: UUID(), departmentId: "procurement", questionId: question.id)
        answer.selectedOptions = ["A"]

        XCTAssertTrue(AnswerValidator.evaluate(answer, for: question).isValid)

        answer.selectedOptions = ["C"]
        XCTAssertEqual(AnswerValidator.evaluate(answer, for: question).code, "ANSWER_OPTION_INVALID")
    }

    func testOtherChoiceRequiresExplanation() {
        let question = makeQuestion(type: .multiChoice, options: ["A", "B"])
        let answer = Answer(projectId: UUID(), departmentId: "procurement", questionId: question.id)
        answer.selectedOptions = ["__other__"]

        XCTAssertEqual(AnswerValidator.evaluate(answer, for: question).code, "ANSWER_OTHER_TEXT_REQUIRED")

        answer.otherText = "现场自定义流程"
        XCTAssertTrue(AnswerValidator.evaluate(answer, for: question).isValid)
    }

    func testNumberRequiresNumericValue() {
        let question = makeQuestion(type: .number)
        let answer = Answer(projectId: UUID(), departmentId: "procurement", questionId: question.id)
        answer.textValue = "一百"
        XCTAssertEqual(AnswerValidator.evaluate(answer, for: question).code, "ANSWER_NUMBER_INVALID")

        answer.textValue = "1,024.5"
        XCTAssertTrue(AnswerValidator.evaluate(answer, for: question).isValid)
    }

    func testIgnoredAnswerNeverCountsAsValid() {
        let question = makeQuestion(type: .text)
        let answer = Answer(projectId: UUID(), departmentId: "procurement", questionId: question.id)
        answer.textValue = "已有回答"
        answer.status = .ignored

        XCTAssertEqual(AnswerValidator.evaluate(answer, for: question).code, "ANSWER_NOT_ACTIVE")
    }

    private func makeQuestion(type: QuestionType, options: [String]? = nil) -> QuestionTemplate {
        QuestionTemplate(
            id: "TEST_001",
            section: .opening,
            topic: "测试",
            question: "测试题目",
            type: type,
            options: options,
            required: true,
            hints: nil,
            triggers: nil,
            meceGroup: nil,
            knowledgeRef: nil,
            industrySpecific: false,
            order: 1
        )
    }
}
