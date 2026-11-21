/*
 * AmbxstDiscord native side, running in the Vesktop main process through
 * Vencord's PluginNative machinery (plan section 8.2).
 *
 * One unix socket client to the mod's bridge, at the same path the QML side
 * derives: $XDG_RUNTIME_DIR/ambxst_discord.sock. Every exported function
 * becomes a promise-returning renderer helper; arguments must stay
 * structured-clone safe. There is no fs access and no shell here, and the
 * socket path is computed, never taken from the page.
 *
 * Copyright (c) 2026 EliasLd
 * SPDX-License-Identifier: GPL-3.0-or-later
 */

import { IpcMainInvokeEvent } from "electron";
import { Socket } from "net";
import { createInterface } from "readline";

// Identical resolution to the DiscordVoice singleton:
// (XDG_RUNTIME_DIR || "/tmp") + "/ambxst_discord.sock".
const RUNTIME_DIR = process.env.XDG_RUNTIME_DIR ?? "/tmp";
const SOCKET_PATH = `${RUNTIME_DIR}/ambxst_discord.sock`;

// The shell may be off, rebuilding or disabled: back off exponentially from
// 1 s to a 2 s ceiling, then reset once a connection succeeds. A refused
// attempt is one silent syscall now that every error path is handled, so a
// tight ceiling keeps the tab's companion chip faithful within a couple of
// seconds of the shell restarting.
const RECONNECT_BASE_MS = 1000;
const RECONNECT_MAX_MS = 2_000;

// Newlines frame the protocol, so no payload may smuggle one; 3 MiB is the
// same order of magnitude the mod side tolerates per line.
const MAX_LINE_BYTES = 3 * 1024 * 1024;

// If the renderer stops polling (a stranded nextCommand after a reload) the
// queue must not grow without bound.
const MAX_QUEUED_COMMANDS = 64;

let socket: Socket | null = null;
let connected = false;
let connectAttempts = 0;
let reconnectTimer: NodeJS.Timeout | undefined;

// Bumped on every real connect. The renderer polls status() and re-announces
// itself (hello + fresh snapshot) whenever the number changes, so a
// restarted shell picks the plugin up within a couple of seconds without
// anyone keeping a persistent event channel.
let session = 0;

const commandQueue: string[] = [];
const pendingCommandResolvers: Array<(line: string | null) => void> = [];

function connect() {
    clearTimeout(reconnectTimer);
    reconnectTimer = undefined;
    socket?.destroy();

    const sock = new Socket();
    socket = sock;

    // Errors surface through close, which owns the reconnect decision.
    sock.on("error", () => {});
    sock.on("connect", () => {
        connected = true;
        session++;
        connectAttempts = 0;
        console.log("[AmbxstDiscord] connected to", SOCKET_PATH);
    });
    sock.on("close", () => {
        connected = false;
        // A late close from a replaced socket must not schedule a reconnect
        // behind the newer attempt's back.
        if (socket !== sock)
            return;
        scheduleReconnect();
    });

    // The mod only ever sends command lines; route them to the long-poll.
    // Readline re-emits socket errors on the Interface itself, and an
    // Interface "error" with no listener surfaces as an uncaught exception:
    // a refused connect attempt (the shell closed or restarting) used to
    // pop Electron's crash dialog on every retry. Handle it there too.
    createInterface({ input: sock })
        .on("line", line => {
            if (!line)
                return;
            commandQueue.push(line);
            if (commandQueue.length > MAX_QUEUED_COMMANDS)
                commandQueue.shift();
            flushCommands();
        })
        .on("error", () => {});

    sock.connect(SOCKET_PATH);
}

function scheduleReconnect() {
    if (reconnectTimer)
        return;
    const delay = Math.min(RECONNECT_BASE_MS * 2 ** connectAttempts, RECONNECT_MAX_MS);
    connectAttempts++;
    reconnectTimer = setTimeout(() => {
        reconnectTimer = undefined;
        connect();
    }, delay);
}

function flushCommands() {
    while (commandQueue.length > 0 && pendingCommandResolvers.length > 0) {
        const resolve = pendingCommandResolvers.shift()!;
        resolve(commandQueue.shift()!);
    }
}

function writeLn(line: string): boolean {
    if (!connected || !socket)
        // Drop rather than buffer while the mod is away: a stale snapshot
        // would lie worse than silence, and fresh state follows the next
        // change or the renderer's session poll.
        return false;
    if (!line || line.includes("\n") || Buffer.byteLength(line) > MAX_LINE_BYTES)
        return false;
    socket.write(line + "\n");
    return true;
}

// Boot the reconnect loop with the module; it lives as long as the process.
if (process.platform !== "win32")
    connect();

// --- Renderer helpers (Vencord PluginNative) ---------------------------------

export async function sendState(_: IpcMainInvokeEvent, json: string) {
    return writeLn(String(json));
}

export async function sendSpeaking(_: IpcMainInvokeEvent, lines: string[]) {
    if (!Array.isArray(lines))
        return false;
    let wroteAny = false;
    for (const line of lines)
        wroteAny = writeLn(String(line)) || wroteAny;
    return wroteAny;
}

// The renderer keeps exactly one invoke of this in flight; it stays pending
// until a command line arrives. null means "poll again", which the loop
// answers after a short pause.
export async function nextCommand(_: IpcMainInvokeEvent): Promise<string | null> {
    if (commandQueue.length > 0)
        return commandQueue.shift() ?? null;

    return new Promise<string | null>(resolve => {
        if (pendingCommandResolvers.length >= MAX_QUEUED_COMMANDS) {
            // Strand cap: retire the oldest waiter instead of growing.
            const retire = pendingCommandResolvers.shift()!;
            retire(null);
        }
        pendingCommandResolvers.push(resolve);
        flushCommands();
    });
}

export async function ack(_: IpcMainInvokeEvent, id: number, ok: boolean, error: string) {
    const payload: Record<string, unknown> = { t: "ack", id: id, ok: ok };
    if (!ok)
        payload.error = String(error ?? "");
    writeLn(JSON.stringify(payload));
    return true;
}

export async function status(_: IpcMainInvokeEvent) {
    return { connected: connected, session: session, socketPath: SOCKET_PATH };
}
