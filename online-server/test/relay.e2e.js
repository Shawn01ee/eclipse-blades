import assert from "node:assert/strict";

const base = process.argv[2] ?? process.env.RELAY_TEST_URL ?? "ws://127.0.0.1:8788";
const room = "TEST2Z";

function connectClient() {
  const ws = new WebSocket(`${base}/room/${room}?v=1`);
  const messages = [];
  const waiters = [];
  ws.addEventListener("message", (event) => {
    const message = JSON.parse(event.data);
    messages.push(message);
    for (const waiter of [...waiters]) {
      if (waiter.predicate(message)) {
        waiters.splice(waiters.indexOf(waiter), 1);
        waiter.resolve(message);
      }
    }
  });
  const opened = new Promise((resolve, reject) => {
    ws.addEventListener("open", resolve, { once: true });
    ws.addEventListener("error", reject, { once: true });
  });
  function waitFor(predicate, label) {
    const found = messages.find(predicate);
    if (found) return Promise.resolve(found);
    return new Promise((resolve, reject) => {
      const timer = setTimeout(() => reject(new Error(`timeout: ${label}`)), 3000);
      waiters.push({
        predicate,
        resolve: (message) => {
          clearTimeout(timer);
          resolve(message);
        },
      });
    });
  }
  return { ws, opened, waitFor };
}

const first = connectClient();
await first.opened;
const welcome0 = await first.waitFor((m) => m.t === "welcome", "first welcome");
assert.equal(welcome0.slot, 0);

const second = connectClient();
await second.opened;
const welcome1 = await second.waitFor((m) => m.t === "welcome", "second welcome");
assert.equal(welcome1.slot, 1);
await first.waitFor((m) => m.t === "peer_joined" && m.peers === 2, "peer joined");

first.ws.send(JSON.stringify({ t: "select", c: 3 }));
second.ws.send(JSON.stringify({ t: "select", c: 4 }));
first.ws.send(JSON.stringify({ t: "ready", v: true }));
second.ws.send(JSON.stringify({ t: "ready", v: true }));
const [start0, start1] = await Promise.all([
  first.waitFor((m) => m.t === "start", "first start"),
  second.waitFor((m) => m.t === "start", "second start"),
]);
assert.deepEqual(start0.chars, [3, 4]);
assert.equal(start0.seed, start1.seed);

first.ws.send(JSON.stringify({ t: "input", k: 0, w: 17 }));
second.ws.send(JSON.stringify({ t: "input", k: 0, w: 34 }));
await Promise.all([
  first.waitFor((m) => m.t === "input" && m.slot === 1 && m.k === 0 && m.w === 34, "second input on first"),
  second.waitFor((m) => m.t === "input" && m.slot === 0 && m.k === 0 && m.w === 17, "first input on second"),
]);

first.ws.close();
second.ws.close();
console.log("relay e2e passed: room, selection, ready, start and tick relay");
