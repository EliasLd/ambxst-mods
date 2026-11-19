/*
 * AmbxstDiscord, the companion Vencord userplugin for the Ambxst
 * discord-voice mod.
 *
 * Serializes Discord's own voice state into the wire protocol the mod
 * expects (newline-delimited JSON, see packages/discord-voice/README.md)
 * and executes the actions the tab sends, so every value stays truthful no
 * matter where the change came from.
 *
 * Copyright (c) 2026 EliasLd
 * SPDX-License-Identifier: GPL-3.0-or-later
 */

import definePlugin, { PluginNative } from "@utils/types";
import { findByPropsLazy, findStoreLazy, onceReady } from "@webpack";
import {
    ChannelStore,
    GuildMemberStore,
    GuildStore,
    IconUtils,
    MediaEngineStore,
    SelectedChannelStore,
    UserStore,
    VoiceStateStore
} from "@webpack/common";
import gitHash from "~git-hash";

import type * as NativeModule from "./native";

const PLUGIN_VERSION = "0.1.0";

// How long speaking transitions are debounced before being sent. Discord can
// emit rapid toggles; coalescing keeps the protocol sparse.
const SPEAKING_FLUSH_MS = 30;

// Wire types (plan section 5). volume is the local percent 0-200 the same
// slider Discord's voice UI edits; both volume and localMute are null when
// the media engine has no data, and the tab hides the slider then.

interface WireSelf {
    id: string;
    name: string;
    avatarUrl: string | null;
    muted: boolean;
    deafened: boolean;
    suppressed: boolean;
}

interface WireUser {
    id: string;
    name: string;
    avatarUrl: string | null;
    muted: boolean;
    deafened: boolean;
    suppressed: boolean;
    volume: number | null;
    localMute: boolean | null;
}

interface WireState {
    inVoice: boolean;
    channel: { id: string; name: string; guildId: string; guildName: string } | null;
    self: WireSelf;
    users: WireUser[];
}

// --- Transport ---------------------------------------------------------------
//
// On Vesktop the transport is the PluginNative helpers of native.ts (a unix
// socket client on the main process). Anywhere else (web, other clients)
// lines fall back to the console; the mod only exists for Vesktop setups.

type NativeHelpers = PluginNative<typeof NativeModule>;

const Native: NativeHelpers | undefined = IS_VESKTOP
    ? VencordNative.pluginHelpers.AmbxstDiscord as NativeHelpers
    : undefined;

interface Transport {
    // Ordered, awaited line sends (hello before the first snapshot).
    sendLines(lines: string[]): Promise<void>;
    // Batched, order-insensitive speaking lines.
    sendSpeakingBatch(lines: string[]): void;
}

const stubTransport: Transport = {
    async sendLines(lines) {
        for (const line of lines)
            console.debug("[AmbxstDiscord]", line);
    },
    sendSpeakingBatch(lines) {
        for (const line of lines)
            console.debug("[AmbxstDiscord]", line);
    }
};

const nativeTransport: Transport | null = Native
    ? {
        async sendLines(lines) {
            // One invoke per line preserves hello-before-snapshot.
            for (const line of lines)
                await Native.sendState(line);
        },
        sendSpeakingBatch(lines) {
            // Fire and forget: a failed batch is retried by the next flush
            // or superseded by the next snapshot; native drops silent.
            void Native.sendSpeaking(lines);
        }
    }
    : null;

const transport: Transport = nativeTransport ?? stubTransport;

// --- Discord internal modules ------------------------------------------------
//
// Resolved the same way Vencord plugins do, all named props verified against
// the current voice bundle:
// - voiceSettings: the module whose functions the voice UI itself calls
//   (setSelfMute / setLocalVolume / toggleSelfMute / toggleSelfDeaf live
//   together on its default export, hence the nested-export props find).
// - channelActions: selectVoiceChannel + selectChannel (userVoiceShow
//   precedent); selectVoiceChannel(null) is Discord's own disconnect flow.
// - SpeakingStore: displayName-located FluxStore backing the speaking rings.

interface VoiceSettingsActions {
    setLocalVolume(userId: string, volume: number): void;
    toggleSelfMute(options?: Record<string, unknown>): void;
    toggleSelfDeaf(options?: Record<string, unknown>): void;
}

interface ChannelActions {
    selectVoiceChannel(channelId: string | null, ...args: unknown[]): void;
}

interface SpeakingStoreLike {
    getSpeakers(): string[];
    addChangeListener(callback: () => void): void;
    removeChangeListener(callback: () => void): void;
}

// The actions object hides behind a default export, so props matching must
// go through the nested-export scan (findByProps does this by default).
const voiceSettingsActions = findByPropsLazy(
    "setSelfMute",
    "setLocalVolume",
    "toggleSelfMute",
    "toggleSelfDeaf"
) as unknown as VoiceSettingsActions | undefined;

const channelActions = findByPropsLazy(
    "selectVoiceChannel",
    "selectChannel"
) as unknown as ChannelActions | undefined;

const speakingStore = findStoreLazy("SpeakingStore") as unknown as SpeakingStoreLike | undefined;

// --- Speaking coalescing ----------------------------------------------------
//
// Diff the SpeakingStore's current speakers against the previous set on its
// change events (the same subscription the voice UI's speaking rings use),
// then keep only the latest transition per user and flush one batch per
// SPEAKING_FLUSH_MS. No flux event names involved, so renames upstream
// cannot break it.

const speakingQueue = new Map<string, boolean>();
let speakingTimer: ReturnType<typeof setTimeout> | undefined;
let knownSpeakers: Set<string> | null = null;

function queueSpeaking(userId: string, on: boolean) {
    if (!userId)
        return;
    speakingQueue.set(userId, on);
    if (speakingTimer === undefined)
        speakingTimer = setTimeout(flushSpeaking, SPEAKING_FLUSH_MS);
}

function flushSpeaking() {
    speakingTimer = undefined;
    if (speakingQueue.size === 0 || ready === false)
        return;

    const lines = Array.from(speakingQueue, ([userId, on]) =>
        JSON.stringify({ t: "speaking", userId, on }));
    speakingQueue.clear();
    transport.sendSpeakingBatch(lines);
}

function diffSpeaking() {
    if (!ready || !speakingStore?.getSpeakers)
        return;

    const current = new Set(speakingStore.getSpeakers());
    if (knownSpeakers) {
        for (const userId of current)
            if (!knownSpeakers.has(userId))
                queueSpeaking(userId, true);
        for (const userId of knownSpeakers)
            if (!current.has(userId))
                queueSpeaking(userId, false);
    }
    knownSpeakers = current;
}

// --- Serialization ----------------------------------------------------------

function serializeSelf(): WireSelf {
    const me = UserStore.getCurrentUser();
    // Outside a voice channel the voice state is absent; the self flags only
    // matter while in voice (the tab hides the controls otherwise), so the
    // absence simply renders as "everything off".
    const state = me ? VoiceStateStore.getVoiceStateForUser(me.id) : undefined;
    return {
        id: me?.id ?? "",
        name: me?.globalName ?? me?.username ?? "",
        // Shaped like a WireUser (same key, same null rules) so the tab can
        // render self as a participant row in the identical style; volume
        // and localMute stay absent since they do not apply to self.
        avatarUrl: me ? IconUtils.getUserAvatarURL(me, true, 80) : null,
        muted: (state?.mute ?? false) || (state?.selfMute ?? false),
        deafened: (state?.deaf ?? false) || (state?.selfDeaf ?? false),
        suppressed: state?.suppress ?? false
    };
}

function serializeUser(userId: string, guildId: string): WireUser {
    const user = UserStore.getUser(userId);
    const state = VoiceStateStore.getVoiceStateForUser(userId);
    // The guild nick first, like Discord itself does, then the profile name.
    const nick = guildId ? GuildMemberStore.getNick(guildId, userId) : null;
    return {
        id: userId,
        name: nick ?? user?.globalName ?? user?.username ?? userId,
        avatarUrl: user ? IconUtils.getUserAvatarURL(user, true, 80) : null,
        muted: (state?.mute ?? false) || (state?.selfMute ?? false),
        deafened: (state?.deaf ?? false) || (state?.selfDeaf ?? false),
        suppressed: state?.suppress ?? false,
        volume: MediaEngineStore?.getLocalVolume?.(userId) ?? null,
        localMute: MediaEngineStore?.isLocalMute?.(userId) ?? null
    };
}

function buildSnapshot(): WireState {
    const channelId = SelectedChannelStore.getVoiceChannelId();

    if (!channelId)
        return { inVoice: false, channel: null, self: serializeSelf(), users: [] };

    const channel = ChannelStore.getChannel(channelId);
    const guildId = channel?.guild_id ?? "";

    const users = Object.values(VoiceStateStore.getVoiceStatesForChannel(channelId))
        .map(state => state?.userId)
        .filter((id): id is string => !!id && id !== UserStore.getCurrentUser()?.id)
        .map(id => serializeUser(id, guildId))
        .sort((a, b) => a.name.localeCompare(b.name));

    // DM calls have no guild; the tab shows the channel name alone then.
    const guildName = guildId ? GuildStore.getGuild(guildId)?.name : "";

    return {
        inVoice: true,
        channel: {
            id: channelId,
            name: channel?.name ?? channelId,
            guildId,
            guildName
        },
        self: serializeSelf(),
        users
    };
}

function helloLine(): string {
    return JSON.stringify({ t: "hello", plugin: PLUGIN_VERSION, vencordHash: gitHash });
}

function stateLine(): string {
    return JSON.stringify({ t: "state", v: 1, data: buildSnapshot() });
}

// Full snapshots on every structural change (plan section 5): the payloads
// are small, and the mod side stays stateless.
let ready = false;

function pushState() {
    if (ready)
        void transport.sendLines([stateLine()]);
}

// --- Session announce ---------------------------------------------------------
//
// The mod learns of the plugin through the hello line, and native has no
// push channel, so the renderer polls status() and re-announces whenever the
// native session counter moved (bridge down and back up: shell restart, or
// the shell rebuilding while Vesktop stays open). Lines pushed into a dead
// socket are dropped by native, so the bump guarantees a fresh hello plus a
// full snapshot instead of silence.

let lastSession = -1;
let sessionPollTimer: ReturnType<typeof setInterval> | undefined;

async function announce(session: number) {
    lastSession = session;
    await transport.sendLines([helloLine(), stateLine()]);
}

function startSessionPolling() {
    if (sessionPollTimer !== undefined || !Native)
        return;
    sessionPollTimer = setInterval(() => {
        void (async () => {
            try {
                const st = await Native.status();
                if (st.connected && st.session !== lastSession)
                    await announce(st.session);
            } catch (e) {
                console.warn("[AmbxstDiscord] status poll failed", e);
            }
        })();
    }, 2000);
}

// --- Command loop --------------------------------------------------------------
//
// The page keeps exactly one nextCommand invoke in flight: native resolves
// it when the shell sends a line, the renderer executes the op and answers
// with Native.ack (plan 8.2). Op execution lands with the controls
// milestone; until then unknown ops get a clean failure ack.

let commandsRunning = false;

async function runCommandLoop() {
    if (commandsRunning || !Native)
        return;
    commandsRunning = true;

    while (commandsRunning) {
        let line: string | null;
        try {
            line = await Native.nextCommand();
        } catch (e) {
            console.warn("[AmbxstDiscord] command poll failed", e);
            line = null;
        }

        if (!commandsRunning)
            break;
        if (line == null || line === "") {
            // "Poll again" from native: pause briefly instead of hammering
            // the invoke. Do not cancel this timer on stop - the loop exits
            // on the flag check right after the pause.
            await new Promise<void>(resolve => setTimeout(resolve, 200));
            continue;
        }
        try {
            await handleCommandLine(line);
        } catch (e) {
            console.warn("[AmbxstDiscord] command failed:", line, e);
        }
    }

    commandsRunning = false;
}

interface BridgeCommand {
    t?: string;
    id?: number;
    op?: string;
    userId?: string;
    value?: number;
    kind?: string;
    [key: string]: unknown;
}

// Discord's global keybind action entries, delivered on
// KEYBINDS_REGISTER_GLOBAL_KEYBIND_ACTIONS (same surface Vesktop's keybinds
// run on). onTrigger gets the press phase plus the keybind descriptor, like
// Vesktop's keybindHandler does.
interface DiscordKeybindEntry {
    onTrigger(pressed: boolean, keybind: { action: string; shortcut: unknown[]; params: object }): void;
    keyEvents?: { keydown?: boolean; keyup?: boolean };
}

let keybindActions: Record<string, DiscordKeybindEntry> | null = null;

// Camera has no direct action module; it rides the keybind registry entry
// (the same action id Vesktop's keybinds map toggleCamera to, proven in
// upstream #1238).
const OP_TO_KEYBIND_ACTION = {
    camera: "TOGGLE_CAMERA"
} as const;

// Runs a Discord keybind action press-and-release style and lets Discord's
// own keyEvents decide which phase does the work (toggles fire on release,
// push to talk on both).
function triggerKeybindAction(actionId: string): boolean {
    const entry = keybindActions?.[actionId];
    if (!entry?.onTrigger)
        return false;
    const keybind = { action: actionId, shortcut: [] as unknown[], params: {} };
    if (entry.keyEvents?.keydown)
        entry.onTrigger(true, keybind);
    if (entry.keyEvents?.keyup)
        entry.onTrigger(false, keybind);
    return true;
}

// Returns null on success, an error message otherwise (passed to ack).
async function executeCommand(cmd: BridgeCommand): Promise<string | null> {
    switch (cmd.op) {
        case "volume.set": {
            if (typeof cmd.userId !== "string" || !cmd.userId
                || typeof cmd.value !== "number" || !Number.isFinite(cmd.value))
                return "volume.set needs userId and a numeric value";
            // The mod clamps too; clamp again so nothing can write nonsense.
            const value = Math.max(0, Math.min(200, Math.round(cmd.value)));
            voiceSettingsActions?.setLocalVolume(cmd.userId, value);
            return voiceSettingsActions ? null : "voice actions module not found";
        }
        case "self.toggle": {
            if (cmd.kind !== "mute" && cmd.kind !== "deafen")
                return `self.toggle kind must be mute or deafen, got: ${String(cmd.kind ?? "(none)")}`;
            if (!voiceSettingsActions?.toggleSelfMute)
                return "voice actions module not found";
            // The exact function the voice UI's own buttons run.
            if (cmd.kind === "mute")
                voiceSettingsActions.toggleSelfMute();
            else
                voiceSettingsActions.toggleSelfDeaf();
            return null;
        }
        case "camera.toggle":
            return triggerKeybindAction(OP_TO_KEYBIND_ACTION.camera)
                ? null
                : "Discord has not registered its keybind actions yet";
        case "voice.leave":
            // null is exactly what Discord's own disconnect flow passes.
            if (!channelActions?.selectVoiceChannel)
                return "channel actions module not found";
            channelActions.selectVoiceChannel(null);
            return null;
        case "state.get":
            pushState();
            return null;
        default:
            return `unknown op: ${String(cmd.op ?? "(none)")}`;
    }
}

async function handleCommandLine(line: string) {
    if (!Native)
        return;
    let cmd: BridgeCommand;
    try {
        cmd = JSON.parse(line) as BridgeCommand;
    } catch {
        return;
    }
    if (cmd.t !== "cmd" || typeof cmd.id !== "number")
        return;

    const failure = await executeCommand(cmd);
    await Native.ack(cmd.id, failure === null, failure ?? "");
}

export default definePlugin({
    name: "AmbxstDiscord",
    description: "Companion for the Ambxst discord-voice mod: streams voice state from Vesktop to the Ambxst dashboard tab. Enable it only if you use that mod.",
    authors: [{ name: "EliasLd", id: 0n }],

    flux: {
        // Anything that changes who is in the channel or their flags lands in
        // the voice state store, so one handler covers join/leave/move and
        // mute changes for us and everyone else.
        VOICE_STATE_UPDATES: () => pushState(),

        // Backup catches for the self flags: they dispatch before or instead
        // of a voice state update in some paths, and the store read is cheap.
        AUDIO_TOGGLE_SELF_MUTE: () => pushState(),
        AUDIO_TOGGLE_SELF_DEAF: () => pushState(),

        // Who is talking comes from the SpeakingStore diff (see its section);
        // the old AUDIO_START/STOP_SPEAKING dispatches no longer exist in the
        // current client, so there is deliberately no flux speaking entry.

        // Discord hands out its global keybind actions here (the same surface
        // Vesktop's own keybinds run on); captured for the camera toggle,
        // which has no direct actions module.
        KEYBINDS_REGISTER_GLOBAL_KEYBIND_ACTIONS: (event: { keybinds?: Record<string, DiscordKeybindEntry> }) => {
            keybindActions = event.keybinds ?? null;
        }
    },

    async start() {
        // The plugin starts before Discord's webpack modules resolve; store
        // reads are only meaningful once the client finished loading.
        await onceReady;
        ready = true;

        // Per-user local volume lives here, outside the voice states, so its
        // own change listener keeps the tab's sliders truthful - including
        // edits made on Discord's own user volume slider.
        MediaEngineStore.addChangeListener(pushState);

        // Speaking truth: subscribe to the store the voice UI uses, and seed
        // the diff baseline with whoever is already speaking.
        if (speakingStore?.addChangeListener) {
            speakingStore.addChangeListener(diffSpeaking);
            knownSpeakers = new Set(speakingStore.getSpeakers?.() ?? []);
        }

        if (Native) {
            startSessionPolling();
            void runCommandLoop();
            try {
                const st = await Native.status();
                if (st.connected)
                    await announce(st.session);
            } catch (e) {
                console.warn("[AmbxstDiscord] initial status failed", e);
            }
            return;
        }

        // Stub transport (no Vesktop): announce unconditionally, console only.
        await transport.sendLines([helloLine(), stateLine()]);
    },

    stop() {
        ready = false;
        commandsRunning = false;
        MediaEngineStore.removeChangeListener(pushState);
        speakingStore?.removeChangeListener?.(diffSpeaking);
        knownSpeakers = null;
        if (sessionPollTimer !== undefined) {
            clearInterval(sessionPollTimer);
            sessionPollTimer = undefined;
        }
        if (speakingTimer !== undefined) {
            clearTimeout(speakingTimer);
            speakingTimer = undefined;
        }
        speakingQueue.clear();
    }
});
