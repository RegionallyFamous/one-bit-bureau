from __future__ import annotations

import json
import unittest
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]


class PluginSourceContractTest(unittest.TestCase):
    def test_every_qml_helper_runs_behind_the_bounded_guardian(self) -> None:
        qml_sources = {
            path.relative_to(ROOT).as_posix(): path.read_text(encoding="utf-8")
            for path in (ROOT / "components").rglob("*.qml")
        }
        runtime = "\n".join(qml_sources.values())
        self.assertNotIn("Quickshell.execDetached", runtime)

        expected_boundaries = {
            "components/active-window/BarWidget.qml": (
                '"python3", root.runHelperPath, "800", "150", "4096", "1024", "--"',
                '"python3", root.runHelperPath, "2000", "200", "0", "4096", "--"',
            ),
            "components/dock/ApplicationIdentityController.qml": (
                '"python3", root.runHelperPath, "3500", "250", "131072", "8192", "--"',
                '"python3", root.runHelperPath, "1800", "200", "65536", "8192", "--"',
            ),
            "components/dock/IconPickerPanel.qml": (
                '"python3", root.runHelperPath, "12000", "250", "0", "4096", "--"',
            ),
            "components/dock/DockPanelBase.qml": (
                '"python3", root.runHelperPath, "12000", "250", "262144", "4096", "--"',
                '"python3", root.runHelperPath, "3000", "250", "0", "8192", "--"',
            ),
            "components/overview/Overview.qml": (
                '"python3", root.runHelperPath, "3500", "250", "0", "8192", "--"',
                '"python3", root.runHelperPath, "5000", "250", "4096", "8192", "--"',
            ),
        }
        for relative, boundaries in expected_boundaries.items():
            source = qml_sources[relative]
            for boundary in boundaries:
                self.assertIn(boundary, source, f"missing helper boundary: {relative}")

        desktop = qml_sources["components/desktop/Service.qml"]
        self.assertIn("function boundedCommand(timeoutMs, stdoutBytes, stderrBytes, command)", desktop)
        self.assertIn('"python3", root.runHelperPath,', desktop)
        self.assertIn('].concat(args)', desktop)
        for helper in (
            "listProc",
            "operationProc",
            "reserveProc",
            "statusProc",
            "cancelProc",
            "quickLookProc",
            "virtualActionProc",
            "renameProc",
            "inspectProc",
            "desktopActionProc",
            "positionsReaderProcess",
            "positionsWriterProcess",
        ):
            self.assertIn(f"id: {helper}", desktop)
        self.assertGreaterEqual(desktop.count("root.boundedCommand("), 13)

    def test_bounded_guardian_kills_and_reaps_the_complete_helper_tree(self) -> None:
        runner = (
            ROOT / "components/dock/scripts/one-bit-bureau-run"
        ).read_text(encoding="utf-8")
        for contract in (
            "STDOUT_BYTES STDERR_BYTES -- COMMAND",
            "PR_SET_CHILD_SUBREAPER",
            "PR_SET_PDEATHSIG",
            "os.setsid()",
            'os.write(ready_write, b"R")',
            'release != b"G"',
            "def descendants_of(",
            "def stop_and_reap(",
            "signal.SIGTERM",
            "signal.SIGKILL",
            "os.waitpid(-1, os.WNOHANG)",
            "helper stdout exceeded its hard cap",
            "helper stderr exceeded its hard cap",
            "helper cancelled after descendant cleanup",
        ):
            self.assertIn(contract, runner)
        self.assertLess(
            runner.index("if len(buffer) + len(chunk) > limit:"),
            runner.index("buffer.extend(chunk)"),
        )

    def test_shell_state_is_bounded_descriptor_relative_and_durable(self) -> None:
        helper = (
            ROOT / "components/dock/scripts/one-bit-bureau-state"
        ).read_text(encoding="utf-8")
        secure_io = (
            ROOT / "scripts/one_bit_bureau_secure_io.py"
        ).read_text(encoding="utf-8")
        self.assertIn("from one_bit_bureau_secure_io import", helper)
        for contract in (
            '"positions": ("desktop-icon-positions.json", 64 * 1024)',
            "MAX_STATE_OUTPUT = 256 * 1024",
            "MAX_SCREENS = 16",
            "MAX_POSITIONS_PER_SCREEN = 256",
            "set(raw_position) != {\"x\", \"y\"}",
            "math.isfinite(x)",
        ):
            self.assertIn(contract, helper)
        for contract in (
            "os.O_EXCL",
            "O_NOFOLLOW",
            "dir_fd=directory_fd",
            "follow_symlinks=False",
            "metadata.st_nlink != 1",
            "os.fsync(descriptor)",
            "os.replace(temporary, name, src_dir_fd=directory_fd, dst_dir_fd=directory_fd)",
            "os.fsync(directory_fd)",
        ):
            self.assertIn(contract, secure_io)

        desktop = (ROOT / "components/desktop/Service.qml").read_text(encoding="utf-8")
        dock = (ROOT / "components/dock/DockPanelBase.qml").read_text(encoding="utf-8")
        self.assertNotIn("positionsFile", desktop)
        self.assertNotIn("FileView.setText", desktop)
        self.assertIn('["python3", root.stateHelperPath, "read", "positions"]', desktop)
        self.assertIn('["python3", root.stateHelperPath, "write", "positions", content]', desktop)
        self.assertIn('"python3", root.stateHelperPath, "read", "dock"', dock)
        self.assertIn('"python3", root.stateHelperPath, "write", "pins", content', dock)
        self.assertIn('"python3", root.stateHelperPath, "write", "settings", content', dock)
        self.assertNotIn('"mv"', dock)
        self.assertNotIn("pendingPath", dock)

    def test_install_update_command_and_gtk_mutations_share_secure_io(self) -> None:
        secure_io = (
            ROOT / "scripts/one_bit_bureau_secure_io.py"
        ).read_text(encoding="utf-8")
        setup = (ROOT / "setup").read_text(encoding="utf-8")
        update = (ROOT / "update").read_text(encoding="utf-8")
        uninstall = (ROOT / "uninstall").read_text(encoding="utf-8")
        command = (ROOT / "one-bit-bureau").read_text(encoding="utf-8")
        doctor = (ROOT / "scripts/one-bit-bureau-doctor").read_text(encoding="utf-8")
        app_chrome = (
            ROOT / "scripts/one-bit-bureau-app-chrome.py"
        ).read_text(encoding="utf-8")

        for contract in (
            "INSTALL_STATE_LIMIT = 64 * 1024",
            "MAX_JSON_DEPTH = 6",
            "MAX_JSON_KEYS = 64",
            "TREE_MAX_BYTES = 1024 * 1024",
            "TREE_MAX_FILES = 32",
            "TREE_MAX_DIRECTORIES = 8",
            "TREE_MAX_DEPTH = 3",
            "os.O_EXCL",
            "nofollow_flag()",
            "metadata.st_uid != os.getuid()",
            "metadata.st_nlink != 1",
            "current_identity != prior_identity",
            "os.fsync(descriptor)",
            "os.fsync(directory_fd)",
        ):
            self.assertIn(contract, secure_io)

        self.assertIn('install-state write', setup)
        self.assertIn('command install --plugin-dir', setup)
        self.assertNotIn('STATE_FILE.tmp', setup)
        self.assertIn('state_snapshot=$(python3 "$SECURE_IO" install-state snapshot)', update)
        self.assertIn('command replace-if-owned', update)
        self.assertNotIn('COMMAND_TARGET.tmp', update)
        self.assertNotIn('STATE_FILE.tmp', update)
        self.assertIn('state_snapshot=$(python3 "$SECURE_IO" install-state snapshot)', uninstall)
        self.assertIn('command remove-if-owned', uninstall)
        self.assertIn('install-state delete', uninstall)
        self.assertIn('install-state read | jq', command)
        self.assertIn('install-state read', doctor)
        self.assertIn('import one_bit_bureau_secure_io as secure', app_chrome)
        self.assertNotIn('.rglob(', app_chrome)
        self.assertNotIn('.read_bytes(', app_chrome)
        self.assertNotIn('shutil.rmtree', app_chrome)

    def test_security_sensitive_desktop_actions_are_tracked_to_completion(self) -> None:
        desktop = (ROOT / "components/desktop/Service.qml").read_text(encoding="utf-8")
        self.assertIn("function queueDesktopAction(", desktop)
        self.assertIn("id: desktopActionProc", desktop)
        self.assertIn("onExited: function(exitCode) { root.finishDesktopAction(exitCode) }", desktop)
        for action in (
            'queueDesktopAction("open"',
            'queueDesktopAction("trust"',
            'queueDesktopAction("trust-open"',
            'queueDesktopAction("reveal"',
            'queueDesktopAction("new-folder"',
            'queueDesktopAction("new-shortcut"',
            'queueDesktopAction("pick-app"',
            'queueDesktopAction("pick-files"',
            'queueDesktopAction("open-folder"',
            'queueDesktopAction("wallpaper"',
        ):
            self.assertIn(action, desktop)
        self.assertIn('action.kind === "trust" || action.kind === "trust-open"', desktop)
        self.assertIn("if (exitCode === 0)", desktop)
        self.assertNotIn("Quickshell.execDetached", desktop)

    def test_experience_hosts_one_shared_inspector_and_routes_each_noun_kind(self) -> None:
        experience = (ROOT / "Experience.qml").read_text(encoding="utf-8")
        dock = (ROOT / "components/dock/DockPanelBase.qml").read_text(
            encoding="utf-8"
        )

        self.assertEqual(
            experience.count("OneBitBureauInspector.InspectorPanel"), 1
        )
        self.assertIn("function onInspectRequested(payload, screenName)", experience)
        self.assertIn("onInspectorRequested: function(context", experience)
        self.assertIn("onInspectRequested: function(payload, screenName)", experience)
        self.assertIn('if (kind === "desktop"', experience)
        self.assertIn('if (kind === "app")', experience)
        self.assertIn('if (kind === "window")', experience)
        self.assertIn("root.service.performInspectorAction(actionId, context)", experience)
        self.assertIn("dock.performInspectorAction(actionId, context)", experience)
        self.assertIn("overview.performInspectorAction(actionId, context)", experience)
        self.assertIn('kind: "app"', dock)
        self.assertNotIn('kind: "application"', dock)
        self.assertIn("facts: [", dock)
        self.assertIn("actions: [", dock)

    def test_one_bit_bureau_is_the_only_canonical_identity(self) -> None:
        manifest = json.loads((ROOT / "manifest.json").read_text(encoding="utf-8"))
        self.assertEqual(manifest["id"], "io.github.regionallyfamous.one-bit-bureau")
        self.assertEqual(manifest["name"], "One-Bit Bureau")

        setup = (ROOT / "setup").read_text(encoding="utf-8")
        command = (ROOT / "one-bit-bureau").read_text(encoding="utf-8")
        dock = (ROOT / "components/dock/DockPanelBase.qml").read_text(
            encoding="utf-8"
        )
        desktop = (ROOT / "components/desktop/Service.qml").read_text(
            encoding="utf-8"
        )
        state = (
            ROOT / "components/dock/scripts/one-bit-bureau-state"
        ).read_text(encoding="utf-8")
        overview = (ROOT / "components/overview/Overview.qml").read_text(
            encoding="utf-8"
        )

        self.assertIn(
            'ONE_BIT_BUREAU_CONFIG="$HOME/.config/omarchy/one-bit-bureau"', setup
        )
        self.assertIn("/.config/omarchy/one-bit-bureau/", dock)
        self.assertNotIn("/.config/omarchy/one-bit-bureau/", desktop)
        self.assertIn('".config/omarchy/one-bit-bureau"', state)
        self.assertIn("open_state_directory", state)
        self.assertIn("regionallyfamous.one-bit-bureau.dock", command)
        self.assertIn("regionallyfamous.one-bit-bureau.overview", command)
        self.assertIn("regionallyfamous.one-bit-bureau.dock", dock)
        self.assertIn("regionallyfamous.one-bit-bureau.overview", overview)

    def test_active_window_widget_keeps_the_desk_menu_without_a_window(self) -> None:
        source = (ROOT / "components/active-window/BarWidget.qml").read_text(
            encoding="utf-8"
        )
        self.assertIn(
            "readonly property bool hasActiveWindow: !!(waylandToplevel || hyprlandToplevel)",
            source,
        )
        self.assertIn("visible: true", source)
        self.assertIn(
            'readonly property string barLabel: hasActiveWindow && displayLabel',
            source,
        )
        self.assertIn('? "Desk · " + displayLabel : "Desk"', source)
        self.assertIn('Accessible.name: "Open Desk menu"', source)

    def test_reduced_motion_is_an_inline_live_plugin_setting(self) -> None:
        manifest = json.loads((ROOT / "manifest.json").read_text(encoding="utf-8"))
        self.assertIs(manifest["barWidget"]["defaults"]["reducedMotion"], False)
        setting = next(
            item
            for item in manifest["barWidget"]["schema"]
            if item["key"] == "reducedMotion"
        )
        self.assertEqual(setting["type"], "boolean")
        self.assertEqual(setting["label"], "Reduce One-Bit Bureau motion")
        self.assertIs(setting["defaultValue"], False)

        overview = (ROOT / "components/overview/Overview.qml").read_text(
            encoding="utf-8"
        )
        active_window = (
            ROOT / "components/active-window/BarWidget.qml"
        ).read_text(encoding="utf-8")
        settings = (ROOT / "components/overview/SettingsView.qml").read_text(
            encoding="utf-8"
        )

        self.assertIn(
            "root.pluginEntry && root.pluginEntry.reducedMotion === true", overview
        )
        self.assertIn("if (root.reducedMotion) {", overview)
        self.assertIn("root.motionProgress = next;", overview)
        self.assertIn("function getReducedMotion(): string", overview)
        self.assertIn(
            'readonly property bool reducedMotion: setting("reducedMotion", false) === true',
            active_window,
        )
        self.assertIn("enabled: !root.reducedMotion", active_window)
        self.assertIn(
            "duration: settingsView.controller.reducedMotion ? 0 : 100", settings
        )
        self.assertIn("enabled: !settingsView.controller.reducedMotion", settings)

    def test_overview_and_active_application_expose_accessible_actions(self) -> None:
        overview = (ROOT / "components/overview/Overview.qml").read_text(
            encoding="utf-8"
        )
        card = (ROOT / "components/overview/WindowCard.qml").read_text(
            encoding="utf-8"
        )
        settings = (ROOT / "components/overview/SettingsView.qml").read_text(
            encoding="utf-8"
        )
        active_window = (
            ROOT / "components/active-window/BarWidget.qml"
        ).read_text(encoding="utf-8")

        self.assertIn('Accessible.name: "Open window overview settings"', overview)
        self.assertIn("Accessible.role: Accessible.Button", card)
        self.assertIn("Accessible.selected: card.selected", card)
        self.assertIn(
            "Accessible.onPressAction: card.controller.activate(card.modelData)", card
        )
        self.assertIn("Accessible.role: Accessible.Slider", settings)
        self.assertIn("Accessible.role: Accessible.CheckBox", settings)
        self.assertIn("Accessible.onToggleAction", settings)
        self.assertIn("Accessible.role: Accessible.Button", active_window)
        self.assertIn("Accessible.onPressAction", active_window)

    def test_runtime_does_not_take_over_global_alt_tab(self) -> None:
        source = (ROOT / "components/dock/DockPanelBase.qml").read_text(
            encoding="utf-8"
        )
        self.assertNotIn('hl.unbind(\\"ALT + TAB', source)
        self.assertNotIn('o.bind(\\"ALT + TAB', source)
        self.assertNotIn("altTabBindRetry", source)

    def test_dock_surfaces_share_one_persisted_output(self) -> None:
        source = (ROOT / "components/dock/DockPanelBase.qml").read_text(
            encoding="utf-8"
        )
        self.assertNotIn("screen: Quickshell.screens", source)
        self.assertGreaterEqual(source.count("screen: root.dockScreen"), 8)
        self.assertIn("screenName: root.preferredScreenName", source)
        self.assertIn("function setScreen(name: string): bool", source)

    def test_theme_keeps_every_application_paper_fully_opaque(self) -> None:
        source = (ROOT / "themes/one-bit-bureau/hyprland.lua").read_text(
            encoding="utf-8"
        )
        self.assertIn("active_opacity = 1.0", source)
        self.assertIn("inactive_opacity = 1.0", source)
        self.assertIn('o.window(".*", { opacity = "1.0 1.0" })', source)

    def test_dock_settings_reject_stale_startup_snapshots(self) -> None:
        source = (ROOT / "components/dock/DockPanelBase.qml").read_text(
            encoding="utf-8"
        )
        self.assertIn("property int settingsMutationRevision: 0", source)
        self.assertIn("property bool settingsWritePending: false", source)
        self.assertIn(
            "Number(settingsRevision) === root.settingsMutationRevision", source
        )
        self.assertIn(
            "stateReaderProcess.running || root.settingsWritePending", source
        )
        self.assertIn(
            "root.applyStateSnapshot(text, root.stateReaderSettingsRevision)", source
        )

    def test_desktop_drop_routes_copied_and_moved_launchers_through_safe_helper(self) -> None:
        source = (ROOT / "components/desktop/bin/desktop-index").read_text(
            encoding="utf-8"
        )
        self.assertIn('mode in ("copy", "move") and source.suffix.lower() == ".desktop"', source)
        self.assertIn('if mode == "move":\n            source.unlink()', source)
        self.assertIn("if result.returncode != 0:", source)

    def test_keyboard_surfaces_leave_super_chords_to_omarchy(self) -> None:
        paths = [
            "components/desktop/Service.qml",
            "components/overview/Overview.qml",
            "components/dock/AltTabPanel.qml",
        ]
        for relative in paths:
            source = (ROOT / relative).read_text(encoding="utf-8")
            guard = "event.modifiers & Qt.MetaModifier"
            self.assertIn(guard, source, relative)
            guard_index = source.index(guard)
            self.assertNotEqual(
                source.find("event.key === Qt.Key_Left", guard_index), -1, relative
            )

        overview = (ROOT / "components/overview/Overview.qml").read_text(
            encoding="utf-8"
        )
        settings_handler = overview.index("function handleSettingsNavigation(event)")
        settings_guard = overview.index(
            "event.modifiers & Qt.MetaModifier", settings_handler
        )
        settings_arrows = overview.index("var isStep =", settings_handler)
        self.assertLess(settings_guard, settings_arrows)

    def test_runtime_does_not_claim_omarchy_navigation_bindings(self) -> None:
        runtime = "\n".join(
            path.read_text(encoding="utf-8")
            for path in (ROOT / "components").rglob("*")
            if path.is_file() and path.suffix in {".qml", ".js", ".lua", ".sh"}
        )
        self.assertNotIn("hl.unbind", runtime)
        self.assertNotIn("o.bind", runtime)
        self.assertNotIn("bindings.lua", runtime)
        self.assertNotIn("input.lua", runtime)

    def test_acceptance_workspace_moves_keep_the_full_live_identity_contract(self) -> None:
        source = (ROOT / "test/omarchy-acceptance.sh").read_text(encoding="utf-8")
        helper_call = 'bash "$PLUGIN_DIR/components/overview/move-window-to-workspace"'
        self.assertEqual(source.count(helper_call), 1)
        self.assertIn(
            'ledger_move_record=$(move_window_with_live_identity "${ledger_addresses[1]}" 2)',
            source,
        )

    def test_acceptance_covers_every_safe_native_theme_override_scene(self) -> None:
        source = (ROOT / "test/omarchy-acceptance.sh").read_text(encoding="utf-8")
        for contract in (
            "the Bureau bar reflows vertically",
            "switching away restores the prior Hyprland geometry exactly",
            "tiled, floating, fullscreen, active, and inactive window geometry",
            "the themed Apps search stays open while typing",
            "the One-Bit Bureau wallpaper picker opens",
            "the One-Bit Bureau OSD paints its progress",
            "the One-Bit Bureau dock tooltip paints",
            "the One-Bit Bureau lock preview paints its idle prompt",
            "the One-Bit Bureau polkit prompt asks for authentication",
        ):
            self.assertIn(contract, source)
        self.assertIn("failed authentication mutates PAM state", source)
        self.assertIn(
            'move_window_with_live_identity "$release_address" 2 >/dev/null',
            source,
        )

    def test_public_lifecycle_uses_exact_plugin_and_theme_sources(self) -> None:
        setup = (ROOT / "setup").read_text(encoding="utf-8")
        update = (ROOT / "update").read_text(encoding="utf-8")
        uninstall = (ROOT / "uninstall").read_text(encoding="utf-8")
        command = (ROOT / "one-bit-bureau").read_text(encoding="utf-8")

        self.assertIn('EXPECTED_REPO_URL="https://github.com/RegionallyFamous/one-bit-bureau.git"', setup)
        self.assertIn('omarchy theme source inspect "$repo_url" --json', setup)
        self.assertIn('omarchy theme source install "$THEME_SOURCE_ID" "$THEME_NAME" --json', setup)
        self.assertIn('THEME_INSTALL_MODE="plugin-link"', setup)
        self.assertIn('ln -s "$source_theme" "$THEME_TARGET"', setup)
        self.assertIn('[[ ! -e $THEME_TARGET && ! -L $THEME_TARGET ]]', setup)
        self.assertIn("for command in inspect install update detach; do", setup)
        self.assertIn(
            "[[ -x $OMARCHY_PATH/bin/omarchy-theme-source-$command ]]", setup
        )
        self.assertNotIn('omarchy theme install "$repo_url"', setup)
        self.assertLess(
            setup.index('if (( THEME_OWNED )); then'),
            setup.index('if (( PLUGIN_OWNED )); then'),
        )
        self.assertIn('omarchy "${arguments[@]}"', update)
        self.assertIn('exec bash "$PLUGIN_DIR/update" --reconcile', update)
        self.assertIn('omarchy theme source update "$source_id" --json', update)
        self.assertIn('[[ $theme_install_mode == "source" ]]', update)
        self.assertIn('[[ $theme_commit == "$plugin_commit" ]]', update)
        self.assertIn('actual_plugin_url=$(git -C "$PLUGIN_DIR" config --get remote.origin.url', update)
        self.assertNotIn("omarchy theme update", update)
        self.assertIn('omarchy theme source detach "$THEME_SOURCE_ID" "$THEME_NAME" --json', uninstall)
        self.assertIn('[[ $THEME_INSTALL_MODE == "plugin-link" ]]', uninstall)
        self.assertLess(
            uninstall.index("preflight_owned_installation || exit 1"),
            uninstall.index('omarchy theme set "$PREVIOUS_THEME"'),
        )
        self.assertIn('PLUGIN_ID="io.github.regionallyfamous.one-bit-bureau"', command)


if __name__ == "__main__":
    unittest.main()
