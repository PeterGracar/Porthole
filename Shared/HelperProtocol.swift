import Foundation

/// Mach service name and launchd label of the privileged helper daemon.
let kMachServiceName = "io.github.petergracar.Porthole.helper"

/// Bumped whenever the XPC protocol or helper behavior changes; the app
/// re-registers the daemon when the running helper reports a different version.
let kHelperVersion = 2

let kPortExecutablePath = "/opt/local/bin/port"

@objc enum PortOperation: Int, CaseIterable {
    case install
    case uninstall
    case upgradeOutdated
    case selfupdate
    case reclaim
    case uninstallInactive
    case uninstallLeaves
    case activate
    case deactivate
    case clean
    // New cases go at the end so existing raw values stay stable.
    case upgrade

    var displayName: String {
        switch self {
        case .install: return "Install"
        case .uninstall: return "Uninstall"
        case .upgradeOutdated: return "Upgrade Outdated"
        case .selfupdate: return "Selfupdate"
        case .reclaim: return "Reclaim"
        case .uninstallInactive: return "Remove Inactive"
        case .uninstallLeaves: return "Uninstall Leaves"
        case .activate: return "Activate"
        case .deactivate: return "Deactivate"
        case .clean: return "Clean"
        case .upgrade: return "Upgrade"
        }
    }

    /// Whether the operation acts on explicitly named packages.
    var requiresPackages: Bool {
        switch self {
        case .install, .uninstall, .activate, .deactivate, .clean, .upgrade: return true
        default: return false
        }
    }

    /// Fixed argv for /opt/local/bin/port. The helper builds its own copy of
    /// this table and never accepts arbitrary arguments from the app.
    func arguments(packages: [String]) -> [String] {
        switch self {
        case .install: return ["-N", "install"] + packages
        case .uninstall: return ["-N", "uninstall"] + packages
        case .upgradeOutdated: return ["-N", "upgrade", "outdated"]
        case .selfupdate: return ["-N", "selfupdate"]
        case .reclaim: return ["-N", "reclaim"]
        case .uninstallInactive: return ["-N", "uninstall", "inactive"]
        case .uninstallLeaves: return ["-N", "uninstall", "leaves"]
        case .activate: return ["-N", "activate"] + packages
        case .deactivate: return ["-N", "deactivate"] + packages
        case .clean: return ["-N", "clean", "--all"] + packages
        case .upgrade: return ["-N", "upgrade"] + packages
        }
    }
}

enum PackageToken {
    private static let allowedCharacters = Set("abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789_.+-")

    /// A package argument is either a port name (`wget`) or a version spec
    /// (`@1.2.3_0+quartz`). The first character after the optional `@` must be
    /// alphanumeric so a token can never be mistaken for a command-line flag.
    static func isValid(_ token: String) -> Bool {
        var rest = Substring(token)
        if rest.first == "@" { rest = rest.dropFirst() }
        guard let first = rest.first, first.isASCII, first.isLetter || first.isNumber else { return false }
        return rest.allSatisfy { allowedCharacters.contains($0) }
    }

    /// Strips everything that is not a plain port-name character, so user input
    /// can be embedded in a `port search --glob` pattern safely.
    static func sanitizedSearchTerm(_ term: String) -> String {
        String(term.filter { allowedCharacters.contains($0) })
    }
}

/// Helper daemon's exported interface (app → daemon).
@objc protocol PortHelperProtocol {
    /// Handshake. The app calls this first; a mismatch with `kHelperVersion`
    /// makes the app re-register the daemon so launchd loads the new binary.
    func getVersion(reply: @escaping (Int) -> Void)

    /// Run one allowlisted operation. The raw value is validated against
    /// `PortOperation` inside the helper. The reply fires on process exit with
    /// (exitCode, errorMessage-or-nil).
    func run(operationRaw: Int, packages: [String], reply: @escaping (Int32, String?) -> Void)

    /// SIGINT the currently running port process. port traps INT and releases
    /// its registry lock, so this is safe mid-operation.
    func cancel()
}

/// App's exported interface (daemon → app), set as the XPC connection's
/// exported object so the daemon can stream output while a command runs.
@objc protocol PortHelperClientProtocol {
    /// Raw output chunk, not line-buffered; the app assembles lines and
    /// interprets carriage returns for progress display.
    func output(_ chunk: String, isStderr: Bool)
}
