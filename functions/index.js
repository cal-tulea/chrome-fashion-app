/**
 * Chromé — Firebase Cloud Functions
 *
 * geminiProxy: Server-side Gemini proxy with auth + rate limiting
 *   - Requires a valid Firebase ID token (user must be signed in)
 *   - Enforces 50 AI calls/day per user in Firestore
 *   - Keeps the Gemini API key off the client entirely
 *   - Validates and sanitizes all inputs
 *
 * Deploy: firebase deploy --only functions
 * Set Gemini key: firebase functions:config:set gemini.key="YOUR_KEY"
 */

const functions  = require('firebase-functions');
const admin      = require('firebase-admin');
const fetch      = require('node-fetch');

admin.initializeApp();
const db = admin.firestore();

// ── Constants ──────────────────────────────────────────────────────────────
const DAILY_LIMIT       = 50;
const MAX_IMAGE_BYTES   = 5 * 1024 * 1024; // 5 MB base64 decoded cap
const GEMINI_PRIMARY    = 'https://generativelanguage.googleapis.com/v1beta/models/gemini-2.5-flash:generateContent';
const GEMINI_FALLBACK   = 'https://generativelanguage.googleapis.com/v1beta/models/gemini-2.0-flash-lite:generateContent';

// ── Helpers ────────────────────────────────────────────────────────────────

function today() {
  return new Date().toISOString().slice(0, 10); // YYYY-MM-DD
}

/** Sanitize a string field — strip control chars, trim, cap length. */
function sanitize(str, maxLen = 100) {
  if (typeof str !== 'string') return '';
  return str
    .replace(/[\x00-\x08\x0B\x0C\x0E-\x1F\x7F]/g, '')
    .trim()
    .slice(0, maxLen);
}

/**
 * Check + increment the per-user daily AI call count.
 * Returns { allowed: bool, remaining: int }
 */
async function checkRateLimit(uid) {
  const ref = db.doc(`users/${uid}/usage/aiCalls`);
  return db.runTransaction(async (tx) => {
    const snap = await tx.get(ref);
    const data = snap.exists ? snap.data() : {};
    const t = today();

    const count = (data.date === t) ? (data.count || 0) : 0;
    if (count >= DAILY_LIMIT) {
      return { allowed: false, remaining: 0 };
    }

    tx.set(ref, { count: count + 1, date: t, lastUsed: admin.firestore.FieldValue.serverTimestamp() }, { merge: true });
    return { allowed: true, remaining: DAILY_LIMIT - (count + 1) };
  });
}

/** Forward a request to a Gemini endpoint. Returns the fetch Response. */
async function callGemini(endpoint, imageBase64, prompt, isThinkingModel) {
  const geminiKey = functions.config().gemini.key;

  const genConfig = { temperature: 0.1, maxOutputTokens: 100 };
  if (isThinkingModel) genConfig.thinkingConfig = { thinkingBudget: 0 };

  const body = {
    contents: [{
      parts: [
        { inlineData: { mimeType: 'image/jpeg', data: imageBase64 } },
        { text: prompt },
      ],
    }],
    generationConfig: genConfig,
  };

  return fetch(`${endpoint}?key=${geminiKey}`, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify(body),
    signal: AbortSignal.timeout(25_000),
  });
}

// ── Cloud Function ─────────────────────────────────────────────────────────

/**
 * geminiProxy — HTTPS callable
 *
 * Request body:
 *   { imageBase64: string, hint: string | null }
 *
 * Response:
 *   { result: string }  — raw pipe-separated Gemini output
 *
 * Errors (codes follow Firebase Functions error codes):
 *   unauthenticated   — no valid auth token
 *   resource-exhausted — daily AI limit reached
 *   invalid-argument  — bad input
 *   internal          — upstream failure
 */
exports.geminiProxy = functions
  .runWith({ timeoutSeconds: 30, memory: '256MB' })
  .https.onCall(async (data, context) => {

    // ── 1. Auth check ──────────────────────────────────────────────────────
    if (!context.auth) {
      throw new functions.https.HttpsError(
        'unauthenticated', 'You must be signed in to use AI features.'
      );
    }
    const uid = context.auth.uid;

    // ── 2. Input validation ────────────────────────────────────────────────
    const { imageBase64, hint } = data;

    if (typeof imageBase64 !== 'string' || imageBase64.length === 0) {
      throw new functions.https.HttpsError('invalid-argument', 'imageBase64 is required.');
    }
    // Rough size guard (base64 is ~4/3 of binary, so *3/4 ≈ actual bytes)
    if (imageBase64.length * 0.75 > MAX_IMAGE_BYTES) {
      throw new functions.https.HttpsError('invalid-argument', 'Image too large (max 5 MB).');
    }

    const safeHint = hint ? sanitize(hint, 30) : null;

    // ── 3. Rate limit ──────────────────────────────────────────────────────
    const { allowed, remaining } = await checkRateLimit(uid);
    if (!allowed) {
      throw new functions.https.HttpsError(
        'resource-exhausted',
        `Daily AI limit of ${DAILY_LIMIT} calls reached. Resets tomorrow.`
      );
    }
    functions.logger.info(`[GeminiProxy] uid=${uid} hint=${safeHint} remaining=${remaining}`);

    // ── 4. Build prompt (mirrors GeminiVisionService._buildPrompt) ─────────
    const hintContext = safeHint === 'footwear'
      ? 'The item is footwear. Look carefully — it could be sneakers, boots, oxfords, loafers, heels, sandals, mules, or flats.'
      : safeHint
        ? `The item is likely a ${safeHint}.`
        : 'Identify the type of clothing or footwear item.';

    const prompt = [
      'Analyze this clothing/footwear image and respond with EXACTLY ONE LINE in this format:',
      'GARMENT|COLOR|FIT|WASH|PATTERN|MATERIAL',
      '',
      hintContext,
      '',
      'Rules:',
      '- GARMENT: specific type (e.g. sneakers, boots, oxford shirt, chinos, blazer, jeans)',
      '- COLOR: main color (e.g. white, navy, black, tan)',
      '- FIT: slim / regular / relaxed / oversized',
      '- WASH: light / medium / dark / N/A',
      '- PATTERN: solid / striped / checked / printed / N/A',
      '- MATERIAL: for footwear use leather/suede/canvas/rubber/mesh/synthetic/unknown; NEVER use denim/cotton/wool for shoes',
      '- Respond with ONLY the pipe-separated line, no extra text',
    ].join('\n');

    // ── 5. Call Gemini with cascade ────────────────────────────────────────
    let response = await callGemini(GEMINI_PRIMARY, imageBase64, prompt, true);

    if (response.status === 429) {
      functions.logger.warn('[GeminiProxy] 2.5-flash quota hit → fallback to 2.0-flash-lite');
      response = await callGemini(GEMINI_FALLBACK, imageBase64, prompt, false);
    }

    if (!response.ok) {
      const errBody = await response.text().catch(() => '');
      functions.logger.error(`[GeminiProxy] Gemini error ${response.status}: ${errBody.slice(0, 200)}`);
      throw new functions.https.HttpsError('internal', 'AI service temporarily unavailable.');
    }

    const json = await response.json();
    const text = json?.candidates?.[0]?.content?.parts?.[0]?.text?.trim();

    if (!text) {
      throw new functions.https.HttpsError('internal', 'Empty response from AI.');
    }

    return { result: text };
  });
