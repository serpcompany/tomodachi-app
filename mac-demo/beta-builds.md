# Mac beta builds

How to build, sign, notarize and check a Mac beta for testers, and the owner's own copy. Running and
rebuilding the app for development is in [README.md](README.md); what testers are told is in
[docs/beta-testing.md](../docs/beta-testing.md).

```bash
mac-demo/scripts/release-beta.sh                 # archive, sign (Developer ID), notarize, staple, zip
mac-demo/scripts/release-beta.sh --no-notarize   # archive and sign only
mac-demo/scripts/release-beta.sh --owner         # the owner's copy in build/owner (run.sh opens it)
```

- **Team:** `DEVELOPMENT_TEAM` in `NotchBuddy/project.yml` (`847HR8U8D9` with bundle ID `com.zenbujapanese.tomo`
  since October 10, 2026; betas 0.0.2 and earlier were `com.zenbujapanese.tomodachi`, on `W3GXL2NQQP` from
  October 6). The export makes the Developer ID profile with iCloud and push
  (`scripts/ExportOptions.plist`). You need a Developer ID Application certificate for that team, and Xcode
  signed in to it (Xcode → Settings → Accounts).
- **Notarizing** uses that same Xcode account, as Organizer's "Distribute App" does, so there are no notary
  credentials to store. The script uploads the archive, waits for Apple (usually a few minutes, at most 30),
  then staples the ticket.
- **Output:** `build/release/Tomodachi-<version>-beta.zip` (universal, macOS 15+; release-please
  bumps the version: `CFBundleShortVersionString`, `NotchBuddy/project.yml`). Its archive, with the
  dSYMs, stays in `build/archives/Tomodachi-<version>-<YYMMDD-HHMM>.xcarchive`, never deleted.
- **What the script checks:** the bundle ID (`com.zenbujapanese.tomo`), your Developer ID team, the
  hardened runtime, iCloud on CloudKit's Production environment with production push, and that no
  Coucou sounds are bundled; again after notarizing, with the stapled ticket and Gatekeeper.
- **What to send testers:** the zip, plus [docs/beta-testing.md](../docs/beta-testing.md).
