import Network
import SafariServices

/// Safari keeps the app active while the system browser follows the IPv4 loopback redirect.
@MainActor
final class SignInBrowser: NSObject, @MainActor SFSafariViewControllerDelegate {
    private var browser: SFSafariViewController?
    private var listener: NWListener?
    private var pending: CheckedContinuation<(URL, URL), Error>?
    private var timer: Task<Void, Never>?
    private var connections: [ObjectIdentifier: NWConnection] = [:]

    func authorize(state: String, url: @escaping (URL) -> URL) async throws -> (URL, URL) {
        let parameters = NWParameters.tcp
        parameters.requiredLocalEndpoint = .hostPort(host: "127.0.0.1", port: .any)
        let listener = try NWListener(using: parameters)
        self.listener = listener
        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                pending = continuation
                listener.stateUpdateHandler = { [weak self] status in
                    Task { @MainActor in
                        guard let self, self.pending != nil else { return }
                        switch status {
                        case .ready:
                            guard let port = listener.port else { self.finish(.failure(URLError(.cannotConnectToHost))); return }
                            let redirect = URL(string: "http://127.0.0.1:\(port.rawValue)/auth/callback")!
                            self.present(url(redirect))
                        case .failed(let error): self.finish(.failure(error))
                        default: break
                        }
                    }
                }
                listener.newConnectionHandler = { [weak self] connection in
                    Task { @MainActor in
                        guard let self, let port = listener.port else { connection.cancel(); return }
                        let redirect = URL(string: "http://127.0.0.1:\(port.rawValue)/auth/callback")!
                        self.accept(connection, redirect: redirect, state: state)
                    }
                }
                listener.start(queue: .main)
                timer = Task {
                    try? await Task.sleep(for: .seconds(300))
                    if !Task.isCancelled { finish(.failure(URLError(.timedOut))) }
                }
            }
        } onCancel: { Task { @MainActor in self.finish(.failure(CancellationError())) } }
    }

    private func present(_ url: URL) {
        let scene = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
            .first { $0.activationState == .foregroundActive }
        guard var presenter = scene?.keyWindow?.rootViewController else {
            finish(.failure(StudyError.message(String(localized: "認証画面を開けませんでした。")))); return
        }
        while let next = presenter.presentedViewController { presenter = next }
        let safari = SFSafariViewController(url: url)
        safari.delegate = self
        browser = safari
        presenter.present(safari, animated: true)
    }

    private func accept(_ connection: NWConnection, redirect: URL, state: String) {
        guard pending != nil, connections.count < 8 else { connection.cancel(); return }
        connections[ObjectIdentifier(connection)] = connection
        connection.start(queue: .main)
        read(connection, data: Data(), redirect: redirect, state: state)
    }

    private func read(_ connection: NWConnection, data: Data, redirect: URL, state: String) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 8192) { chunk, _, done, error in
            Task { @MainActor in
                let buffer = data + (chunk ?? Data())
                guard self.pending != nil, error == nil, buffer.count <= 16384 else { self.close(connection); return }
                guard let end = buffer.range(of: Data([13, 10])) else {
                    if done { self.close(connection) }
                    else { self.read(connection, data: buffer, redirect: redirect, state: state) }
                    return
                }
                let line = String(decoding: buffer[..<end.lowerBound], as: UTF8.self).split(separator: " ")
                guard line.count == 3, line[0] == "GET", line[1].hasPrefix("/auth/callback?"),
                      let callback = URL(string: String(line[1]), relativeTo: redirect)?.absoluteURL,
                      let items = URLComponents(url: callback, resolvingAgainstBaseURL: false)?.queryItems,
                      items.filter({ $0.name == "state" }).map(\.value) == [state] else { self.close(connection); return }
                let reply = "HTTP/1.1 200 OK\r\nContent-Type: text/plain\r\nCache-Control: no-store\r\nConnection: close\r\n\r\nYou can return to Pocket IELTS."
                connection.send(content: Data(reply.utf8), completion: .contentProcessed { _ in
                    Task { @MainActor in self.finish(.success((callback, redirect))) }
                })
            }
        }
    }

    private func close(_ connection: NWConnection) {
        connections.removeValue(forKey: ObjectIdentifier(connection))
        connection.cancel()
    }

    func safariViewControllerDidFinish(_ controller: SFSafariViewController) {
        finish(.failure(CancellationError()))
    }

    private func finish(_ result: Result<(URL, URL), Error>) {
        guard let pending else { return }
        self.pending = nil
        timer?.cancel()
        timer = nil
        listener?.cancel()
        listener = nil
        for connection in connections.values { connection.cancel() }
        connections.removeAll()
        browser?.dismiss(animated: true)
        browser = nil
        pending.resume(with: result)
    }
}
