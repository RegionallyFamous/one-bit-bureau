# Changelog

## 0.5.1 — Picture means icon

- Replaced literal desktop photo thumbnails with the dedicated ImageGen-authored one-bit picture-file icon in both runtime and the static design proof.

## 0.5.0 — Paper Jam ’84

- Reframed the vintage edition as Paper Jam ’84 while preserving the permanent plugin ID and existing user-state filenames.
- Replaced the desktop object family and wallpaper with original ImageGen-authored bitmap artwork, added a real-color photo path, and added an original one-bit image fallback.
- Made local installation atomic, collision-safe, and rollback-capable; added an ownership record so uninstall removes only this release and restores only settings it still owns.
- Kept copied launchers untrusted unless they originate in canonical application directories, made launcher generation keyfile-safe, and made Trash operate on symlinks rather than their targets.
- Removed runtime global Alt+Tab takeover, fixed preview batch commits, made focus cursor restoration trap-safe, and persisted one-output ownership across every dock surface.
- Added regression coverage for desktop trust/path policy, dock lifecycle and app matching, setup/uninstall recovery, ownership tampering, and user-modified settings.
