# Signing-key incident migration

The Android key used by historical VibeTube releases was committed in old
repository revisions. Removing it from `main` does not revoke copies. APKs
signed by that key therefore cannot establish publisher authenticity.

## What the CI fingerprint check does

`VIBETUBE_EXPECTED_CERT_SHA256` makes CI fail if its decoded keystore is not the
explicitly approved certificate. This catches accidental or workflow-level key
substitution. It **does not** make the exposed historical key private again.

Obtain a fingerprint without printing key material:

```bash
keytool -list -v -keystore /secure/path/vibetube-release.jks \
  | sed -n 's/.*SHA256: //p' | head -n1
```

Store the value as a protected GitHub Actions secret. Protect release
environments, require reviewer approval, and restrict who can create `v*` tags.

## Safe migration choices

### New sideload distribution (recommended)

1. Generate a new key on an offline/trusted machine.
2. Change `applicationId` to a new, never-published package ID.
3. Update App Links/custom scheme declarations and documentation as needed.
4. Publish the new APK from an explicitly announced release and fingerprint.
5. Tell users this is a one-time side-by-side install/migration; the compromised
   package must not be trusted as an update channel.
6. Archive the old package and stop producing releases signed by the old key.

A new key with the old package ID is not a normal sideload update and will cause
`INSTALL_FAILED_UPDATE_INCOMPATIBLE` unless a platform-managed rotation path is
available.

### Managed-store distribution

If the app is enrolled in Google Play App Signing, follow Play Console's key
upgrade/compromise process. Confirm Android-version compatibility and rotation
semantics with the store before shipping. Do not assume a locally generated new
key can update old sideloaded installs.

## Required owner decision

The repository cannot choose between package continuity and a trustworthy new
identity automatically. No workflow should label the historical certificate as
secure. Record the selected migration plan in a security advisory and publish
the new certificate fingerprint through an independent trusted channel.
