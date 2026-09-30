import Foundation
import ObjectiveC

/// A request as the SDK sent it.
struct GleapRecordedRequest {
    let method: String
    let url: URL
    let headers: [String: String]
    let body: Data

    var path: String { url.path }

    func header(_ name: String) -> String? {
        headers.first { $0.key.caseInsensitiveCompare(name) == .orderedSame }?.value
    }

    var json: [String: Any]? {
        (try? JSONSerialization.jsonObject(with: body)) as? [String: Any]
    }

    var bodyString: String { String(decoding: body, as: UTF8.self) }
}

/// A canned reply for a stubbed route.
struct GleapStubReply {
    var status = 200
    var headers = ["Content-Type": "application/json"]
    var body = Data("{}".utf8)
    var error: URLError?

    static func json(_ object: Any, status: Int = 200, headers: [String: String] = [:]) -> GleapStubReply {
        var reply = GleapStubReply()
        reply.status = status
        reply.headers.merge(headers) { _, new in new }
        reply.body = (try? JSONSerialization.data(withJSONObject: object)) ?? Data()
        return reply
    }

    static func text(_ text: String, status: Int) -> GleapStubReply {
        GleapStubReply(status: status, headers: ["Content-Type": "text/plain"], body: Data(text.utf8))
    }

    static func failure(_ code: URLError.Code = .notConnectedToInternet) -> GleapStubReply {
        GleapStubReply(error: URLError(code))
    }
}

/// Answers every HTTP(S) request of the test process from canned routes and records it, so no
/// test ever reaches the network. The SDK builds its sessions from `defaultSessionConfiguration`,
/// which `URLProtocol.registerClass` does not reach; `GleapStubInstaller` therefore also puts this
/// class into every default configuration (test-only, the SDK has no seam for it).
final class GleapStubURLProtocol: URLProtocol {
    private typealias Route = (method: String?, path: String, reply: (GleapRecordedRequest) -> GleapStubReply)

    private static let lock = NSLock()
    private static var recorded: [GleapRecordedRequest] = []
    private static var routes: [Route] = []

    /// Forgets all routes and recorded requests.
    static func reset() {
        lock.lock()
        recorded = []
        routes = []
        lock.unlock()
    }

    /// Answers requests to `path` (and `method`, when given). The route added last wins.
    static func stub(_ method: String? = nil, _ path: String, reply: @escaping (GleapRecordedRequest) -> GleapStubReply) {
        lock.lock()
        routes.append((method, path, reply))
        lock.unlock()
    }

    static func stub(_ method: String? = nil, _ path: String, _ reply: GleapStubReply) {
        stub(method, path) { _ in reply }
    }

    static var requests: [GleapRecordedRequest] {
        lock.lock()
        defer { lock.unlock() }
        return recorded
    }

    static func requests(path: String) -> [GleapRecordedRequest] {
        requests.filter { $0.path == path }
    }

    private static func handle(_ request: GleapRecordedRequest) -> GleapStubReply {
        lock.lock()
        recorded.append(request)
        let route = routes.last { route in
            route.path == request.path && (route.method == nil || route.method == request.method)
        }
        lock.unlock()
        return route?.reply(request) ?? GleapStubReply()
    }

    private static func body(of request: URLRequest) -> Data {
        if let body = request.httpBody {
            return body
        }
        guard let stream = request.httpBodyStream else {
            return Data()
        }
        // Session tasks hand the body over as a stream.
        var data = Data()
        var buffer = [UInt8](repeating: 0, count: 16384)
        stream.open()
        while stream.hasBytesAvailable {
            let count = stream.read(&buffer, maxLength: buffer.count)
            if count <= 0 {
                break
            }
            data.append(buffer, count: count)
        }
        stream.close()
        return data
    }

    override class func canInit(with request: URLRequest) -> Bool {
        guard let scheme = request.url?.scheme?.lowercased() else {
            return false
        }
        return scheme == "http" || scheme == "https"
    }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest {
        request
    }

    override func startLoading() {
        guard let url = request.url else {
            client?.urlProtocol(self, didFailWithError: URLError(.badURL))
            return
        }
        let recordedRequest = GleapRecordedRequest(
            method: request.httpMethod ?? "GET",
            url: url,
            headers: request.allHTTPHeaderFields ?? [:],
            body: Self.body(of: request)
        )
        let reply = Self.handle(recordedRequest)
        if let error = reply.error {
            client?.urlProtocol(self, didFailWithError: error)
            return
        }
        let response = HTTPURLResponse(url: url, statusCode: reply.status, httpVersion: "HTTP/1.1", headerFields: reply.headers)!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: reply.body)
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}

enum GleapStubInstaller {
    /// Registers the stub for `URLSession.shared` and for every session created from
    /// `URLSessionConfiguration.default`. Runs once per test process.
    static let install: Void = {
        URLProtocol.registerClass(GleapStubURLProtocol.self)
        let original = class_getClassMethod(URLSessionConfiguration.self, NSSelectorFromString("defaultSessionConfiguration"))
        let replacement = class_getClassMethod(URLSessionConfiguration.self, #selector(URLSessionConfiguration.gleapTests_defaultSessionConfiguration))
        if let original = original, let replacement = replacement {
            method_exchangeImplementations(original, replacement)
        }
    }()
}

extension URLSessionConfiguration {
    @objc dynamic class func gleapTests_defaultSessionConfiguration() -> URLSessionConfiguration {
        // After the exchange this calls the original implementation.
        let configuration = gleapTests_defaultSessionConfiguration()
        configuration.protocolClasses = [GleapStubURLProtocol.self] + (configuration.protocolClasses ?? [])
        return configuration
    }
}
