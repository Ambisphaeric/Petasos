# Signing Petasos

Petasos ships as a self-signed `.app`. This gets us the two things we need from code signing without paying for an Apple Developer Program membership:

1. **Stable keychain ACL.** macOS keys keychain ACLs to the binary's designated requirement. An unsigned (or ad-hoc-signed) binary changes identity on every rebuild, so "Always Allow" never sticks and users get re-prompted constantly. A stable self-signed identity fixes that.
2. **Same `.app` artifact ships to GitHub Releases.** Same signing, same upgrade behavior for downloaders.

The trade-off vs. a real Developer ID is Gatekeeper: on first launch downloaders must right-click → Open (one time) instead of just double-clicking. Documented in the README.

## One-time setup (do this once per machine that signs)

### 1. Create a self-signed code signing certificate

1. Open **Keychain Access** (`/System/Applications/Utilities/Keychain Access.app`).
2. Menu: **Keychain Access → Certificate Assistant → Create a Certificate…**
3. Fill in:
   - **Name**: `Petasos Dev` (this is the identity name you'll pass to codesign)
   - **Identity Type**: `Self Signed Root`
   - **Certificate Type**: `Code Signing`
   - Leave "Let me override defaults" **unchecked**.
4. Click **Create**, then **Done**.

The cert is now in your **login** keychain. Trust it so macOS treats it as a valid code-signing identity:

```sh
security find-certificate -a -c "Petasos Dev" -p > /tmp/petasos-dev.pem
security add-trusted-cert -d -r trustRoot -k ~/Library/Keychains/login.keychain-db -p codeSign -p basic /tmp/petasos-dev.pem
```

Confirm:

```sh
security find-identity -p codesigning -v
```

You should see `1 valid identities found` with `"Petasos Dev"` listed.

### 2. Sign a local build

```sh
PETASOS_SIGN_IDENTITY="Petasos Dev" ./scripts/build-app.sh
```

That produces `build/Petasos.app` signed with your cert. On first launch macOS will ask once per keychain item to allow access; click **Always Allow**. After that, restarts are silent — and remain silent across rebuilds because the codesign identity is stable.

### 3. (Optional) Add the same cert to GitHub Actions

If you want CI release builds to use the *same* identity as your local builds — so a DMG downloaded from GitHub Releases is treated as "the same Petasos" by Keychain on your machine — export the cert and store it as a repo secret.

1. In Keychain Access, find the **certificate** named `Petasos Dev` (under "My Certificates" — make sure it has the disclosure triangle showing the private key beneath it).
2. Right-click → **Export "Petasos Dev"…** → format **Personal Information Exchange (.p12)** → save as `petasos-dev.p12`.
3. Choose an export password (you'll need it in a moment).
4. Base64-encode it:

   ```sh
   base64 -i petasos-dev.p12 | pbcopy
   ```

5. In GitHub: **Settings → Secrets and variables → Actions → New repository secret**. Add three secrets:
   - `PETASOS_CERT_P12` — paste the base64 string from step 4
   - `PETASOS_CERT_PASSWORD` — the export password from step 3
   - `PETASOS_SIGN_IDENTITY` — `Petasos Dev` (or whatever you named the cert)
6. Delete the local `petasos-dev.p12` file. Don't commit it.

### 4. Cut a release

```sh
git tag v0.3.0
git push origin v0.3.0
```

The `.github/workflows/release.yml` workflow runs on macos-14, imports the cert, builds the `.app`, packs the DMG, and uploads it to a new GitHub Release named `v0.3.0`.

## Upgrade story

Same self-signed identity = same designated requirement = same keychain ACL. Users upgrade by:

1. Downloading the new `Petasos-vX.Y.Z.dmg` from GitHub Releases.
2. Opening the DMG and dragging `Petasos.app` over the old one in `/Applications`.
3. Launching. No keychain re-prompt, no Gatekeeper re-prompt (since the cert is the same).

## Future: Apple Developer ID

When/if you join the Apple Developer Program ($99/yr), the migration is small:

- Replace the self-signed cert with a "Developer ID Application" cert.
- Add a `notarize` step to the workflow (`xcrun notarytool submit ... --wait`, then `xcrun stapler staple build/Petasos.app`).
- Downloaders stop seeing the "unidentified developer" warning.

No changes needed to `scripts/build-app.sh` itself — just point `PETASOS_SIGN_IDENTITY` at the new identity.
