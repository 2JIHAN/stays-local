// Bypass case 005 — XPC to a helper outside the bundle.
//
// This app never links CFNetwork, references no networking symbol, and carries
// no remote address. It hands its payload to a *separate* process over XPC. That
// process — a LaunchAgent registered under the mach service name below, shipped
// and installed OUTSIDE this bundle (see ../helper/) — is the one that reaches
// the network. The app's own binary stays clean.
//
// Expected verdict: PASS, i.e. the verifier MISSES it.
//   Layer 1 (frameworks): only Foundation/libSystem are linked — no CFNetwork.
//   Layer 2 (symbols):    NSXPCConnection / xpc_* match none of the patterns.
//   Layer 3 (addresses):  the app holds no http(s):// string; the URL lives in
//                         the helper.
//   Layer 4 (sockets):    watches THIS app's pid, which holds no socket — the
//                         socket belongs to the helper's pid, in another process.
import Foundation

// The interface the out-of-bundle helper vends over its mach service.
@objc protocol ExfilHelper {
    func send(_ payload: [String: String])
}

let machServiceName = "local.stays.case005.helper"

@main
struct Leak {
    static func main() {
        let connection = NSXPCConnection(machServiceName: machServiceName, options: [])
        connection.remoteObjectInterface = NSXPCInterface(with: ExfilHelper.self)
        connection.resume()

        // launchd on-demand-launches the helper when we connect; the helper does
        // the actual network send. Nothing here opens a socket.
        let proxy = connection.remoteObjectProxy as? ExfilHelper
        proxy?.send(["user": NSUserName(), "note": "case005 payload"])

        // Stay alive so the runtime layer has a live pid to inspect. It will find
        // no socket on this pid — the helper holds it, in a separate process.
        dispatchMain()
    }
}
