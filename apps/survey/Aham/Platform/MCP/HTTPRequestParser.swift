import Foundation

struct HTTPRPCRequest {
    let method: String
    let path: String
    let version: String
    let headers: [String: String]
    let body: Data
}

struct HTTPRPCParseFailure: Error, Equatable {
    let status: String
    let code: String
    let message: String
}

enum HTTPRPCParseResult {
    case incomplete
    case complete(HTTPRPCRequest)
    case failure(HTTPRPCParseFailure)
}

/// 对单个 Connection: close 请求做增量解析，避免假设一次 TCP receive 就能拿到完整 HTTP body。
enum HTTPRequestParser {
    static let maxHeaderBytes = 64 * 1024
    static let maxBodyBytes = 2 * 1024 * 1024

    private static let headerDelimiter = Data("\r\n\r\n".utf8)

    static func parse(_ buffer: Data) -> HTTPRPCParseResult {
        guard let delimiterRange = buffer.range(of: headerDelimiter) else {
            if buffer.count > maxHeaderBytes {
                return .failure(.init(
                    status: "431 Request Header Fields Too Large",
                    code: "HTTP_HEADERS_TOO_LARGE",
                    message: "请求头超过允许大小"
                ))
            }
            return .incomplete
        }

        guard delimiterRange.lowerBound <= maxHeaderBytes else {
            return .failure(.init(
                status: "431 Request Header Fields Too Large",
                code: "HTTP_HEADERS_TOO_LARGE",
                message: "请求头超过允许大小"
            ))
        }

        let headData = buffer[..<delimiterRange.lowerBound]
        guard let head = String(data: headData, encoding: .utf8) else {
            return .failure(.init(
                status: "400 Bad Request",
                code: "HTTP_HEADER_ENCODING_INVALID",
                message: "请求头不是有效 UTF-8"
            ))
        }

        let lines = head.components(separatedBy: "\r\n")
        let requestParts = (lines.first ?? "").split(separator: " ", omittingEmptySubsequences: true)
        guard requestParts.count == 3 else {
            return .failure(.init(
                status: "400 Bad Request",
                code: "HTTP_REQUEST_LINE_INVALID",
                message: "HTTP 请求行格式错误"
            ))
        }

        var headers: [String: String] = [:]
        for line in lines.dropFirst() {
            guard let separator = line.firstIndex(of: ":") else {
                return .failure(.init(
                    status: "400 Bad Request",
                    code: "HTTP_HEADER_INVALID",
                    message: "HTTP 请求头格式错误"
                ))
            }
            let key = line[..<separator].trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            let value = line[line.index(after: separator)...].trimmingCharacters(in: .whitespacesAndNewlines)
            guard !key.isEmpty else {
                return .failure(.init(
                    status: "400 Bad Request",
                    code: "HTTP_HEADER_INVALID",
                    message: "HTTP 请求头名称为空"
                ))
            }
            headers[key] = value
        }

        guard let rawLength = headers["content-length"], let contentLength = Int(rawLength), contentLength >= 0 else {
            return .failure(.init(
                status: "411 Length Required",
                code: "HTTP_CONTENT_LENGTH_REQUIRED",
                message: "请求必须包含合法的 Content-Length"
            ))
        }
        guard contentLength <= maxBodyBytes else {
            return .failure(.init(
                status: "413 Payload Too Large",
                code: "HTTP_BODY_TOO_LARGE",
                message: "请求正文超过允许大小"
            ))
        }

        let bodyStart = delimiterRange.upperBound
        let expectedTotal = bodyStart + contentLength
        guard buffer.count >= expectedTotal else { return .incomplete }
        guard buffer.count == expectedTotal else {
            return .failure(.init(
                status: "400 Bad Request",
                code: "HTTP_TRAILING_DATA",
                message: "请求包含 Content-Length 之外的多余数据"
            ))
        }

        return .complete(HTTPRPCRequest(
            method: String(requestParts[0]),
            path: String(requestParts[1]),
            version: String(requestParts[2]),
            headers: headers,
            body: buffer.subdata(in: bodyStart..<expectedTotal)
        ))
    }
}
