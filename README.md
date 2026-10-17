# wely-ios

Native iOS client for Wely (SwiftUI, iOS 18+). It talks to the same gateway as wely-web and
signs in through the same Keycloak realm.

## Run

1. Start the local stack: `~/Documents/wely-app/wely up` (gateway :8081, Keycloak :8080).
2. Open `Wely.xcodeproj` in Xcode, pick an iPhone simulator, press ⌘R.

Sign-in happens on the app's own screen: the username and password go to Keycloak's token
endpoint (direct access grant, enabled on the public client `wely-client`). Signing up and
resetting a password still open Keycloak's pages, with the authorization code flow and PKCE;
Keycloak must list `wely://oauth-callback` among its redirect URIs (done in
`wely-gitops-infra/overlays/local/keycloak/wely-realm.json`).

**Demo mode** — enable the `-WelyDemo` argument in *Product › Scheme › Edit Scheme › Run ›
Arguments* (Debug only): signed in against an in-memory gateway (`DemoTransport`) with sample
data, no backend needed. Debug builds also take `-WelyTab feed|messages|social|profile` and
`-WelyOpen /event/<id>` (any wely-web path) to start on a given screen.

From the command line:

```sh
xcodebuild test -project Wely.xcodeproj -scheme Wely -destination 'platform=iOS Simulator,name=iPhone 17'
```

## Environments

URLs are build settings of the `Wely` target (`WELY_GATEWAY_URL`, `WELY_KEYCLOAK_URL`,
`WELY_WEB_URL`), read at runtime from `Config/Wely-Info.plist`. In the simulator they point
at `localhost`, which it shares with the Mac; on a real iPhone (`sdk=iphoneos*`), which cannot
reach the Mac's `localhost`, at the dev infra (`dev-web.welylabs.app`, `dev-auth.welylabs.app`).

## On a real iPhone

Signing comes from `Config/Signing.xcconfig`. Put your team and a bundle id of your own in
`Config/Signing.local.xcconfig` (ignored by git), not in the project's settings:

```
DEVELOPMENT_TEAM = ABCDE12345
PRODUCT_BUNDLE_IDENTIFIER = com.yourname.wely
```

The team id is in Xcode → Settings → Accounts. With a free Apple ID, plug the iPhone in before
the first build (Xcode registers it to create the profile), turn on Developer Mode, then trust
the profile in Settings → General → VPN & Device Management. The app expires after 7 days.

## Layout

| Folder | What |
| --- | --- |
| `Wely/App` | entry point, `AppModel` (services, people, notifications, chat socket), tabs, routes |
| `Wely/Core/Auth` | Keycloak sign-in (password grant; PKCE for sign-up), tokens in the Keychain, refresh |
| `Wely/DesignSystem` | wely-web's look: colours, Outfit, buttons, cards, the tab bar's pieces |
| `Wely/Core/API` | gateway client (JSON, multipart, business error codes), lenient decoding |
| `Wely/Core/Realtime` | RSocket over WebSocket (chat), server-sent events (notifications, polls) |
| `Wely/Core/Backend` | `DemoTransport`, the in-memory gateway of the demo mode |
| `Wely/Models` | the wire types, as wely-web's models |
| `Wely/Services` | one struct per backend service, same routes as wely-web |
| `Wely/Features` | calendar, explore (feed + map), events (detail, form, poll, expenses), social (friends, people), communities, chat, notifications, profile, preferences |
| `WelyTests` | Swift Testing unit tests |

Not ported yet: calls (WebRTC) and push notifications (APNs, needs a backend change).
