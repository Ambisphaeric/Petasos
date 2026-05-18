# Petasos

Accessibility-first macOS menu bar companion for [hermes-agent](https://hermes-agent.nousresearch.com/).

Built for deaf and blind users, useful for everyone. Low-latency on-device STT (Parakeet 110m on MLX) and TTS (Kokoro 82m on MLX), pluggable transparent overlays, global hotkeys, and a native menu bar UI that talks to any hermes-agent server over its OpenAI-compatible HTTP API.

## Status

**P0–P2 are complete.** Menu bar shell, onboarding, chat streaming, and the full on-device voice loop (STT + TTS) are shipped. Work is now focused on overlays and polish.

| Phase | Status | Scope |
|---|---|---|
| **P0 — Skeleton & onboarding** | ✅ done | menu bar + onboarding wizard + capability probe |
| **P1 — Chat core + streaming** | ✅ done | SSE token streaming + popover chat |
| **P2 — Voice loop** | ✅ done | Parakeet STT + Kokoro TTS, PTT + always-listening + wake word |
| **P3 — Overlay engine + 3 modes** | in progress | pluggable overlay framework |
| **P4 — Primitives & polish** | not started | shorthand expander, screenshot vision, settings panel |

## Install

**Recommended:** grab the latest `Petasos-vX.Y.Z.dmg` from the [Releases page](https://github.com/Ambisphaeric/Petasos/releases).

1. Open the DMG.
2. Drag `Petasos.app` to `/Applications`.
3. **First launch only:** right-click `Petasos.app` → **Open** → confirm. (The app is signed with a self-signed certificate, so Gatekeeper doesn't recognize it as "from an identified developer" yet — once Petasos joins the Apple Developer Program this step goes away.)
4. After that, launch normally from Spotlight or the menu bar.

**Upgrading**: open the new DMG, drag `Petasos.app` over the old one in `/Applications`. Same signing identity → keychain ACL persists, no re-prompt.

## Build from source

Requires macOS 14+, Xcode 16+ (Swift 6.0).

### Dev iteration

Open `Package.swift` in Xcode and hit Run. Xcode runs the Metal shader compiler so MLX features (Parakeet STT, Kokoro TTS) work.

`swift run` also works for fast iteration on non-MLX code, but it cannot compile Metal shaders — anything touching MLX will crash with "Failed to load the default metallib." Use Xcode (or the build script below) when exercising MLX paths.

### Building a signed `.app`

```sh
PETASOS_SIGN_IDENTITY="Petasos Dev" ./scripts/build-app.sh   # signs locally
./scripts/package-dmg.sh                                      # → build/Petasos-X.Y.Z.dmg
```

One-time cert setup is in [`docs/SIGNING.md`](docs/SIGNING.md). Without `PETASOS_SIGN_IDENTITY`, the script falls back to ad-hoc signing — fine for testing, but keychain ACLs won't persist across rebuilds so you'll see repeated prompts.

### Cutting a release

```sh
git tag v0.3.0
git push origin v0.3.0
```

`.github/workflows/release.yml` runs on tag push, builds the signed `.app`, packs the DMG, and attaches it to a new GitHub Release. See `docs/SIGNING.md` for the one-time GitHub secrets setup.

### First-run flow

1. Menu bar icon appears (no dock icon — `setActivationPolicy(.accessory)`).
2. Onboarding popover opens automatically.
3. Probes `127.0.0.1:8642` for a local hermes instance; otherwise asks for a URL.
4. Takes a bearer token, stores it in Keychain.
5. Probes `/v1/capabilities` and `/v1/models` to confirm.

## Architecture

```
Sources/
├── PetasosCore/        models, protocols, system flag observation
├── PetasosHermes/      HTTP client, SSE, endpoint clients, autodiscover
├── PetasosUI/          onboarding flow, popover, settings (SwiftUI)
└── PetasosApp/         @main, AppDelegate, menu bar, keychain
```

See `MEMORY.md` (not in repo — Claude's project memory) for fuller architectural context.
