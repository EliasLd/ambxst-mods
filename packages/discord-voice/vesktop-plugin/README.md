# AmbxstDiscord plugin source

Companion Vencord userplugin for the Ambxst `discord-voice` mod. This
directory is the source of truth for published builds and for local builds;
it is never composed into Ambxst itself.

User-facing install and troubleshooting steps live in the package
`README.md`; the wire protocol lives there too.

## Files

| file | role |
|---|---|
| `index.tsx` | renderer side: voice state serialization, speaking coalescing (30 ms), op execution |
| `native.ts` | Vesktop main process side: unix socket transport with backoff reconnect and the long-poll command path |
| `VENCORD_REF` | the Vencord ref all published builds are pinned to |

## Local build

The repo-root script does the whole round trip:

```
sh scripts/discord-plugin-build.sh              # default pin, default tmp dir
sh scripts/discord-plugin-build.sh --ref v1.15.18 --out /tmp/artifacts
```

It clones Vencord at the ref, injects this directory as
`src/userplugins/ambxst-discord/` (index.tsx + native.ts only), runs
`pnpm install && pnpm build` and verifies the four artifacts Vesktop loads
(`vencordDesktopMain.js`, `vencordDesktopPreload.js`,
`vencordDesktopRenderer.js`, `vencordDesktopRenderer.css`). CI runs the same
steps in `.github/workflows/discord-build.yml`.
