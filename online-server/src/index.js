import { DurableObject } from "cloudflare:workers";
import {
  PROTOCOL,
  allowedOrigin,
  cleanCharacter,
  cleanInput,
  cleanTick,
  parseClientMessage,
  roomCodeFromPath,
} from "./protocol.js";

const jsonHeaders = {
  "content-type": "application/json; charset=utf-8",
  "cache-control": "no-store",
  "access-control-allow-origin": "*",
};

export default {
  async fetch(request, env) {
    const url = new URL(request.url);
    if (url.pathname === "/health") {
      return Response.json({ ok: true, service: "eclipse-blades-relay", protocol: PROTOCOL }, { headers: jsonHeaders });
    }

    const roomCode = roomCodeFromPath(url.pathname);
    if (!roomCode) {
      return Response.json({ error: "not_found" }, { status: 404, headers: jsonHeaders });
    }
    if (request.headers.get("Upgrade")?.toLowerCase() !== "websocket") {
      return Response.json({ error: "websocket_required" }, { status: 426, headers: jsonHeaders });
    }
    if (url.searchParams.get("v") !== String(PROTOCOL)) {
      return Response.json({ error: "protocol_mismatch", protocol: PROTOCOL }, { status: 400, headers: jsonHeaders });
    }
    if (!allowedOrigin(request.headers.get("Origin"))) {
      return Response.json({ error: "origin_not_allowed" }, { status: 403, headers: jsonHeaders });
    }

    const roomId = env.ROOMS.idFromName(roomCode);
    return env.ROOMS.get(roomId).fetch(request);
  },
};

export class GameRoom extends DurableObject {
  async fetch(request) {
    const pair = new WebSocketPair();
    const [client, server] = Object.values(pair);
    const sockets = this.#openSockets();
    const used = new Set(sockets.map((socket) => socket.deserializeAttachment()?.slot));
    const slot = used.has(0) ? (used.has(1) ? -1 : 1) : 0;

    this.ctx.acceptWebSocket(server, ["player"]);
    if (slot < 0) {
      server.send(JSON.stringify({ t: "error", message: "이미 두 명이 대전 중인 방입니다." }));
      server.close(1008, "room full");
      return new Response(null, { status: 101, webSocket: client });
    }

    const attachment = {
      slot,
      char: slot,
      ready: false,
      started: false,
      lastTick: -1,
      hashTick: -1,
      hash: 0,
    };
    server.serializeAttachment(attachment);
    const all = this.#openSockets();
    server.send(JSON.stringify({
      t: "welcome",
      slot,
      peers: all.length,
      chars: this.#slotValues(all, "char", [0, 1]),
      ready: this.#slotValues(all, "ready", [false, false]),
    }));
    this.#broadcast({ t: "peer_joined", slot, peers: all.length }, server);
    return new Response(null, { status: 101, webSocket: client });
  }

  async webSocketMessage(ws, raw) {
    const message = parseClientMessage(typeof raw === "string" ? raw : "");
    if (!message) {
      ws.send(JSON.stringify({ t: "error", message: "잘못된 네트워크 메시지입니다." }));
      return;
    }
    const attachment = ws.deserializeAttachment();
    if (!attachment || ![0, 1].includes(attachment.slot)) return;

    switch (message.t) {
      case "ping": {
        if (Number.isInteger(message.n)) ws.send(JSON.stringify({ t: "pong", n: message.n }));
        return;
      }
      case "select": {
        if (attachment.started) return;
        const character = cleanCharacter(message.c);
        if (character === null) return;
        attachment.char = character;
        attachment.ready = false;
        ws.serializeAttachment(attachment);
        this.#broadcast({ t: "select", slot: attachment.slot, c: character });
        return;
      }
      case "ready": {
        if (attachment.started || typeof message.v !== "boolean") return;
        attachment.ready = message.v;
        ws.serializeAttachment(attachment);
        this.#broadcast({ t: "ready", slot: attachment.slot, v: message.v });
        this.#tryStart();
        return;
      }
      case "input": {
        if (!attachment.started) return;
        const tick = cleanTick(message.k, attachment.lastTick);
        const word = cleanInput(message.w);
        if (tick === null || word === null) return;
        attachment.lastTick = tick;
        ws.serializeAttachment(attachment);
        this.#broadcast({ t: "input", slot: attachment.slot, k: tick, w: word });
        return;
      }
      case "hash": {
        if (!attachment.started || !Number.isInteger(message.k) || !Number.isInteger(message.h)) return;
        attachment.hashTick = message.k;
        attachment.hash = message.h;
        ws.serializeAttachment(attachment);
        const other = this.#openSockets().find((socket) => socket !== ws);
        const otherState = other?.deserializeAttachment();
        if (otherState?.hashTick === attachment.hashTick && otherState.hash !== attachment.hash) {
          this.#broadcast({ t: "desync", k: attachment.hashTick });
        }
        return;
      }
      default:
        return;
    }
  }

  async webSocketClose(ws, code, reason) {
    const left = ws.deserializeAttachment();
    for (const socket of this.#openSockets()) {
      const state = socket.deserializeAttachment();
      if (!state) continue;
      state.ready = false;
      state.started = false;
      state.lastTick = -1;
      socket.serializeAttachment(state);
      try {
        socket.send(JSON.stringify({ t: "peer_left", slot: left?.slot ?? -1 }));
      } catch {
        // The other player can close in the same event-loop turn.
      }
    }
  }

  async webSocketError(ws) {
    ws.close(1011, "socket error");
  }

  #tryStart() {
    const sockets = this.#openSockets();
    if (sockets.length !== 2) return;
    const states = sockets.map((socket) => socket.deserializeAttachment());
    if (!states.every((state) => state?.ready && !state.started)) return;

    for (let i = 0; i < sockets.length; i += 1) {
      states[i].started = true;
      states[i].lastTick = -1;
      states[i].hashTick = -1;
      sockets[i].serializeAttachment(states[i]);
    }
    const seed = crypto.getRandomValues(new Uint32Array(1))[0] % 100000000 + 1;
    this.#broadcast({ t: "start", seed, chars: this.#slotValues(sockets, "char", [0, 1]) });
  }

  #openSockets() {
    return this.ctx.getWebSockets("player").filter((socket) => socket.readyState === WebSocket.OPEN);
  }

  #slotValues(sockets, key, fallback) {
    const values = [...fallback];
    for (const socket of sockets) {
      const state = socket.deserializeAttachment();
      if (state && [0, 1].includes(state.slot)) values[state.slot] = state[key];
    }
    return values;
  }

  #broadcast(payload, except = null) {
    const text = JSON.stringify(payload);
    for (const socket of this.#openSockets()) {
      if (socket !== except) socket.send(text);
    }
  }
}
