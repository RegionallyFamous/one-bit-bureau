# Changelog

## 0.6.0 — One clean Paper Jam

- Renamed the unpublished internal identity to `io.github.regionallyfamous.paper-jam-84`, namespaced all runtime targets and user state, and added a non-destructive migration from Alumina-era local files.
- Added twelve original offline ImageGen app-role icons with automatic Linux app association, manual pack selection, native-icon opt-out, and migration-compatible local mappings.
- Replaced direct shell-side state loading with a no-follow, size-capped, record-capped reader; removed external icon search and fallback screenshot/ImageMagick jobs so background work has a small, deterministic lifetime.
- Added original plugin, About, screensaver, and unlock branding plus a generated 1920×1080 Plymouth preview.
- Bundled Monaspace Krypton NF 1.400 and Departure Mono 1.500 with upstream licenses and checksums; fonts install without silently changing the selected system font.
- Added a Git-native `paper-jam` coordinator, source-owned theme lifecycle, commit-aligned updates, and ownership-aware removal.
- Preserved every Omarchy `Super` navigation chord by passing Meta-modified keys through focused desktop, overview, and switcher surfaces.

## 0.5.1 — Picture means icon

- Replaced literal desktop photo thumbnails with the dedicated ImageGen-authored one-bit picture-file icon in both runtime and the static design proof.

## 0.5.0 — Paper Jam ’84 (unpublished development)

- Reframed the vintage edition as Paper Jam ’84 while temporarily preserving the Alumina development namespace.
- Replaced the desktop object family and wallpaper with original ImageGen-authored bitmap artwork, added a real-color photo path, and added an original one-bit image fallback.
- Made local installation atomic, collision-safe, and rollback-capable; added an ownership record so uninstall removes only this release and restores only settings it still owns.
- Kept copied launchers untrusted unless they originate in canonical application directories, made launcher generation keyfile-safe, and made Trash operate on symlinks rather than their targets.
- Removed runtime global Alt+Tab takeover, fixed preview batch commits, made focus cursor restoration trap-safe, and persisted one-output ownership across every dock surface.
- Added regression coverage for desktop trust/path policy, dock lifecycle and app matching, setup/uninstall recovery, ownership tampering, and user-modified settings.
