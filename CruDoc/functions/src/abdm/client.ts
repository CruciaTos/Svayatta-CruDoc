import * as crypto from "crypto";
import {getAbdmConfig} from "./config";
import {encryptForAbdm} from "./crypto";

export class AbdmError extends Error {
  readonly status: number;
  readonly code: string;

  constructor(status: number, code: string, message: string) {
    super(message);
    this.name = "AbdmError";
    this.status = status;
    this.code = code;
  }
}

export function messageFrom(body: unknown): string {
  if (typeof body === "string") {
    return body.trim() || "ABDM request failed";
  }
  if (Array.isArray(body) && body.length > 0) {
    return messageFrom(body[0]);
  }
  if (body && typeof body === "object") {
    const obj = body as Record<string, unknown>;
    if (obj.error && typeof obj.error === "object") {
      const errObj = obj.error as Record<string, unknown>;
      if (typeof errObj.message === "string" && errObj.message.trim()) {
        return errObj.message.trim();
      }
    }
    if (typeof obj.message === "string" && obj.message.trim()) {
      return obj.message.trim();
    }
    if (typeof obj.detail === "string" && obj.detail.trim()) {
      return obj.detail.trim();
    }
    for (const val of Object.values(obj)) {
      if (typeof val === "string" && val.trim()) {
        return val.trim();
      }
    }
  }
  return "ABDM request failed";
}

function codeFrom(body: unknown, status: number): string {
  if (Array.isArray(body) && body.length > 0) {
    return codeFrom(body[0], status);
  }
  if (body && typeof body === "object") {
    const obj = body as Record<string, unknown>;
    if (obj.error && typeof obj.error === "object") {
      const errObj = obj.error as Record<string, unknown>;
      if (typeof errObj.code === "string" && errObj.code.trim()) {
        return errObj.code.trim();
      }
    }
    if (typeof obj.code === "string" && obj.code.trim()) {
      return obj.code.trim();
    }
  }
  return `HTTP_${status}`;
}

export interface AbdmClientOptions {
  fetchImpl?: typeof fetch;
  clientId: string;
  clientSecret: string;
  env?: string;
}

export interface AbdmPublicKey {
  publicKey: string;
  encryptionAlgorithm: string;
}

export interface AbdmClient {
  getGatewayToken(): Promise<string>;
  getPublicKey(): Promise<AbdmPublicKey>;
  encrypt(plain: string): Promise<string>;
  requestAbha<T = Record<string, unknown>>(
    method: "GET" | "POST",
    path: string,
    opts?: {
      body?: unknown;
      xToken?: string;
      headers?: Record<string, string>;
      skipAuth?: boolean;
    },
  ): Promise<T>;
  requestAbhaBinary(
    path: string,
    opts: {xToken: string},
  ): Promise<{contentType: string; base64: string}>;
  requestGateway<T = Record<string, unknown>>(
    method: "GET" | "POST" | "PATCH",
    path: string,
    body?: unknown,
  ): Promise<T>;
}

const KEY_TTL_MS = 60 * 60 * 1000;
const TOKEN_MARGIN_MS = 60 * 1000;
const REQUEST_TIMEOUT_MS = 15000;

export function createAbdmClient(opts: AbdmClientOptions): AbdmClient {
  const fetchImpl = opts.fetchImpl ?? fetch;
  const config = getAbdmConfig(opts.env);

  let cachedToken: {token: string; expiresAtMs: number} | null = null;
  let cachedKey: {key: AbdmPublicKey; expiresAtMs: number} | null = null;

  function baseHeaders(): Record<string, string> {
    return {
      "REQUEST-ID": crypto.randomUUID(),
      "TIMESTAMP": new Date().toISOString(),
      "Content-Type": "application/json",
    };
  }

  async function parseBody(res: Response): Promise<unknown> {
    const text = await res.text();
    if (!text) return {};
    try {
      return JSON.parse(text);
    } catch {
      return text;
    }
  }

  async function getGatewayToken(): Promise<string> {
    const now = Date.now();
    if (cachedToken && now < cachedToken.expiresAtMs - TOKEN_MARGIN_MS) {
      return cachedToken.token;
    }
    const res = await fetchImpl(`${config.gatewayBaseUrl}/gateway/v3/sessions`, {
      method: "POST",
      headers: {
        ...baseHeaders(),
        "X-CM-ID": config.cmId,
      },
      body: JSON.stringify({
        clientId: opts.clientId,
        clientSecret: opts.clientSecret,
        grantType: "client_credentials",
      }),
      signal: AbortSignal.timeout(REQUEST_TIMEOUT_MS),
    });
    const body = await parseBody(res);
    if (!res.ok) {
      throw new AbdmError(res.status, codeFrom(body, res.status), messageFrom(body));
    }
    const data = body as Record<string, unknown>;
    const token = String(data.accessToken ?? "");
    const expiresInSec = Number(data.expiresIn ?? 0);
    if (!token) {
      throw new AbdmError(502, "NO_TOKEN", "ABDM session did not return accessToken");
    }
    cachedToken = {
      token,
      expiresAtMs: now + Math.max(expiresInSec, 0) * 1000,
    };
    return token;
  }

  async function getPublicKey(): Promise<AbdmPublicKey> {
    const now = Date.now();
    if (cachedKey && now < cachedKey.expiresAtMs) {
      return cachedKey.key;
    }
    const token = await getGatewayToken();
    const res = await fetchImpl(`${config.abhaBaseUrl}/profile/public/certificate`, {
      method: "GET",
      headers: {
        ...baseHeaders(),
        "Authorization": `Bearer ${token}`,
      },
      signal: AbortSignal.timeout(REQUEST_TIMEOUT_MS),
    });
    const body = await parseBody(res);
    if (!res.ok) {
      throw new AbdmError(res.status, codeFrom(body, res.status), messageFrom(body));
    }
    const data = body as Record<string, unknown>;
    const publicKey = String(data.publicKey ?? "");
    const encryptionAlgorithm = String(data.encryptionAlgorithm ?? "");
    if (!publicKey || !encryptionAlgorithm) {
      throw new AbdmError(502, "NO_PUBLIC_KEY", "ABDM certificate response missing key");
    }
    const key = {publicKey, encryptionAlgorithm};
    cachedKey = {key, expiresAtMs: now + KEY_TTL_MS};
    return key;
  }

  async function encrypt(plain: string): Promise<string> {
    const {publicKey, encryptionAlgorithm} = await getPublicKey();
    return encryptForAbdm(plain, publicKey, encryptionAlgorithm);
  }

  async function requestAbha<T = Record<string, unknown>>(
    method: "GET" | "POST",
    path: string,
    reqOpts?: {
      body?: unknown;
      xToken?: string;
      headers?: Record<string, string>;
      skipAuth?: boolean;
    },
  ): Promise<T> {
    const headers: Record<string, string> = {
      ...baseHeaders(),
      ...(reqOpts?.headers ?? {}),
    };
    if (!reqOpts?.skipAuth) {
      headers["Authorization"] = `Bearer ${await getGatewayToken()}`;
    }
    if (reqOpts?.xToken) {
      headers["X-token"] = `Bearer ${reqOpts.xToken}`;
    }
    const res = await fetchImpl(`${config.abhaBaseUrl}${path}`, {
      method,
      headers,
      body: reqOpts?.body !== undefined ? JSON.stringify(reqOpts.body) : undefined,
      signal: AbortSignal.timeout(REQUEST_TIMEOUT_MS),
    });
    const body = await parseBody(res);
    if (!res.ok) {
      throw new AbdmError(res.status, codeFrom(body, res.status), messageFrom(body));
    }
    return body as T;
  }

  async function requestAbhaBinary(
    path: string,
    reqOpts: {xToken: string},
  ): Promise<{contentType: string; base64: string}> {
    const token = await getGatewayToken();
    const res = await fetchImpl(`${config.abhaBaseUrl}${path}`, {
      method: "GET",
      headers: {
        "REQUEST-ID": crypto.randomUUID(),
        "TIMESTAMP": new Date().toISOString(),
        "Authorization": `Bearer ${token}`,
        "X-token": `Bearer ${reqOpts.xToken}`,
      },
      signal: AbortSignal.timeout(REQUEST_TIMEOUT_MS),
    });
    if (!res.ok) {
      const body = await parseBody(res);
      throw new AbdmError(res.status, codeFrom(body, res.status), messageFrom(body));
    }
    const contentType = res.headers.get("content-type") ?? "image/png";
    const buf = Buffer.from(await res.arrayBuffer());
    return {
      contentType,
      base64: buf.toString("base64"),
    };
  }

  async function requestGateway<T = Record<string, unknown>>(
    method: "GET" | "POST" | "PATCH",
    path: string,
    body?: unknown,
  ): Promise<T> {
    const token = await getGatewayToken();
    const res = await fetchImpl(`${config.gatewayBaseUrl}${path}`, {
      method,
      headers: {
        ...baseHeaders(),
        "X-CM-ID": config.cmId,
        "Authorization": `Bearer ${token}`,
      },
      body: body !== undefined ? JSON.stringify(body) : undefined,
      signal: AbortSignal.timeout(REQUEST_TIMEOUT_MS),
    });
    const parsed = await parseBody(res);
    if (!res.ok) {
      throw new AbdmError(res.status, codeFrom(parsed, res.status), messageFrom(parsed));
    }
    return parsed as T;
  }

  return {
    getGatewayToken,
    getPublicKey,
    encrypt,
    requestAbha,
    requestAbhaBinary,
    requestGateway,
  };
}
