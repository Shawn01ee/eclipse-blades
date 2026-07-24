import test from "node:test";
import assert from "node:assert/strict";
import {
  PROTOCOL,
  SIM_BUILD,
  allowedOrigin,
  cleanCharacter,
  cleanInput,
  cleanTick,
  parseClientMessage,
  roomCodeFromPath,
} from "../src/protocol.js";

test("validates four-digit numeric room codes", () => {
  assert.equal(roomCodeFromPath("/room/0427"), "0427");
  assert.equal(roomCodeFromPath("/room/9999"), "9999");
  assert.equal(roomCodeFromPath("/room/AB7K"), null);   // 문자 불가
  assert.equal(roomCodeFromPath("/room/427"), null);    // 3자리 불가
  assert.equal(roomCodeFromPath("/room/04270"), null);  // 5자리 불가
});

test("accepts only compact valid protocol payloads", () => {
  assert.deepEqual(parseClientMessage('{"t":"input","k":4,"w":3}'), { t: "input", k: 4, w: 3 });
  assert.equal(parseClientMessage("not-json"), null);
  assert.equal(parseClientMessage(`{"x":"${"a".repeat(600)}"}`), null);
});

test("validates fighter, input bitmask and strictly sequential tick", () => {
  assert.equal(PROTOCOL, 2);
  assert.equal(SIM_BUILD, "2026-07-20-hayate-rushdown");
  assert.equal(cleanCharacter(5), 5);
  assert.equal(cleanCharacter(6), null);
  assert.equal(cleanInput(1023), 1023);
  assert.equal(cleanInput(1024), null);
  assert.equal(cleanTick(12, 11), 12);
  assert.equal(cleanTick(14, 11), null);
});

test("allows production and local development origins only", () => {
  assert.equal(allowedOrigin("https://eclipse-blades.vercel.app"), true);
  assert.equal(allowedOrigin("https://eclipse-blades-rmis4mcur-leesmofficial01-7776s-projects.vercel.app"), true);
  assert.equal(allowedOrigin("https://web-gilt-iota-25.vercel.app"), true);
  assert.equal(allowedOrigin("http://localhost:8060"), true);
  assert.equal(allowedOrigin("https://evil.example"), false);
  assert.equal(allowedOrigin("https://evil.vercel.app"), false);
  assert.equal(allowedOrigin("https://website-evil.vercel.app"), false);
});
