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

- Release APKs in this repo may be signed with a **publicly committed keystore** for CI sideload convenience. Treat that key as **untrusted for high-security identity**. Forks distributing widely should use their own private signing keys.  
- VibeTube talks to third-party services (YouTube InnerTube, SponsorBlock, Return YouTube Dislike, GitHub). Those services have their own security and privacy policies.
