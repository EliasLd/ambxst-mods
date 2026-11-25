# Changelog

## 0.1.0

- The Effects section leaves the Settings tab: the sidebar entry, the
  searchable "Audio Effects" result and the panel behind them are removed.
  With every reference gone, the EasyEffects service singleton is never
  instantiated, so the shell stops probing and respawn-triggering the
  `easyeffects` CLI altogether.
- A cleanup service kills the `easyeffects --gapplication-service` instance
  the shell's backend spawns at every start, within the first ~16 seconds
  of the session; afterwards it stays quiet, and nothing respawns
  EasyEffects until the next shell start.
