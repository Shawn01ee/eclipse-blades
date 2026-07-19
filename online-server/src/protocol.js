export const PROTOCOL = 1;
export const INPUT_MASK = 1023;
export const MAX_TICK_LEAD = 240;
export const ROOM_RE = /^[A-HJ-NP-Z2-9]{6}$/;

export function roomCodeFromPath(pathname) {
  const match = pathname.match(/^\/room\/([A-Za-z0-9]{6})$/);
  if (!match) return null;
  const code = match[1].toUpperCase();
  return ROOM_RE.test(code) ? code : null;
}

export function parseClientMessage(raw) {
  if (typeof raw !== "string" || raw.length > 512) return null;
  let value;
  try {
    value = JSON.parse(raw);
  } catch {
    return null;
  }
  if (!value || typeof value !== "object" || Array.isArray(value)) return null;
  return value;
}

export function cleanCharacter(value) {
  return Number.isInteger(value) && value >= 0 && value <= 4 ? value : null;
}

export function cleanInput(value) {
  return Number.isInteger(value) && value >= 0 && value <= INPUT_MASK ? value : null;
}

export function cleanTick(value, lastTick) {
  return Number.isInteger(value) && value === lastTick + 1 ? value : null;
}

export function allowedOrigin(origin) {
  if (!origin) return true;
  if (origin === "https://shawn01ee.github.io") return true;
  return /^http:\/\/(localhost|127\.0\.0\.1)(:\d+)?$/.test(origin);
}
