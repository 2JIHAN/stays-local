# stays local — Windows, spec v1 (draft)

**Status: draft. No verifier yet — [help wanted](https://github.com/2JIHAN/stays-local/labels/verifier).**

Read `spec/core.md` first.

Windows is close to macOS in shape: the evidence is what the executable imports. It is harder in one specific way — `LoadLibrary` is idiomatic on Windows in a way that `dlopen` is not on macOS, so the import table alone proves less.

## Subject

An `.exe`, or a directory of files containing one, built from public source. Every PE in the artifact is checked — executables, DLLs, and any bundled runtime.

## Layers

### 1. Imported modules — required

No PE imports from `WS2_32.dll`, `WSOCK32.dll`, `WININET.dll`, `WINHTTP.dll`, `URLMON.dll`, `IPHLPAPI.dll`, or `MSWSOCK.dll`.

Read the import directory with `dumpbin /imports` or `llvm-readobj --coff-imports`.

### 2. Delay-loaded and dynamically resolved modules — required

The same DLL names must not appear in the delay-load import directory, nor as strings anywhere in the artifact.

The string check exists because `LoadLibrary("winhttp.dll")` leaves nothing in the import table but does leave the name. It is crude and it will produce false positives on, say, a bundled library that merely mentions the name — those get resolved by declaring them, the same way remote addresses are.

### 3. Managed code references — required

For .NET assemblies, no reference to `System.Net`, `System.Net.Http`, `System.Net.Sockets`, or `System.Net.WebClient` in the assembly's reference table. Single-file and AOT-published apps must be scanned as native PEs under layers 1 and 2 instead.

### 4. Remote addresses — required

Same rule as every platform. `ShellExecute` to the user's browser is the legitimate case.

### 5. Sockets while running — conditional

Launch the app and poll `Get-NetTCPConnection -OwningProcess <pid>` and `Get-NetUDPEndpoint` for 20 seconds. Zero entries.

## Open questions for whoever implements this

- **Electron and other bundled runtimes.** They link everything, so they cannot pass layer 1, and that is probably correct — a bundled Chromium *can* reach the network whatever the app intends. Should such apps be out of scope, or get a separate track?
- **The string check in layer 2 is noisy.** Is declaring false positives good enough, or does it need symbol-level analysis?
- **Which toolchain in CI.** `windows-latest` runners have MSVC (`dumpbin`); LLVM tools are more portable but need installing.
