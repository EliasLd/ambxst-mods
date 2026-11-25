# No EasyEffects

Removes the **EasyEffects** integration that Ambxst carries by default.
EasyEffects stays installed on disk; the mod removes every place the shell
probes, spawns or presents it, so nothing in a session runs or re-spawns it
anymore:

- **The Settings tab loses the Effects section.** The sidebar entry, the
  searchable "Audio Effects" result and the panel behind them are gone.
  With every reference removed, the QML service singleton is never
  instantiated: no availability probes, no 5-second poller, no CLI spawn
  triggers.
- **The service daemon the shell's backend auto-spawns is terminated.**
  Ambxst's daemon launches an `easyeffects --gapplication-service` instance
  before Quickshell runs, hidden and untouchable from QML. The mod ships a
  tiny cleanup service that looks for that instance during the first ~16
  seconds of every shell start and kills it (the same cmdline the base
  shell itself matches); afterwards it goes quiet — nothing kills or
  respawns EasyEffects for the rest of the session.

Two things the mod does not do: it does not uninstall the `easyeffects`
package, and it does not touch anything else in the shell (the mixer and
audio widgets are separate code paths).

## Install

Either with the mod manager CLI:

```sh
ambxst mods install https://github.com/EliasLd/ambxst-mods/tree/main/packages/no-easyeffects
ambxst mods enable eliasld.no-easyeffects
ambxst mods rebuild
```

or from the GUI: Settings -> Mods -> paste the same URL, install, enable the
toggle, rebuild. Restart Ambxst afterwards.

## Verify

1. Settings has no Effects entry, and searching "easyeffects" (or "audio
   effects") returns nothing.
2. After a shell start, `pgrep -f 'easyeffects.*gapplication-service'` is
   empty once the first ~16 seconds passed; the Quickshell log marks the
   moment with `[no-easyeffects] EasyEffects service is gone`.

## Revert

Disable the mod (`ambxst mods disable eliasld.no-easyeffects`), rebuild and
restart: the Effects section and the auto-spawned daemon return. Or skip
the mod generation entirely with `AMBXST_MODS_DISABLED=1 ambxst`.

## Optional: remove the package too

The mod alone leaves an unused EasyEffects binary on disk, doing nothing.
To drop it as well, run `pacman -R easyeffects` (or the equivalent of your
distro; with the Ambxst Nix packaging, remove the entry from
`nix/packages/apps.nix`). With the binary gone, the cleanup window simply
finds nothing, and Ambxst's install script does not re-run on updates, so
the dependency does not silently come back.

## Caveats

- If EasyEffects is opened with a window during the ~16 s startup window,
  that instance shares the service's identity and is closed too. Opens
  after the window are untouched, and stay up for the whole session, since
  nothing respawns the service after the cleanup window closes.
- Killing the service removes EasyEffects' pipewire effect loop — that is
  EasyEffects' own defined exit behavior, and routing falls back to the raw
  devices.

## Compatibility

Tested against Ambxst 1.3.15 (commit
5d71e924212ce2c0203e7448e0b1e3db52608640) and 1.4.1 (commit
5db90ba000713b5cb991a2abce1b766ab47fbd2b); the patched sources are
byte-identical between both. The patch removes the Effects entries from
`SettingsTab.qml` and `SettingsIndex.qml`; see
`patches/no-easyeffects.patch`. The Go-side spawn lives in the compiled
`ambxst` binary and remains stock behavior — this package's cleanup service
runs after each shell start to compensate.

> Note: the startup cleanup described in the second bullet is being added
> in the next commit of this branch. Until then the mod only removes the
> UI integration, and the Go-spawned daemon still exists each session.
