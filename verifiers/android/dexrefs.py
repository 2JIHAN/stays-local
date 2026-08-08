#!/usr/bin/env python3
"""Lists the type and method references in a DEX file.

    dexrefs.py <classes.dex> [--strings]

Reads the type_ids and method_ids tables directly. Two reasons not to run
`strings` over the file instead: a string match cannot tell a constant-pool
descriptor from an app that merely logs the words "java.net.Socket", and it
cannot separate `java.net.URI` — which parses text and touches nothing — from
`java.net.URL.openStream`, which is the network. That distinction is the
difference between a rule reviewers trust and one false positive away from
being discredited.

Stdlib only. A contributor should be able to read and rerun this without
installing anything.
"""
import struct
import sys

HEADER_SIZE = 0x70


class Dex:
    def __init__(self, data: bytes):
        if data[:4] not in (b"dex\n",):
            raise ValueError("not a DEX file")
        self.d = data
        (self.string_ids_size, self.string_ids_off,
         self.type_ids_size, self.type_ids_off,
         self.proto_ids_size, self.proto_ids_off,
         self.field_ids_size, self.field_ids_off,
         self.method_ids_size, self.method_ids_off) = struct.unpack_from("<10I", data, 56)

    def _uleb128(self, off: int):
        result = shift = 0
        while True:
            b = self.d[off]
            off += 1
            result |= (b & 0x7F) << shift
            if not b & 0x80:
                return result, off
            shift += 7

    def string(self, idx: int) -> str:
        off = struct.unpack_from("<I", self.d, self.string_ids_off + idx * 4)[0]
        _, off = self._uleb128(off)          # length in UTF-16 code units
        end = self.d.index(b"\x00", off)
        # MUTF-8. surrogatepass keeps malformed input from raising; these are
        # descriptors, and a broken one should be reported, not crash the run.
        return self.d[off:end].decode("utf-8", errors="replace")

    def type_string(self, idx: int) -> str:
        return self.string(struct.unpack_from("<I", self.d, self.type_ids_off + idx * 4)[0])

    def types(self):
        for i in range(self.type_ids_size):
            yield self.type_string(i)

    def methods(self):
        for i in range(self.method_ids_size):
            class_idx, _proto_idx, name_idx = struct.unpack_from(
                "<HHI", self.d, self.method_ids_off + i * 8)
            yield f"{self.type_string(class_idx)}->{self.string(name_idx)}"

    def strings(self):
        for i in range(self.string_ids_size):
            yield self.string(i)


def main() -> None:
    path = sys.argv[1]
    want_strings = "--strings" in sys.argv
    dex = Dex(open(path, "rb").read())
    out = dex.strings() if want_strings else list(dex.types()) + list(dex.methods())
    for item in out:
        print(item)


if __name__ == "__main__":
    main()
