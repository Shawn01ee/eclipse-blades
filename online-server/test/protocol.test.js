import test from "node:test";
import assert from "node:assert/strict";
import {
  allowedOrigin,
  cleanCharacter,
  cleanInput,
  cleanTick,
  parseClientMessage,
  roomCodeFromPath,
} from "../src/protocol.js";

test("validates safe six-character room codes", () => {
  assert.equal(roomCodeFromPath("/room/AB7K2Z"), "AB7K2Z");
  assert.equal(roomCodeFromPath("/room/ab7k2z"), "AB7K2Z");
  assert.equal(roomCodeFromPath("/room/O00000"), null);
  assert.equal(roomCodeFromPath("/room/ABCDE"), null);
});

test("accepts only compact valid protocol payloads", () => {
  assert.deepEqual(parseClientMessage('{"t":"input","k":4,"w":3}'), { t: "input", k: 4, w: 3 });
  assert.equal(parseClientMessage("not-json"), null);
  assert.equal(parseClientMessage(`{"x":"${"a".repeat(600)}"}`), null);
});

test("validates fighter, input bitmask and strictly sequential tick", () => {
  assert.equal(cleanCharacter(4), 4);
  assert.equal(cleanCharacter(5), null);
  assert.equal(cleanInput(1023), 1023);
  assert.equal(cleanInput(1024), null);
  assert.equal(cleanTick(12, 11), 12);
  assert.equal(cleanTick(14, 11), null);
});

test("allows production and local development origins only", () => {
  assert.equal(allowedOrigin("https://shawn01ee.github.io"), true);
  assert.equal(allowedOrigin("http://localhost:8060"), true);
  assert.equal(allowedOrigin("https://evil.example"), false);
});
