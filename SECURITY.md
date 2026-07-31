# Security Policy

## Supported versions

| Version | Supported          |
| ------- | ------------------ |
| Latest release on GitHub | ✅ |
| Older APKs | ⚠️ Best-effort only |

Please upgrade to the [latest release](https://github.com/Code-Stride/VibeTube/releases/latest) when possible. The app can also prompt for updates via GitHub Releases.

## Reporting a vulnerability

**Do not** file a public GitHub issue for security-sensitive reports.

Instead:

1. Use GitHub **Private vulnerability reporting** on this repository (Security tab), if enabled  
2. Or contact the maintainers via the GitHub organization **Code-Stride** / repo owner

Please include:

- Description and impact  
- Steps to reproduce  
- Affected version / commit  
- Any suggested fix  

We aim to acknowledge reports within a reasonable time and will coordinate disclosure after a fix is available when appropriate.

## Non-security bugs

Use [GitHub Issues](https://github.com/Code-Stride/VibeTube/issues) for crashes, UI bugs, and feature requests.

## Notes

- **Signing key**: the release keystore is no longer stored in this repository. CI decodes it from the `VIBETUBE_KEYSTORE_BASE64` secret at build time and deletes it before uploading artifacts. Passwords come from repository secrets and are never written to the workflow file.
- **Historical exposure**: the keystore and its password were committed to this repository between v1.2.0 and v1.5.1. Anyone who cloned the repo in that window still holds a copy, so the current key cannot be considered private. It is retained only so existing installs can update in place; a signature match on releases up to that point is **not** proof of authenticity. Key rotation is planned, and will require a one-time uninstall/reinstall.
- Forks distributing widely should generate and use their own private signing key.  
- VibeTube talks to third-party services (YouTube InnerTube, SponsorBlock, Return YouTube Dislike, GitHub). Those services have their own security and privacy policies.
