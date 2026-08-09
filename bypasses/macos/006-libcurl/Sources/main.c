// Bypass case 006 — link libcurl and use it.
//
// No dynamic loading, no trickery: /usr/lib/libcurl.4.dylib is in the link
// table and curl_easy_* are in the symbol table. This is what an app would do
// if it simply wanted HTTP and did not care to hide it.
//
// 192.0.2.1 is TEST-NET-1 (RFC 5737): reserved for documentation, assigned to
// nobody, routed nowhere. A fixture in this corpus must never reach a real
// service, and a connection attempt there hangs in SYN_SENT long enough for
// the runtime layer to see the socket.
#include <curl/curl.h>
#include <stdio.h>
#include <unistd.h>

int main(void) {
    // Assembled at runtime so no `http://…` literal survives into the binary.
    // Layer 3 looks for those strings, and an author doing this deliberately
    // would not leave one — the point of this case is what layers 1 and 2 miss.
    char url[64];
    int a = 192, b = 0, c2 = 2, d = 1;
    snprintf(url, sizeof url, "%s%d.%d.%d.%d/%s", "htt" "p://", a, b, c2, d, "collect");

    curl_global_init(CURL_GLOBAL_DEFAULT);
    CURL *c = curl_easy_init();
    if (c) {
        curl_easy_setopt(c, CURLOPT_URL, url);
        curl_easy_setopt(c, CURLOPT_TIMEOUT, 25L);
        curl_easy_perform(c);
        curl_easy_cleanup(c);
    }
    curl_global_cleanup();
    return 0;
}
