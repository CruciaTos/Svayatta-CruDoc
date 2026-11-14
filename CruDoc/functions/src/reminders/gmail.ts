import {defineSecret} from "firebase-functions/params";

/**
 * Plain-fetch Gmail client: code exchange, refresh, send, revoke.
 *
 * Only the gmail.send scope is ever requested, so CruDoc can send as the
 * clinic but never read its mail. No googleapis dependency: three REST calls.
 * Access tokens live for one sweep in memory and are never stored.
 */

export const gmailClientIdSecret = defineSecret("GMAIL_OAUTH_CLIENT_ID");
export const gmailClientSecretSecret = defineSecret("GMAIL_OAUTH_CLIENT_SECRET");

export const GMAIL_SEND_SCOPE = "https://www.googleapis.com/auth/gmail.send";

const TOKEN_URL = "https://oauth2.googleapis.com/token";
const REVOKE_URL = "https://oauth2.googleapis.com/revoke";
const SEND_URL = "https://gmail.googleapis.com/gmail/v1/users/me/messages/send";

export class GmailError extends Error {
  constructor(
    message: string,
    /** Short stable code for the log: invalid_grant, http_429, ... */
    public readonly code: string,
    /** True when the refresh token is dead and the clinic must reconnect. */
    public readonly reauth = false,
    /** True when retrying cannot help (bad address, no consent). */
    public readonly permanent = false,
  ) {
    super(message);
    this.name = "GmailError";
  }
}

function oauthClient(): {id: string; secret: string} {
  let id = "";
  let secret = "";
  try {
    id = gmailClientIdSecret.value().trim();
    secret = gmailClientSecretSecret.value().trim();
  } catch (_) {
    // Not bound to this function, or running locally.
  }
  id = id || (process.env.GMAIL_OAUTH_CLIENT_ID || "").trim();
  secret = secret || (process.env.GMAIL_OAUTH_CLIENT_SECRET || "").trim();
  if (!id || !secret) {
    throw new GmailError(
      "Gmail OAuth client is not configured.", "oauth_client_unset", false, true,
    );
  }
  return {id, secret};
}

export interface GmailTokens {
  refreshToken: string;
  accessToken: string;
  scope: string;
  /** The account's address, from the id_token Google returned. */
  email: string | null;
}

async function postForm(
  url: string,
  form: Record<string, string>,
): Promise<{status: number; json: Record<string, unknown>}> {
  const response = await fetch(url, {
    method: "POST",
    headers: {"Content-Type": "application/x-www-form-urlencoded"},
    body: new URLSearchParams(form).toString(),
  });
  let json: Record<string, unknown> = {};
  try {
    json = (await response.json()) as Record<string, unknown>;
  } catch (_) {
    // Empty or non-JSON body; the status carries the outcome.
  }
  return {status: response.status, json};
}

/** Address from an id_token. Not verified: it came straight from Google. */
function emailFromIdToken(idToken: unknown): string | null {
  if (typeof idToken !== "string") return null;
  const part = idToken.split(".")[1];
  if (!part) return null;
  try {
    const claims = JSON.parse(
      Buffer.from(part, "base64url").toString("utf8"),
    ) as {email?: unknown};
    return typeof claims.email === "string" ? claims.email.toLowerCase() : null;
  } catch (_) {
    return null;
  }
}

/** Exchanges the app's server auth code for a refresh token. */
export async function exchangeAuthCode(
  authCode: string,
  redirectUri: string,
): Promise<GmailTokens> {
  const {id, secret} = oauthClient();
  const form: Record<string, string> = {
    code: authCode,
    client_id: id,
    client_secret: secret,
    grant_type: "authorization_code",
  };
  // Google's mobile server auth codes take no redirect_uri; desktop loopback
  // codes must repeat the one the browser used.
  if (redirectUri) form.redirect_uri = redirectUri;

  const {status, json} = await postForm(TOKEN_URL, form);
  if (status !== 200) {
    const code = typeof json.error === "string" ? json.error : `http_${status}`;
    throw new GmailError(
      `Google rejected the sign-in (${code}).`, code, false, true,
    );
  }
  const refreshToken = typeof json.refresh_token === "string" ?
    json.refresh_token : "";
  const accessToken = typeof json.access_token === "string" ?
    json.access_token : "";
  const scope = typeof json.scope === "string" ? json.scope : "";
  if (!refreshToken) {
    throw new GmailError(
      "Google did not return a refresh token. Remove CruDoc from " +
      "myaccount.google.com/permissions and connect again.",
      "no_refresh_token", false, true,
    );
  }
  if (!scope.split(" ").includes(GMAIL_SEND_SCOPE)) {
    throw new GmailError(
      "Permission to send email was not granted.", "scope_missing", false, true,
    );
  }
  return {
    refreshToken, accessToken, scope, email: emailFromIdToken(json.id_token),
  };
}

/** A short-lived access token for one run. */
export async function refreshAccessToken(refreshToken: string): Promise<string> {
  const {id, secret} = oauthClient();
  const {status, json} = await postForm(TOKEN_URL, {
    refresh_token: refreshToken,
    client_id: id,
    client_secret: secret,
    grant_type: "refresh_token",
  });
  if (status === 200 && typeof json.access_token === "string") {
    return json.access_token;
  }
  const code = typeof json.error === "string" ? json.error : `http_${status}`;
  // invalid_grant: revoked, expired (unverified apps in Testing mode last 7
  // days) or password changed. Only reconnecting helps.
  const reauth = code === "invalid_grant";
  throw new GmailError(
    `Could not refresh Gmail access (${code}).`, code, reauth,
    reauth || code === "invalid_client",
  );
}

export async function revokeToken(token: string): Promise<void> {
  try {
    await postForm(REVOKE_URL, {token});
  } catch (_) {
    // Best effort: the stored copy is deleted regardless.
  }
}

function b64Lines(text: string): string {
  return (Buffer.from(text, "utf8").toString("base64").match(/.{1,76}/g) ?? [])
    .join("\r\n");
}

/** Headers must never carry a line break from patient or clinic text. */
function oneLine(value: string): string {
  return value.replace(/[\r\n]+/g, " ").trim();
}

export function isPlausibleEmail(value: string | null | undefined): boolean {
  return !!value && value.length <= 254 &&
    /^[^\s@<>",;]+@[^\s@<>",;]+\.[^\s@<>",;]+$/.test(value);
}

function buildMime(params: {
  to: string;
  subject: string;
  body: string;
  fromAddress: string;
}): string {
  const subject = oneLine(params.subject).slice(0, 200);
  return [
    `To: ${params.to}`,
    `Subject: =?UTF-8?B?${Buffer.from(subject, "utf8").toString("base64")}?=`,
    "MIME-Version: 1.0",
    "Content-Type: text/plain; charset=\"UTF-8\"",
    "Content-Transfer-Encoding: base64",
    "Auto-Submitted: auto-generated",
    `List-Unsubscribe: <mailto:${params.fromAddress}?subject=STOP>`,
    "",
    b64Lines(params.body),
  ].join("\r\n");
}

/** Sends one plain-text email as the connected account. */
export async function sendGmail(params: {
  accessToken: string;
  fromAddress: string;
  to: string;
  subject: string;
  body: string;
}): Promise<{messageId: string}> {
  if (!isPlausibleEmail(params.to)) {
    throw new GmailError("Invalid recipient address.", "bad_recipient", false, true);
  }
  const raw = Buffer.from(buildMime(params), "utf8").toString("base64url");
  const response = await fetch(SEND_URL, {
    method: "POST",
    headers: {
      "Authorization": `Bearer ${params.accessToken}`,
      "Content-Type": "application/json",
    },
    body: JSON.stringify({raw}),
  });
  if (response.ok) {
    const json = (await response.json()) as {id?: string};
    return {messageId: json.id || ""};
  }
  const code = `http_${response.status}`;
  if (response.status === 401) {
    throw new GmailError("Gmail rejected the access token.", code, true, true);
  }
  throw new GmailError(
    `Gmail send failed (${response.status}).`, code, false,
    response.status >= 400 && response.status < 500 && response.status !== 429,
  );
}
