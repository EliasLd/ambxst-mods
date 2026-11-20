# Discord voice

Adds a **Discord voice tab** to the Ambxst dashboard. The tab shows who is in
your Vesktop voice channel and controls your voice session:

- Participants as compact tiles in a responsive grid (avatar with speaking
  glow, display name, mic / deafen state badge); you appear in the same
  style, without a volume bar (a local volume does not apply to yourself).
  The grid scrolls and the self controls stay docked when many people are
  in the channel.
- Per-user local volume, the same "user volume" Discord's own slider edits,
  and a local mute button per participant.
- Self controls: mic mute, deafen, camera and leave voice channel, docked to
  the bottom left of the tab.

It works with **Vesktop only** (the Vesktop fork with Vencord support in the
Ambxst ecosystem). Two cooperating pieces make it work:

1. This mod, which composes into Ambxst and draws the tab. It hosts a bridge
   socket that the plugin connects to; released Vesktop has no control socket
   a shell could write to, so every action flows through the plugin.
2. A companion **Vencord userplugin** (`AmbxstDiscord`), running inside
   Vesktop, which reads Discord's internal voice state, executes the actions
   (self mute, deafen, camera, leave, per-user volume) and reports state back
   to the mod over the bridge socket.

Nothing else in the shell changes. The tab degrades gracefully: without
Vesktop it shows an install hint; with Vesktop but without the plugin it
shows a companion-missing hint; without being in a voice channel it shows a
quiet explanation.

## Install

Two things, in this order: the mod adds the tab, the companion plugin feeds
it.

### 1. The mod

Either with the mod manager CLI:

```sh
ambxst mods install https://github.com/EliasLd/ambxst-mods/tree/main/packages/discord-voice
ambxst mods enable eliasld.discord-voice
ambxst mods rebuild
```

or from the GUI: Settings -> Mods -> paste the same URL, install, enable the
toggle, rebuild. Restart Ambxst afterwards.

### 2. The companion plugin

Run the installer only while Vesktop is completely closed - Vesktop rewrites
its state.json from memory on exit, and would undo the change (the script
refuses to run while Vesktop is up and tells you so).

```sh
curl -fsSL https://raw.githubusercontent.com/EliasLd/ambxst-mods/main/scripts/discord-install.sh | sh
```

The script downloads the companion Vencord build (checksums verified against
SHA256SUMS), extracts the 4 plugin files to
`~/.local/share/ambxst-discord/vencord/`, and points Vesktop's
`vencordDir` override in `~/.config/vesktop/state.json` at that directory. It
never kills Vesktop and never touches anything beyond those two locations.
Flatpak Vesktop is not supported (different state file location).

Flags the script understands: `--latest` (install the rolling build instead
of the one pinned to the repo ref), `--dir <path>` (custom data directory),
`--build` (build the plugin locally first, needs git + node + pnpm), and
`--uninstall`.

Then close Vesktop fully, relaunch it, and restart Ambxst.

One step is manual: once, after the first install, open Vesktop's settings
(only after it was launched with the override in place), go to
**Settings -> Plugins** and enable `AmbxstDiscord` (it ships disabled by
default). It stays enabled across Vesktop updates.

### First-run checklist

1. Install the mod, enable it, rebuild, restart Ambxst.
2. Run the installer, close Vesktop fully, relaunch Vesktop.
3. Enable `AmbxstDiscord` in Vesktop: Settings -> Plugins.
4. Optionally add the keybind in your hyprland config:

```sh
bind = $mainMod, V, exec, ambxst run discord
```

5. Open the dashboard (or press the bind): the Companion chip lit means the
   stack is up. Join a voice channel in Vesktop: participants appear.

The keybind accepts both `ambxst run discord` and
`ambxst run dashboard-discord`.

Two more commands exist for global mute keys, so you never have to focus
the Discord window:

```sh
bind = $mainMod, M, exec, ambxst run discord-mute
bind = $mainMod, N, exec, ambxst run discord-deafen
```

`discord-mute` toggles your microphone, `discord-deafen` toggles Discord's
deafen (mutes all incoming audio). Both are plain toggles, work like
Discord's own global mute actions, and do nothing quietly while Vesktop is
closed. Pick your own key combos - the ones above are examples.

## Update, uninstall, recovery

- **Update:** re-run the same one-liner. It replaces the plugin files and is
  idempotent.
- **Uninstall:** `sh <script> --uninstall` removes the `vencordDir` override
  and `~/.local/share/ambxst-discord`; the next Vesktop start re-downloads
  its official Vencord build. Remove the mod with the manager if you want the
  tab gone too.
- **After Vesktop's "RepairInstall" or a Vencord in-app update:** Vesktop
  overwrites the custom directory and the plugin disappears - the tab will
  show the companion-missing state. Recovery: re-run the one-liner.
- **Manual alternative (no curl | sh):** download
  `discord-vencord-files.zip` from the
  [discord-latest release](https://github.com/EliasLd/ambxst-mods/releases/tag/discord-latest),
  verify it against `SHA256SUMS`, extract the 4 files to
  `~/.local/share/ambxst-discord/vencord/`, and add
  `"vencordDir": "/home/you/.local/share/ambxst-discord/vencord"` as a key to
  `~/.config/Vesktop/state.json`. Relaunch Vesktop.

## Troubleshooting

| Symptom | Cause / fix |
|---|---|
| Tab missing entirely | mod disabled, or `ambxst mods rebuild` not run |
| "Companion" chip dark | Vesktop not running, or the plugin missing or disabled: run the installer (with Vesktop closed), and check that `AmbxstDiscord` is enabled in Vesktop's Settings -> Plugins |
| Self buttons do nothing | the plugin is not connected: they only exist while the plugin is up and you are in voice |
| Plugin vanished after a Vesktop repair | expected overwrite; re-run the installer |
| Volume slider not visible in a row | the plugin could not reach Discord's internal volume module; the rest still works |

## Local builds of the plugin

For development, `scripts/discord-plugin-build.sh` in the repository root
builds the companion bundle from the ref pinned in `vesktop-plugin/VENCORD_REF`
(see `vesktop-plugin/README.md`). The installer's `--build` flag runs it and
installs the result instead of a release download.

## Compatibility

Tested against Ambxst 1.3.15 (commit
5d71e924212ce2c0203e7448e0b1e3db52608640), 1.4.1 (commit
5db90ba000713b5cb991a2abce1b766ab47fbd2b) and the current tree (commit
5bb2b95d6d55de6ef40fa64720dfec1209fe8fd3). The patch adds a dashboard tab,
the keybind commands and a `discord` icon to `Icons.qml`; see
`patches/discord-voice.patch`. The companion side needs a native Vesktop
install with Vencord support; PluginNative must reach Vesktop's main process
(stock Vesktop behavior).

The companion Vencord build is compiled from Vencord at the ref pinned in
`vesktop-plugin/VENCORD_REF`, with this repository's plugin source injected as
a userplugin. Vencord itself is AGPL-3.0; the modified source and the pin stay
public in this repository.
