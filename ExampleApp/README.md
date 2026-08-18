# Synheart Core iOS Example

This SwiftUI app is a runnable integration harness for `SynheartCore`. It uses
the repository root as a local Swift package and demonstrates:

- runtime ABI diagnostics and truthful initialization failures;
- development configuration without embedding production secrets;
- consent-gated feature activation and native session lifecycle;
- typed HSI 1.3 and raw JSON delivery;
- runtime-backed sync, storage usage, session catalog, and orphan repair;
- copyable diagnostics for device and integration bug reports.

## Run the app

1. Open `SynheartExample.xcodeproj` in Xcode.
2. Select the `SynheartExample` scheme and an iOS 16+ device or simulator.
3. Link/embed the current Synheart native runtime in the app target when testing
   real sessions. Without it, the app still launches and the Diagnostics tab
   reports every missing required and optional symbol.
4. Enter an app ID and pseudonymous subject ID, then initialize.
5. Grant at least one collection consent before starting a session.

### Install the native runtime

The preferred flow is to install a built runtime distribution with the
Synheart CLI:

```bash
synheart runtime install --from /path/to/runtime-dist --project ExampleApp
```

For sibling-repository development, build the XCFramework from
`synheart-core-runtime` with `make ios`, add
`build/ios-edge/SynheartCoreRuntime.xcframework` to the app target's
**Frameworks, Libraries, and Embedded Content**, and select **Embed & Sign** for
device builds. The Diagnostics tab must report a compatible required ABI before
session testing begins.

Unsigned capabilities are enabled by default for local development. Production
hosts must supply a server-issued capability token and must not ship embedded
capability secrets.

## Command-line build

```bash
xcodebuild \
  -project ExampleApp/SynheartExample.xcodeproj \
  -scheme SynheartExample \
  -destination 'generic/platform=iOS Simulator' \
  IPHONEOS_DEPLOYMENT_TARGET=16.0 \
  CODE_SIGNING_ALLOWED=NO \
  build
```

The explicit deployment-target override is currently necessary because
`synheart-wear-swift` 0.4.1 declares iOS 13 in its package manifest while its
HealthKit backfill implementation uses iOS 16 sleep-stage APIs. It can be
removed after that dependency raises its declared platform minimum.

The example deliberately does not provide an implicit mock wearable. Add a real
wear source in the host integration or explicitly inject a mock in test-only
code.
