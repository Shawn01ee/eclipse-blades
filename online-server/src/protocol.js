export const PROTOCOL = 2;
export const SIM_BUILD = "2026-07-20-hayate-rushdown";
export const INPUT_MASK = 1023;
export const MAX_TICK_LEAD = 240;
export const ROOM_RE = /^[0-9]{4}$/;

export function roomCodeFromPath(pathname) {
  const match = pathname.match(/^\/room\/([0-9]{4})$/);
  if (!match) return null;
  const code = match[1];
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
  return Number.isInteger(value) && value >= 0 && value <= 5 ? value : null;
}

export function cleanInput(value) {
  return Number.isInteger(value) && value >= 0 && value <= INPUT_MASK ? value : null;
}

export function cleanTick(value, lastTick) {
  return Number.isInteger(value) && value === lastTick + 1 ? value : null;
}

export function allowedOrigin(origin) {
  if (!origin) return true;
  // Vercel 배포(프로덕션·프리뷰) — eclipse-blades(신규)·web(구) 프로젝트의 vercel.app
  if (/^https:\/\/(eclipse-blades|web)(-[a-z0-9-]+)?\.vercel\.app$/.test(origin)) return true;
  return /^http:\/\/(localhost|127\.0\.0\.1)(:\d+)?$/.test(origin);
}
