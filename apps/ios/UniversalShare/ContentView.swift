import SwiftUI
import ReplayKit

struct ContentView: View {
    @StateObject private var vm = SenderViewModel()

    var body: some View {
        ZStack {
            Color(hex: "#0f1117").ignoresSafeArea()

            switch vm.step {
            case .connect: ConnectView(vm: vm)
            case .pin:     PINView(vm: vm)
            case .sharing: SharingView(vm: vm)
            }
        }
        .preferredColorScheme(.dark)
    }
}

// ─── Connect step ─────────────────────────────────────────────────────────────
struct ConnectView: View {
    @ObservedObject var vm: SenderViewModel

    var body: some View {
        VStack(spacing: 20) {
            Text("🖥 UniversalShare").font(.title2).bold().foregroundColor(Color(hex: "#4f8cff"))
            Text("Sunucu adresini gir").foregroundColor(Color(hex: "#9aa3b2")).font(.subheadline)

            TextField("192.168.1.20:8788", text: $vm.serverAddr)
                .textFieldStyle(.roundedBorder)
                .keyboardType(.URL)
                .autocapitalization(.none)
                .frame(width: 280)

            if let err = vm.connectError {
                Text(err).foregroundColor(.red).font(.caption)
            }

            Button("Bağlan") { Task { await vm.connect() } }
                .buttonStyle(.borderedProminent)
                .disabled(vm.serverAddr.isEmpty || vm.loading)

            if vm.loading { ProgressView() }
        }
        .padding(32)
    }
}

// ─── PIN step ────────────────────────────────────────────────────────────────
struct PINView: View {
    @ObservedObject var vm: SenderViewModel
    @FocusState private var focusedIndex: Int?

    var body: some View {
        VStack(spacing: 20) {
            Text("PIN Gir").font(.title2).bold().foregroundColor(Color(hex: "#4f8cff"))
            Text("Alıcı ekranındaki 6 haneli kodu gir")
                .foregroundColor(Color(hex: "#9aa3b2")).font(.subheadline)

            HStack(spacing: 8) {
                ForEach(0..<6, id: \.self) { i in
                    PINBox(digit: $vm.pinDigits[i])
                        .focused($focusedIndex, equals: i)
                        .onChange(of: vm.pinDigits[i]) { _, new in
                            if !new.isEmpty, i < 5 { focusedIndex = i + 1 }
                        }
                }
            }

            if !vm.fpDisplay.isEmpty {
                Text("Sertifika: \(vm.fpDisplay)")
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundColor(Color(hex: "#4a5568"))
            }

            if let err = vm.pinError {
                Text(err).foregroundColor(.red).font(.caption)
            }

            HStack(spacing: 12) {
                Button("← Geri") { vm.step = .connect }
                    .buttonStyle(.bordered)
                Button("Paylaşımı Başlat") {
                    Task { await vm.startBroadcast() }
                }
                .buttonStyle(.borderedProminent)
                .disabled(vm.pin.count < 6)
            }
        }
        .padding(32)
        .onAppear { focusedIndex = 0 }
    }
}

struct PINBox: View {
    @Binding var digit: String
    var body: some View {
        TextField("", text: $digit)
            .frame(width: 44, height: 56)
            .multilineTextAlignment(.center)
            .font(.system(size: 28, weight: .bold))
            .keyboardType(.numberPad)
            .background(Color(hex: "#1b1f2a"))
            .cornerRadius(10)
            .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color(hex: "#2a3040")))
    }
}

// ─── Sharing step ─────────────────────────────────────────────────────────────
struct SharingView: View {
    @ObservedObject var vm: SenderViewModel

    var body: some View {
        VStack(spacing: 20) {
            Text("🟢 Yayında").font(.title2).bold().foregroundColor(.green)
            Text(vm.statusMsg).foregroundColor(Color(hex: "#9aa3b2")).font(.subheadline)

            Button("Paylaşımı Durdur") { vm.stopBroadcast() }
                .buttonStyle(.borderedProminent)
                .tint(.red)
        }
        .padding(32)
    }
}

// ─── ViewModel ───────────────────────────────────────────────────────────────
enum SenderStep { case connect, pin, sharing }

@MainActor
class SenderViewModel: ObservableObject {
    @Published var step: SenderStep = .connect
    @Published var serverAddr = ""
    @Published var connectError: String?
    @Published var loading = false
    @Published var pinDigits = Array(repeating: "", count: 6)
    @Published var pinError: String?
    @Published var statusMsg = ""
    @Published var fpDisplay = ""

    var pin: String { pinDigits.joined() }
    private var serverBase: URL?
    private var signal: SignalClient?
    private let broadcaster = RPBroadcastActivityViewController.self

    func connect() async {
        loading = true
        connectError = nil
        defer { loading = false }

        var addr = serverAddr.trimmingCharacters(in: .whitespaces)
        if !addr.hasPrefix("http") { addr = "https://\(addr)" }
        guard let base = URL(string: addr) else {
            connectError = "Geçersiz adres"; return
        }

        do {
            let (data, _) = try await insecureSession().data(from: base.appendingPathComponent("healthz"))
            guard String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) == "ok" else {
                connectError = "Sunucu yanıtı beklenmedik"; return
            }
            // Fetch fingerprint for display
            if let infoData = try? await insecureSession().data(from: base.appendingPathComponent("api/info")).0,
               let info = try? JSONDecoder().decode([String: String].self, from: infoData),
               let fp = info["fp"] {
                fpDisplay = String(fp.prefix(32)) + "…"
            }
            serverBase = base
            step = .pin
        } catch {
            connectError = "Bağlanamadı: \(error.localizedDescription)"
        }
    }

    func startBroadcast() async {
        guard let base = serverBase, pin.count == 6 else { return }
        step = .sharing
        statusMsg = "Bağlanılıyor…"
        pinError = nil

        let wsScheme = base.scheme == "https" ? "wss" : "ws"
        guard let host = base.host,
              let wsURL = URL(string: "\(wsScheme)://\(host):\(base.port ?? 8788)/ws?role=sender&name=iPhone")
        else { return }

        signal = SignalClient(url: wsURL)
        let capturedPin = pin

        signal?.onMessage = { [weak self] msg in
            guard let self else { return }
            Task { @MainActor in
                await self.handle(msg: msg, pin: capturedPin, base: base)
            }
        }
        signal?.onClose = { [weak self] in
            self?.statusMsg = "Bağlantı koptu, yeniden deneniyor…"
        }
        signal?.connect()

        // ReplayKit yayınını başlat
        RPBroadcastActivityViewController.load { [weak self] controller, error in
            guard let self, let vc = controller else { return }
            vc.delegate = self as? RPBroadcastActivityViewControllerDelegate
            // Ana ViewController'dan sunum yapılmalı — SwiftUI köprüsü:
            // UIApplication.shared.connectedScenes üzerinden UIWindow alınır.
            if let window = UIApplication.shared.connectedScenes
                .compactMap({ $0 as? UIWindowScene })
                .first?.windows.first,
               let rootVC = window.rootViewController {
                rootVC.present(vc, animated: true)
            }
        }
    }

    private func handle(msg: SignalMessage, pin: String, base: URL) async {
        switch msg.type {
        case "challenge":
            guard let payload = msg.payload?.value as? [String: Any],
                  let salt = payload["salt"] as? String else { return }
            let proof = PairUtil.proof(pin: pin, saltHex: salt)
            signal?.send(SignalMessage(type: "auth", payload: AnyCodable(["proof": proof])))
            statusMsg = "Kimlik doğrulanıyor…"

        case "paired":
            statusMsg = "Eşleşti — ReplayKit yayınını başlatın"

        case "error":
            let errs: [String: String] = [
                "bad-pin": "PIN hatalı.",
                "pin-expired": "PIN süresi dolmuş.",
                "room-full": "Oda dolu.",
                "receiver-gone": "Alıcı kapandı.",
            ]
            pinError = errs[msg.reason ?? ""] ?? (msg.reason ?? "bilinmeyen hata")
            step = .pin

        default: break
        }
    }

    func stopBroadcast() {
        signal?.close()
        signal = nil
        step = .connect
        pinDigits = Array(repeating: "", count: 6)
        statusMsg = ""
    }

    private func insecureSession() -> URLSession {
        // Self-signed sertifika için TLS doğrulamayı atla
        let delegate = InsecureSessionDelegate()
        return URLSession(configuration: .default, delegate: delegate, delegateQueue: nil)
    }
}

// URLSession delegate: self-signed sertifikayı kabul eder.
private class InsecureSessionDelegate: NSObject, URLSessionDelegate {
    func urlSession(
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

// ─── Color helper ─────────────────────────────────────────────────────────────
extension Color {
    init(hex: String) {
        let h = hex.hasPrefix("#") ? String(hex.dropFirst()) : hex
        var rgb: UInt64 = 0
        Scanner(string: h).scanHexInt64(&rgb)
        self.init(
            red:   Double((rgb >> 16) & 0xFF) / 255,
            green: Double((rgb >> 8)  & 0xFF) / 255,
            blue:  Double( rgb        & 0xFF) / 255
        )
    }
}
