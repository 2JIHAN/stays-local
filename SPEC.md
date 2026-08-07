# stays local — spec v1

## What the badge claims

The app's shipped code contains no way to reach the network, and an observed run opened no sockets.

## What it does not claim

Read this before trusting the badge.

| Not covered | Why |
|---|---|
| Code the app shells out to | `curl` in a script the app runs is invisible to a Mach-O scan |
| XPC or IPC to another process | The app can ask a daemon that does have network access |
| Files written for another app to upload | Nothing leaves *this* process; something else may carry it |
| Code loaded at runtime | A plugin or downloaded dylib is not in the bundle we checked |
| The binary you downloaded | The check runs on a build from public source. Ask for build provenance separately |

The badge is about one specific, checkable property. It is not a privacy audit.

## Criteria

An app passes when all three required layers pass on a build produced from its public source.

### 1. No networking frameworks linked — required

No Mach-O in the bundle links `CFNetwork`, `Network.framework`, or `libnetwork`.

This is the load-bearing check. Source greps can be worked around; reaching the network cannot be done without pulling in these, and that shows up in `otool -L`.

### 2. No networking symbols referenced — required

No Mach-O references `URLSession`, `NWConnection`, `CFSocket`, `CFStream`, `NSURLConnection`, `getaddrinfo`, or the raw `connect`/`socket` syscalls.

### 3. No undeclared remote addresses — required

Every `http://` or `https://` string in the bundle must appear in `declared_urls` in the manifest, with a reason. Declared addresses are published on the registry entry, so declaring is disclosure, not an exemption.

The common legitimate case is a URL handed to the user's browser — the app opens it via `NSWorkspace`/`LSOpen` and never connects itself.

### 4. No sockets while running — recorded, not required

The app is launched and watched for 20 seconds; it must hold zero open sockets. This layer is skipped in headless environments, and the registry entry records whether it ran.

Every Mach-O in the bundle is checked, not just the main executable — helpers, XPC services, and embedded frameworks included.

## Manifest

`stays-local.json` in the repository root:

```json
{
  "name": "Steam Shelf",
  "repository": "https://github.com/2JIHAN/steam-shelf",
  "build": "./build.sh \"$STAYS_LOCAL_OUT\"",
  "bundle": "Steam Shelf.app",
  "declared_urls": [
    {
      "url": "store.steampowered.com",
      "reason": "Handed to the user's browser by NSWorkspace when they pick Open Store Page. The app itself never connects."
    }
  ]
}
```

| Field | Meaning |
|---|---|
| `name` | Display name on the registry |
| `repository` | Public source. Required — a closed-source app cannot be certified |
| `build` | Command that builds the bundle into `$STAYS_LOCAL_OUT`. Must need no secrets |
| `bundle` | Bundle name inside `$STAYS_LOCAL_OUT` |
| `declared_urls` | Every remote address in the binary, each with a reason |

## Certification

The check runs in this repository's CI, on a fresh checkout of the applicant's public source. It is not run by the applicant on their own machine, and the run log is public.

Certified entries are re-verified weekly against the default branch. An entry that stops passing is marked `failed` in the registry, and the badge follows the registry, so a badge that stops being true stops rendering as verified.

## Scope

macOS app bundles, v1. Other platforms need their own layer definitions and are not covered.
