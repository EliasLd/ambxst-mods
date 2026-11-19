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

import definePlugin from "@utils/types";
import { onceReady } from "@webpack";
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

// --- Transport -------------------------------------------------------------
//
// M2 stub: lines land in the console so the DevTools checklist can verify
// the serialization. M3 swaps in the PluginNative transport from native.ts
// (unix socket to the mod) without touching anything above this comment.

interface Transport {
    sendLines(lines: string[]): void;
}

const stubTransport: Transport = {
    sendLines(lines) {
        for (const line of lines)
            console.debug("[AmbxstDiscord]", line);
    }
};

const transport: Transport = stubTransport;

// --- Speaking coalescing ----------------------------------------------------
//
// Keep only the latest transition per user and flush one batch every SPEAK:
// a user flapping mute-and-talk still produces at most one line per flush.

const speakingQueue = new Map<string, boolean>();
let speakingTimer: ReturnType<typeof setTimeout> | undefined;

function queueSpeaking(userId: string, on: boolean) {
    if (!userId)
        return;
    speakingQueue.set(userId, on);
    if (speakingTimer === undefined)
        speakingTimer = setTimeout(flushSpeaking, SPEAKING_FLUSH_MS);
}

function flushSpeaking() {
    speakingTimer = undefined;
    if (speakingQueue.size === 0)
        return;

    const lines = Array.from(speakingQueue, ([userId, on]) =>
        JSON.stringify({ t: "speaking", userId, on }));
    speakingQueue.clear();
    transport.sendLines(lines);
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
        transport.sendLines([stateLine()]);
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

        // Who is talking. SPEAKING / STOP_SPEAKING are the names the current
        // client dispatches (discord-types); the AUDIO_START/STOP pair is a
        // legacy fallback kept so a future rebuild cannot go silent.
        SPEAKING: (event: { userId?: string }) => queueSpeaking(event.userId ?? "", true),
        STOP_SPEAKING: (event: { userId?: string }) => queueSpeaking(event.userId ?? "", false),
        AUDIO_START_SPEAKING: (event: { userId?: string }) => queueSpeaking(event.userId ?? "", true),
        AUDIO_STOP_SPEAKING: (event: { userId?: string }) => queueSpeaking(event.userId ?? "", false)
    },

    async start() {
        // The plugin starts before Discord's webpack modules resolve; store
        // reads are only meaningful once the client finished loading.
        await onceReady;
        ready = true;
        // hello announces the plugin to the mod; the first snapshot follows.
        transport.sendLines([helloLine(), stateLine()]);
    },

    stop() {
        ready = false;
        if (speakingTimer !== undefined) {
            clearTimeout(speakingTimer);
            speakingTimer = undefined;
        }
        speakingQueue.clear();
    }
});
