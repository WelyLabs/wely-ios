# wely-ios

Native iOS client for Wely (SwiftUI, iOS 18+). It talks to the same gateway as wely-web and
signs in through the same Keycloak realm.

## Run

1. Start the local stack: `~/Documents/wely-app/wely up` (gateway :8081, Keycloak :8080).
2. Open `Wely.xcodeproj` in Xcode, pick an iPhone simulator, press ⌘R.

Sign-in uses the authorization code flow with PKCE on the public client `wely-client`; Keycloak
must list `wely://oauth-callback` among its redirect URIs (done in
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
`WELY_WEB_URL`), read at runtime from `Config/Wely-Info.plist`. They default to `localhost`,
which the simulator shares with the Mac.

## Layout

| Folder | What |
| --- | --- |
| `Wely/App` | entry point, `AppModel` (services, people, notifications, chat socket), tabs, routes |
| `Wely/Core/Auth` | Keycloak sign-in (PKCE), tokens in the Keychain, refresh |
| `Wely/Core/API` | gateway client (JSON, multipart, business error codes), lenient decoding |
| `Wely/Core/Realtime` | RSocket over WebSocket (chat), server-sent events (notifications, polls) |
| `Wely/Core/Backend` | `DemoTransport`, the in-memory gateway of the demo mode |
| `Wely/Models` | the wire types, as wely-web's models |
| `Wely/Services` | one struct per backend service, same routes as wely-web |
| `Wely/Features` | calendar, explore (feed + map), events (detail, form, poll, expenses), social (friends, people), communities, chat, notifications, profile |
| `WelyTests` | Swift Testing unit tests |

Not ported yet: calls (WebRTC) and push notifications (APNs, needs a backend change).
