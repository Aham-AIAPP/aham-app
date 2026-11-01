import XCTest
@testable import Aham_Survey

final class HTTPRequestParserTests: XCTestCase {
    func testParsesRequestAcrossTCPChunks() throws {
        let body = Data(#"{"tool":"get_capabilities","args":{}}"#.utf8)
        let request = makeRequest(body: body)
        let split = request.count - 7

        guard case .incomplete = HTTPRequestParser.parse(request.prefix(split)) else {
            return XCTFail("不完整 TCP 数据应等待下一段")
        }

        guard case .complete(let parsed) = HTTPRequestParser.parse(request) else {
            return XCTFail("完整请求应解析成功")
        }
        XCTAssertEqual(parsed.method, "POST")
        XCTAssertEqual(parsed.path, "/rpc")
        XCTAssertEqual(parsed.body, body)
        XCTAssertEqual(parsed.headers["authorization"], "Bearer test")
    }

    func testRejectsMissingContentLength() {
        let request = Data("POST /rpc HTTP/1.1\r\nHost: 127.0.0.1\r\n\r\n{}".utf8)
        guard case .failure(let failure) = HTTPRequestParser.parse(request) else {
            return XCTFail("缺少 Content-Length 应失败")
        }
        XCTAssertEqual(failure.code, "HTTP_CONTENT_LENGTH_REQUIRED")
    }

    func testRejectsDeclaredOversizedBodyBeforeReceivingIt() {
        let request = Data("POST /rpc HTTP/1.1\r\nHost: 127.0.0.1\r\nContent-Length: 9999999\r\n\r\n".utf8)
        guard case .failure(let failure) = HTTPRequestParser.parse(request) else {
            return XCTFail("超大正文应失败")
        }
        XCTAssertEqual(failure.code, "HTTP_BODY_TOO_LARGE")
    }

    func testRejectsTrailingBytes() {
        var request = makeRequest(body: Data("{}".utf8))
        request.append(Data("extra".utf8))
        guard case .failure(let failure) = HTTPRequestParser.parse(request) else {
            return XCTFail("Content-Length 之后的多余数据应失败")
        }
        XCTAssertEqual(failure.code, "HTTP_TRAILING_DATA")
    }

    private func makeRequest(body: Data) -> Data {
        var request = Data(
            "POST /rpc HTTP/1.1\r\nHost: 127.0.0.1:51823\r\nContent-Type: application/json\r\nAuthorization: Bearer test\r\nContent-Length: \(body.count)\r\n\r\n".utf8
        )
        request.append(body)
        return request
    }
}
