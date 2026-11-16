# wely-ios

> One Auth0 tenant serves every environment, with an application and an API per environment
> (`wely-ios-dev`, `wely-api-dev`, `wely-dev-users` today), so the domain, client id, audience and connection come from the
> `WELY_AUTH_DOMAIN`, `WELY_AUTH_CLIENT_ID`, `WELY_AUTH_AUDIENCE` and `WELY_AUTH_CONNECTION` build settings rather than
> being constants. Device builds target dev; the simulator's gateway points wherever the settings
> say, since the `local` environment was retired in November 2026 with the datastores that backed it.

Native iOS client for Wely (SwiftUI, iOS 18+). It talks to the same gateway as wely-web and
signs in through the same Auth0 tenant.

## Run

1. Start the local stack: `~/Documents/wely-app/wely up` (gateway :8081).
2. Open `Wely.xcodeproj` in Xcode, pick an iPhone simulator, press ⌘R.

Sign-in happens on the app's own screen: the username and password go to Auth0's `/oauth/token`
(password-realm grant, `realm` = the `WELY_AUTH_CONNECTION` database connection, enabled as the
Password grant on the Native application `wely-ios-<env>`). Signing up (`screen_hint=signup`) and a forgotten password open Auth0's Universal Login,
with the authorization code flow and PKCE; Auth0 has no reset URL, its login page carries the
« forgot password » link. Every request sends `audience=wely-api-<env>`, without which Auth0 hands
out an opaque token. Signing out revokes the refresh token (`/oauth/revoke`).

The Native application needs:

| Setting | Value |
| --- | --- |
| Allowed Callback URLs | `wely://oauth-callback` |
| Allowed Logout URLs | `wely://oauth-callback` (unused today: the web sessions are ephemeral) |
| Grant types | Authorization Code, Refresh Token, Password |
| Refresh token rotation | on (the app shares one refresh request between callers) |
| Token endpoint authentication | None (public client) |

**Demo mode** — enable the `-WelyDemo` argument in *Product › Scheme › Edit Scheme › Run ›
Arguments* (Debug only): signed in against an in-memory gateway (`DemoTransport`) with sample
data, no backend needed. Debug builds also take `-WelyTab feed|messages|social|profile` and
`-WelyOpen /event/<id>` (any wely-web path) to start on a given screen.

From the command line:

```sh
xcodebuild test -project Wely.xcodeproj -scheme Wely -destination 'platform=iOS Simulator,name=iPhone 17'
```

## Environments

URLs are build settings of the `Wely` target (`WELY_GATEWAY_URL`, `WELY_WEB_URL`, and
`WELY_AUTH_*` for Auth0), read at runtime from `Config/Wely-Info.plist`. In the simulator the
gateway and web point at `localhost`, which it shares with the Mac; on a real iPhone
(`sdk=iphoneos*`), which cannot reach the Mac's `localhost`, at the dev infra (`dev-web.welylabs.app`).
Auth0 has no local counterpart: both sign in against the dev tenant.

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
| `Wely/Core/Auth` | Auth0 sign-in (password grant; PKCE for sign-up), tokens in the Keychain, refresh |
| `Wely/DesignSystem` | wely-web's look: colours, Outfit, buttons, cards, the tab bar's pieces |
| `Wely/Core/API` | gateway client (JSON, multipart, business error codes), lenient decoding |
| `Wely/Core/Realtime` | RSocket over WebSocket (chat, call events), server-sent events (notifications, polls) |
| `Wely/Core/Calls` | audio and video calls: one WebRTC connection to Cloudflare's relay through wely-chat, simulcast camera, ringing |
| `Wely/Core/Push` | notification permission, APNs token registration, local notifications for live arrivals |
| `Wely/Core/Backend` | `DemoTransport`, the in-memory gateway of the demo mode |
| `Wely/Models` | the wire types, as wely-web's models |
| `Wely/Services` | one struct per backend service, same routes as wely-web |
| `Wely/Features` | calendar, explore (feed + map), events (detail, form, poll, expenses), social (friends, people), communities, chat, notifications, profile, preferences |
| `WelyTests` | Swift Testing unit tests |

## Calls

Calls use Google's WebRTC build, as a Swift package ([stasel/WebRTC](https://github.com/stasel/WebRTC)),
and the same `chat-service/calls` steps as wely-web, so a phone and a browser can call each other.
They ring while the app runs; ringing a closed app needs PushKit and CallKit, so a paid team.

## Push notifications

A free personal team cannot sign the APNs entitlement. Without it, the app shows a system
notification for what arrives on the live stream while it runs or has just gone to the background.
With a paid team, set `CODE_SIGN_ENTITLEMENTS = Config/Wely.entitlements` in
`Signing.local.xcconfig`: the app then registers its APNs token with wely-notifications, which
pushes to it once its APNs key is configured.
