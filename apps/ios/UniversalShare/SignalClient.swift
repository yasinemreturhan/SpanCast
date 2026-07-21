import Foundation

// WebSocket mesaj yapısı — Go signal.Message ile uyumlu.
struct SignalMessage: Codable {
    var type: String
    var from: String?
    var to: String?
    var name: String?
    var pin: String?
    var reason: String?
    var payload: AnyCodable?
}

// JSON'da arbitrary value taşır (offer/answer/ICE candidate için).
struct AnyCodable: Codable {
    let value: Any

    init(_ value: Any) { self.value = value }

    init(from decoder: Decoder) throws {
        let c = try decoder.singleValueContainer()
        if let v = try? c.decode(Bool.self)   { value = v; return }
        if let v = try? c.decode(Int.self)    { value = v; return }
        if let v = try? c.decode(Double.self) { value = v; return }
        if let v = try? c.decode(String.self) { value = v; return }
        if let v = try? c.decode([String: AnyCodable].self) { value = v.mapValues { $0.value }; return }
        if let v = try? c.decode([AnyCodable].self) { value = v.map { $0.value }; return }
        value = NSNull()
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.singleValueContainer()
        switch value {
        case let v as Bool:               try c.encode(v)
        case let v as Int:                try c.encode(v)
        case let v as Double:             try c.encode(v)
        case let v as String:             try c.encode(v)
        case let v as [String: Any]:
            try c.encode(v.mapValues { AnyCodable($0) })
        case let v as [Any]:
            try c.encode(v.map { AnyCodable($0) })
        default: try c.encodeNil()
        }
    }
}

@MainActor
class SignalClient: NSObject, URLSessionWebSocketDelegate {
    private let url: URL
    private var ws: URLSessionWebSocketTask?
    private var session: URLSession?
    private var closed = false
    private var attempt = 0
    var onMessage: ((SignalMessage) -> Void)?
    var onClose: (() -> Void)?

    init(url: URL) {
        self.url = url
        super.init()
    }

    func connect() {
        guard !closed else { return }
        let cfg = URLSessionConfiguration.default
        // Self-signed sertifika: URLSession delegate ile onaylama yapılır.
        session = URLSession(configuration: cfg, delegate: self, delegateQueue: .main)
        ws = session!.webSocketTask(with: url)
        ws!.resume()
        listen()
    }

    func send(_ msg: SignalMessage) {
        guard let ws, !closed else { return }
        guard let data = try? JSONEncoder().encode(msg),
              let str = String(data: data, encoding: .utf8) else { return }
        ws.send(.string(str)) { _ in }
    }

    func close() {
        closed = true
        ws?.cancel(with: .goingAway, reason: nil)
    }

    private func listen() {
        ws?.receive { [weak self] result in
            guard let self else { return }
            switch result {
            case .success(let m):
                if case .string(let s) = m,
                   let data = s.data(using: .utf8),
                   let msg = try? JSONDecoder().decode(SignalMessage.self, from: data) {
                    DispatchQueue.main.async { self.onMessage?(msg) }
                }
                self.listen()
            case .failure:
                if !self.closed {
                    DispatchQueue.main.async { self.onClose?() }
                    let delay = min(0.5 * pow(2.0, Double(self.attempt)), 8.0)
                    self.attempt += 1
                    DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
                        self.connect()
                    }
                }
            }
        }
    }

    // Self-signed sertifika kabul et — parmak izi kontrolü üst katmanda yapılır.
    nonisolated func urlSession(
        _ session: URLSession,
        didReceive challenge: URLAuthenticationChallenge,
        completionHandler: @escaping (URLSession.AuthChallengeDisposition, URLCredential?) -> Void
    ) {
        if challenge.protectionSpace.authenticationMethod == NSURLAuthenticationMethodServerTrust,
           let trust = challenge.protectionSpace.serverTrust {
            completionHandler(.useCredential, URLCredential(trust: trust))
        } else {
            completionHandler(.performDefaultHandling, nil)
        }
    }
}
