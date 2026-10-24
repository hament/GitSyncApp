import Foundation

nonisolated struct CloneAuthenticationGuide: Hashable, Sendable {
    let server: String
    let configureCommand: String
    let authenticateCommand: String

    init?(address: String, failure: String, gitPath: String) {
        guard Self.isAuthenticationFailure(failure),
              let components = URLComponents(string: address.trimmingCharacters(in: .whitespacesAndNewlines)),
              components.scheme?.lowercased() == "https",
              let host = components.host, !host.isEmpty,
              components.user == nil, components.password == nil,
              components.query == nil, components.fragment == nil,
              !components.path.isEmpty, components.path != "/",
              gitPath.hasPrefix("/"), !gitPath.contains("\0") else { return nil }

        var origin = URLComponents()
        origin.scheme = "https"
        origin.host = host
        origin.port = components.port
        guard let server = origin.string, let address = components.string else { return nil }
        self.server = server
        let git = Self.shellQuote(gitPath)
        let key = Self.shellQuote("credential.\(server).helper")
        configureCommand = "\(git) config --global --replace-all \(key) '' &&\n"
            + "\(git) config --global --add \(key) osxkeychain"
        authenticateCommand = "env -u GIT_ASKPASS -u SSH_ASKPASS GIT_TERMINAL_PROMPT=1 "
            + "\(git) -C / -c core.askPass= -c credential.interactive=true "
            + "ls-remote -- \(Self.shellQuote(address)) HEAD"
    }

    static func isAuthenticationFailure(_ failure: String) -> Bool {
        let failure = failure.lowercased()
        return [
            "authentication failed", "authentication required", "invalid username or password",
            "could not read username", "could not read password", "unable to get password",
            "terminal prompts disabled", "http basic: access denied", "returned error: 401",
            "support for password authentication was removed",
        ].contains { failure.contains($0) }
    }

    private static func shellQuote(_ value: String) -> String {
        "'" + value.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }
}
