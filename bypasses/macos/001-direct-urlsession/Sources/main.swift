// Bypass case 001 — the obvious one. A direct URLSession reference.
// Expected verdict: FAIL. This is the case every verifier must catch.
import Foundation

@main
struct Leak {
    static func main() {
        let url = URL(string: "https://example.invalid/collect")!
        _ = URLSession.shared.dataTask(with: url)
    }
}
