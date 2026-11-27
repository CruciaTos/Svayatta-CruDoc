/**
 * Registers the ABDM bridge URL for Scan and Share.
 * Usage: ABDM_CLIENT_ID=... ABDM_CLIENT_SECRET=... node scripts/abdm-set-bridge.js <url>
 */
const crypto = require("crypto");
const {getAbdmConfig} = require("../lib/abdm/config");

const url = (process.argv[2] || "").trim();
const clientId = (process.env.ABDM_CLIENT_ID || "").trim();
const clientSecret = (process.env.ABDM_CLIENT_SECRET || "").trim();

if (!url || !clientId || !clientSecret) {
  console.error("Usage: ABDM_CLIENT_ID=... ABDM_CLIENT_SECRET=... node scripts/abdm-set-bridge.js <url>");
  process.exit(1);
}

const config = getAbdmConfig();

function headers(extra = {}) {
  return {
    "REQUEST-ID": crypto.randomUUID(),
    "TIMESTAMP": new Date().toISOString(),
    "Content-Type": "application/json",
    "X-CM-ID": config.cmId,
    ...extra,
  };
}

(async () => {
  const sessRes = await fetch(`${config.gatewayBaseUrl}/gateway/v3/sessions`, {
    method: "POST",
    headers: headers(),
    body: JSON.stringify({clientId, clientSecret, grantType: "client_credentials"}),
    signal: AbortSignal.timeout(15000),
  });
  if (!sessRes.ok) {
    console.log(sessRes.status);
    process.exit(1);
  }
  const {accessToken} = await sessRes.json();
  const patchRes = await fetch(`${config.gatewayBaseUrl}/gateway/v3/bridge/url`, {
    method: "PATCH",
    headers: headers({"Authorization": `Bearer ${accessToken}`}),
    body: JSON.stringify({url}),
    signal: AbortSignal.timeout(15000),
  });
  console.log(patchRes.status);
  if (!patchRes.ok) process.exit(1);
})().catch(() => {
  process.exit(1);
});
