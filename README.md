# Swift Tesla BLE

A Swift Package for communicating with Tesla vehicles over BLE. Provides scanning, pairing (AddKey), and vehicle-state fetching through a single `TeslaVehicleClient` actor.

> ⚠️ **Status: v0.1.0 has not been hardware-verified.** The package builds cleanly and all unit tests pass, but no real-device validation has been performed against this extracted codebase. Integrate at your own risk until a follow-up verification task lands.

## Requirements

- macOS with Xcode 16+
- iOS 17+ deployment target
- Swift 6.2 toolchain (see `.swift-version`)
- Go 1.21+ on `$PATH` (to build the bundled `TeslaCommand.xcframework`)

## First Build

`TeslaCommand.xcframework` is produced at build time from `Vendor/tesla-vehicle-command` plus `GoPatches/mobile.go`. You must run the build script once after cloning before `swift build` will work.

```bash
git clone --recursive <repo-url>
cd swift-tesla-ble
./scripts/bootstrap.sh         # installs gomobile if missing (one time)
./scripts/build-xcframework.sh # ~3–5 min cold, ~30 s incremental
swift test
```

## Integrating into an app

swift-tesla-ble ships its `TeslaCommand.xcframework` binary target as a _build-time product_ — the repo does not check in the xcframework, it's generated from the vendored `tesla-vehicle-command` submodule by `scripts/build-xcframework.sh`. SwiftPM itself has no mechanism to run that script automatically (build-tool plugins are sandboxed and cannot invoke `gomobile`), so the consuming app has to trigger it.

Until a pre-built binary is published to GitHub Releases, the supported integration path is a **local SwiftPM dependency + Xcode Run Script Phase**.

### Step 1 — Add swift-tesla-ble as a local package

Either place the repo next to your app repo and declare a local dependency in `Package.swift`:

```swift
.package(path: "../swift-tesla-ble")
```

…or in Xcode: `File → Add Package Dependencies… → Add Local…` and pick the `swift-tesla-ble` directory.

### Step 2 — Add a Run Script build phase to your app target

In the app's Xcode project, select the app target → **Build Phases** → **+** → **New Run Script Phase**. Drag it so it runs **before "Compile Sources"**. Paste:

```bash
set -euo pipefail
PKG_DIR="${SRCROOT}/../swift-tesla-ble"   # adjust to wherever your local package lives
if [ ! -x "${PKG_DIR}/scripts/build-xcframework.sh" ]; then
    echo "warning: swift-tesla-ble build script not found at ${PKG_DIR}; skipping"
    exit 0
fi
"${PKG_DIR}/scripts/bootstrap.sh"
"${PKG_DIR}/scripts/build-xcframework.sh"
```

Uncheck **"Based on dependency analysis"** (this phase always runs, and `gomobile` caches its own work so the hot path is quick). The first run takes ~3–5 minutes; subsequent incremental runs are ~5–10 seconds.

**Your machine (and CI) must have Go 1.21+ and `gomobile` installed**, exactly as documented under [Requirements](#requirements). `bootstrap.sh` will install `gomobile` via `go install` if missing, but cannot install Go itself.

### Step 3 — Import and use

```swift
import TeslaBLE
// ... see Usage below
```

### Why not automatic via SwiftPM alone?

- **Build Tool Plugins** run in a sandbox with no network access and no arbitrary process execution — they cannot invoke `go`/`gomobile`. They're designed for in-place code generators (SwiftGen, SwiftProtobuf, etc.), not for producing binary targets.
- **Command Plugins** (`swift package plugin …`) can request network + write permissions, but still require explicit invocation — they do not hook into `swift build` or Xcode build phases automatically.
- **`.binaryTarget(url: checksum:)`** (the Firebase / AWS SDK pattern) _would_ make integration zero-config for consumers, but it requires publishing the built xcframework to a GitHub Release first. That is the planned path once swift-tesla-ble stabilizes; see [Future work](#future-work).

### Future work

- **Publish pre-built xcframework to GitHub Releases** and switch `Package.swift` to `.binaryTarget(url: checksum:)`. Consumers will no longer need Go, `gomobile`, or any Run Script Phase — `swift build` will resolve and download the binary automatically. This is the idiomatic SwiftPM distribution pattern and removes the entire per-app integration burden above.
- **Upstream `mobile.go` into a fork of `tesla-vehicle-command`** so the build script no longer patches the submodule in place.

## Usage

```swift
import TeslaBLE

let keyStore = KeychainTeslaKeyStore(service: "com.example.teslaBLE")
let logger = OSLogTeslaBLELogger()
let client = TeslaVehicleClient(
    vin: "5YJ...",
    keyStore: keyStore,
    logger: logger
)

Task {
    for await state in client.stateStream {
        print("State: \(state)")
    }
}

try await client.connect()
let snapshot = try await client.fetchVehicleData()
print("Battery: \(snapshot.charge?.batteryLevel ?? -1)%")
```

## License

MIT. See `LICENSE`.
