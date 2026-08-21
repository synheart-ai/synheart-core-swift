# Synheart Core iOS Example

This SwiftUI app is an integration harness for `SynheartCore`. It starts in
**local-only mode** and does not need a server or an app secret. It makes the
important runtime boundaries visible:

- the consent choice saved by the user versus the consent actually enforced;
- real behavior events, motion samples, HSI deliveries, and data-bearing HSI;
- independent collector startup failures;
- native upload queue state, device registration, attestation, and flush errors;
- runtime ABI, storage, session catalog, and orphan-session diagnostics.

## Requirements

- Xcode with an iOS 16 or newer SDK;
- CocoaPods 1.16 or newer (`pod install` for native-runtime mode and
  `pod deintegrate` for source-only mode);
- Apple Silicon when running the native runtime in the iOS Simulator.

The distributed runtime currently contains `arm64` device and `arm64`
simulator slices. It can build for a physical iPhone from an Intel Mac, but its
simulator framework does not contain an `x86_64` slice.

## Build and run

The example supports two intentionally different integration modes. Choose one
before opening it in Xcode.

### Native-runtime mode (recommended)

Use this mode to initialize the SDK, collect data, generate HSI, and exercise
local storage or cloud ingestion. From the repository root:

```bash
synheart runtime install --from /path/to/runtime-dist --project ExampleApp
cd ExampleApp
pod install
```

The CLI must install the framework at:

```text
ExampleApp/synheart/vendor/runtime/ios/SynheartCoreRuntime.xcframework
```

That exact path is consumed by `SynheartCoreRuntimeHost.podspec` and excluded
from Git. If you copy a runtime manually, copy the complete XCFramework to that
location; do not add it separately under **Frameworks, Libraries, and Embedded
Content** because CocoaPods owns the embedding step.

After `pod install`:

1. Open `ExampleApp/SynheartExample.xcworkspace` in Xcode, not the
   `.xcodeproj`.
2. Select the `SynheartExample` scheme and an iOS 16+ simulator or device.
3. Run the app and tap **Initialize SDK**.

The committed Xcode project contains the CocoaPods integration, while the
generated `Pods/`, workspace, and native runtime remain ignored. A clean
checkout must therefore install the runtime and run `pod install` before the
workspace can be built.

### Source-only diagnostic mode

Use this mode to inspect the UI or verify that missing native dependencies are
reported safely. Sessions, storage, HSI, and cloud ingestion are unavailable
without the native runtime. This is the mode built by GitHub CI.

On a disposable checkout, remove the committed CocoaPods integration and build
the project directly:

```bash
pod deintegrate ExampleApp/SynheartExample.xcodeproj
xcodebuild -quiet \
  -project ExampleApp/SynheartExample.xcodeproj \
  -scheme SynheartExample \
  -destination 'generic/platform=iOS Simulator' \
  ARCHS=arm64 \
  ONLY_ACTIVE_ARCH=YES \
  IPHONEOS_DEPLOYMENT_TARGET=16.0 \
  CODE_SIGNING_ALLOWED=NO \
  build
```

`pod deintegrate` modifies the tracked Xcode project, which is why this command
is intended for an ephemeral CI or disposable checkout rather than switching a
working native-runtime checkout back and forth.

The app persists one pseudonymous subject ID and one device ID in
`UserDefaults`. They do not change every time the view or app is recreated.

The example's local pod embeds that XCFramework and installs
`onnxruntime-c`. For stable/lab runtimes it also force-loads ONNX Runtime so
`OrtGetApiBase` cannot be stripped from the app. Without this link step, older
host packaging allowed initialization but crashed when a session first created
the ONNX pipeline. The SDK now blocks that call and reports the missing host
dependency in **Diagnostics**.

An edge runtime does not use ONNX and is detected automatically, so it does not
require `onnxruntime-c` at session start even though the example installation
keeps the dependency available.

## Easy local ingestion test

This is the quickest honest test and needs no cloud account:

1. On **Setup**, initialize the SDK. The mode should say **Local only**.
2. On **Session**, enable **Behavior** under Requested choice.
3. Confirm **Behavior — Allowed** appears under Runtime enforced.
4. Start a session and interact with the app: tap, scroll, and switch tabs.
5. Confirm **Behavior events** increases.
6. Leave the session running for about 60 seconds, then inspect **Live HSI**.

`HSI deliveries` proves that the engine emitted a window. `HSI with data
basis` proves that at least one axis has non-zero confidence. Those counts are
intentionally separate. Behavior input can produce digital HSI axes; physical
signals such as HRV require a real supported sensor source.

To test phone ingestion, enable **Phone context**, start a session on a physical
iPhone, move the phone, and verify **Motion samples** increases. The production
example never generates random phone events.

## Cloud upload test

The cloud path is opt-in. Copy `Config/Synheart.xcconfig.example` to an ignored
file such as `Config/Synheart.local.xcconfig`, set the values, and attach it as
the app target's Debug base configuration. You can also put the same variables
in the Xcode scheme's Run environment.

Required values:

```text
SYNHEART_APP_ID
SYNHEART_BASE_URL
SYNHEART_AUTH_URL
SYNHEART_CONSENT_BASE_URL
SYNHEART_ORG_ID
SYNHEART_PACKAGE_NAME
```

`SYNHEART_AUTH_BASE_URL` remains accepted as a compatibility alias.
`SYNHEART_TENANT_ID` and `SYNHEART_PROJECT_ID` may also be supplied so the
example can display the complete credentials context, but the current SDK does
not send those two values to the runtime.

The platform `app_…` identifier and `SYNHEART_PACKAGE_NAME` are different:
the latter must equal the installed app's bundle identifier. Use a dedicated
development app ID for Debug testing.

Then:

1. Add the **App Attest** capability under Signing & Capabilities.
2. Open **Data** and follow the **Guided cloud ingestion test** card. Its single
   action advances through SDK initialization, the cloud-upload choice that
   triggers device registration, effective cloud authorization, Behavior
   consent, real session collection, finalization, and queue flush.
3. While collection is running, interact with the app for about 60 seconds.
   Stop when HSI deliveries begin appearing so the runtime can finalize the
   session artifacts.
4. Confirm the card reaches **Cloud ingestion verified**. Expand **Technical
   details** for queue state, timestamps, batch ID, upload counts, typed failure
   information, and a copyable diagnostic report.

The card reports local-only configuration as an informational state, identifies
the exact blocked prerequisite, and never treats a successful zero-artifact
flush as proof of ingestion. A new guided run must produce a newer successful
upload before it is marked verified.

Do not manually enqueue every HSI callback. The native runtime already enqueues
closed HSI windows; doing it again duplicates uploads.

Development servers may explicitly allow unattested Debug registration.
Release builds always disable that shortcut. Never add a private server secret,
static capability secret, or API key to the app bundle.

Client configuration alone is insufficient. The platform must also associate
the development app ID with the exact bundle ID, enable development registration
when App Attest is unavailable, permit upload in app policy, and assign a consent
profile capable of issuing the verified cloud token. A policy refusal is
permanent until that server configuration changes; repeatedly retrying the same
request will not fix it.

## Command-line build

```bash
xcodebuild \
  -workspace ExampleApp/SynheartExample.xcworkspace \
  -scheme SynheartExample \
  -destination 'generic/platform=iOS Simulator' \
  ARCHS=arm64 \
  ONLY_ACTIVE_ARCH=YES \
  IPHONEOS_DEPLOYMENT_TARGET=16.0 \
  CODE_SIGNING_ALLOWED=NO \
  build
```

The deployment override is needed while `synheart-wear-swift` declares iOS 13
but uses iOS 16 HealthKit sleep-stage APIs. The example deliberately has no
implicit mock wearable; tests must inject mocks explicitly.
