# Synheart Core iOS Example

This SwiftUI app is an integration harness for `SynheartCore`. It starts in
**local-only mode** and does not need a server or an app secret. It makes the
important runtime boundaries visible:

- the consent choice saved by the user versus the consent actually enforced;
- real behavior events, motion samples, HSI deliveries, and data-bearing HSI;
- independent collector startup failures;
- native upload queue state, device registration, attestation, and flush errors;
- runtime ABI, storage, session catalog, and orphan-session diagnostics.

## Build and run

1. Open `SynheartExample.xcodeproj` in Xcode.
2. Select the `SynheartExample` scheme and an iOS 16+ simulator or device.
3. Link/embed the current native runtime. Without it, the app still opens and
   the Diagnostics tab lists the missing native symbols.
4. Run the app and tap **Initialize SDK**.

The app persists one pseudonymous subject ID and one device ID in
`UserDefaults`. They do not change every time the view or app is recreated.

### Install a local native runtime

Install a built distribution with the Synheart CLI:

```bash
synheart runtime install --from /path/to/runtime-dist --project ExampleApp
```

For sibling-repository development, build the XCFramework from the native
runtime repository with `make ios`, add
`build/ios-edge/SynheartCoreRuntime.xcframework` to **Frameworks, Libraries,
and Embedded Content**, and use **Embed & Sign** for a physical device.

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
SYNHEART_AUTH_BASE_URL
SYNHEART_CONSENT_BASE_URL
SYNHEART_ORG_ID
SYNHEART_PACKAGE_NAME
```

Then:

1. Add the **App Attest** capability under Signing & Capabilities.
2. Initialize and confirm the app says **Cloud test**.
3. Tap **Register Device** and inspect its registration and attestation state.
4. Enable a collection category and **Cloud upload**.
5. Start a session and wait for a closed HSI window.
6. Open **Data**. The native queue should update automatically.
7. Tap **Flush Upload Queue** and inspect uploaded/requeued counts or the typed
   native failure reason.

Do not manually enqueue every HSI callback. The native runtime already enqueues
closed HSI windows; doing it again duplicates uploads.

Development servers may explicitly allow unattested Debug registration.
Release builds always disable that shortcut. Never add a private server secret,
static capability secret, or API key to the app bundle.

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

The deployment override is needed while `synheart-wear-swift` declares iOS 13
but uses iOS 16 HealthKit sleep-stage APIs. The example deliberately has no
implicit mock wearable; tests must inject mocks explicitly.
