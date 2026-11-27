import * as crypto from "crypto";
import * as admin from "firebase-admin";
import {FieldValue, Timestamp} from "firebase-admin/firestore";
import {CallableRequest, HttpsError, onCall} from "firebase-functions/v2/https";
import {loadCaller, requirePerm} from "../clinic";
import {rejectSuperAdmin} from "../clinic-app-guard";
import {getPepper, patientKekPepperSecret} from "../crypto/patientCipher";
import {AbdmClient, AbdmError, createAbdmClient} from "./client";
import {abdmClientId, abdmClientSecret, getAbdmConfig} from "./config";
import {open, seal} from "./crypto";

const FLOW_TTL_MS = 30 * 60 * 1000;
const OTP_WINDOW_MS = 30 * 60 * 1000;
const OTP_RESEND_WAIT_MS = 60 * 1000;
const MAX_OTP_SENDS_PER_ID = 3;
const MAX_OTP_SENDS_PER_USER = 30;
const MAX_SEARCHES_PER_USER = 30;

export async function assertEntitledAccount(
  db: FirebaseFirestore.Firestore,
  clinicId: string,
): Promise<void> {
  const d = (await db.collection("users").doc(clinicId).get()).data();
  const status = String(d?.status ?? "").toLowerCase();
  const entitled = Boolean(
    d &&
    d.isDeleted !== true &&
    status !== "suspended" &&
    (d.expiresDate || d.status || d.trialStartedAt),
  );
  if (!entitled) {
    throw new HttpsError(
      "failed-precondition",
      "Finish setting up your CruDoc account before using ABHA.",
    );
  }
}

async function consumeSearchQuota(
  db: FirebaseFirestore.Firestore,
  clinicId: string,
  uid: string,
): Promise<void> {
  const ref = db.collection("abdmOtpLimits").doc(`search_${hmacOf(clinicId, uid)}`);
  await db.runTransaction(async (tx) => {
    const snap = await tx.get(ref);
    const now = Date.now();
    const d = snap.data();
    const fresh = !d || now - Number(d.windowStart ?? 0) > OTP_WINDOW_MS;
    const count = fresh ? 0 : Number(d.count ?? 0);
    if (count >= MAX_SEARCHES_PER_USER) {
      throw new HttpsError(
        "resource-exhausted",
        "Too many searches. Try again after 30 minutes.",
      );
    }
    tx.set(ref, {windowStart: fresh ? now : d.windowStart, count: count + 1, lastAt: now});
  });
}

export interface AbhaProfileReply {
  abhaNumber: string;
  abhaAddress: string;
  name: string;
  gender: string;
  dateOfBirth: string | null;
  mobile: string;
  kycVerified: boolean;
}

export function hmacOf(clinicId: string, value: string): string {
  return crypto.createHmac("sha256", getPepper())
    .update(`abha:${clinicId}:${value}`)
    .digest("hex");
}

function digitsOnly(value: string): string {
  return value.replace(/\D/g, "");
}

function formatAbhaNumber(digits: string): string {
  return `${digits.slice(0, 2)}-${digits.slice(2, 6)}-${digits.slice(6, 10)}-${digits.slice(10, 14)}`;
}

function pad2(val: unknown): string | null {
  const n = Number(String(val ?? "").trim());
  if (!Number.isInteger(n) || n <= 0) return null;
  return String(n).padStart(2, "0");
}

function parseDob(raw: Record<string, unknown>): string | null {
  const yearStr = String(raw.yearOfBirth ?? "").trim();
  const monthStr = pad2(raw.monthOfBirth);
  const dayStr = pad2(raw.dayOfBirth);
  if (/^\d{4}$/.test(yearStr) && monthStr && dayStr) {
    return `${yearStr}-${monthStr}-${dayStr}`;
  }
  const direct = String(raw.dateOfBirth ?? raw.dob ?? "").trim();
  if (/^\d{4}-\d{2}-\d{2}$/.test(direct)) {
    return direct;
  }
  const dmy = direct.match(/^(\d{2})-(\d{2})-(\d{4})$/);
  if (dmy) {
    return `${dmy[3]}-${dmy[2]}-${dmy[1]}`;
  }
  return null;
}

export function toProfile(raw: Record<string, unknown>): AbhaProfileReply {
  const phrList = Array.isArray(raw.phrAddress) ? raw.phrAddress : [];
  const firstPhr = phrList.length > 0 ? String(phrList[0] ?? "") : "";
  const abhaAddress = String(raw.preferredAbhaAddress ?? raw.abhaAddress ?? firstPhr).trim();
  const abhaNumber = String(raw.ABHANumber ?? raw.abhaNumber ?? "").trim();
  const builtName = [raw.firstName, raw.middleName, raw.lastName]
    .map((x) => String(x ?? "").trim())
    .filter(Boolean)
    .join(" ");
  const name = String(raw.name ?? raw.fullName ?? builtName).trim();
  const gender = String(raw.gender ?? "").trim();
  const mobile = String(raw.mobile ?? raw.mobileNumber ?? "").trim();
  return {
    abhaNumber,
    abhaAddress,
    name,
    gender,
    dateOfBirth: parseDob(raw),
    mobile,
    kycVerified: Boolean(raw.kycVerified),
  };
}

function readMillis(ts: unknown): number {
  if (!ts) return 0;
  if (typeof ts === "number") return ts;
  if (typeof (ts as {toMillis?: () => number}).toMillis === "function") {
    return (ts as {toMillis: () => number}).toMillis();
  }
  return 0;
}

async function loadFlow(
  db: FirebaseFirestore.Firestore,
  flowId: string,
  clinicId: string,
  uid: string,
): Promise<{ref: FirebaseFirestore.DocumentReference; data: Record<string, unknown>}> {
  if (!flowId) {
    throw new HttpsError("invalid-argument", "flowId is required.");
  }
  const ref = db.collection("abdmFlows").doc(flowId);
  const snap = await ref.get();
  if (!snap.exists) {
    throw new HttpsError("failed-precondition", "ABDM session expired. Please start again.");
  }
  const data = snap.data() ?? {};
  if (data.clinicId !== clinicId || data.uid !== uid) {
    throw new HttpsError("permission-denied", "ABDM session does not belong to this user.");
  }
  if (readMillis(data.expiresAt) <= Date.now()) {
    throw new HttpsError("failed-precondition", "ABDM session expired. Please start again.");
  }
  return {ref, data};
}

async function consumeOtpQuota(
  db: FirebaseFirestore.Firestore,
  clinicId: string,
  uid: string,
  identifierKey: string,
): Promise<number> {
  const idRef = db.collection("abdmOtpLimits").doc(hmacOf(clinicId, identifierKey));
  const userRef = db.collection("abdmOtpLimits").doc(`user_${hmacOf(clinicId, uid)}`);

  return db.runTransaction(async (tx) => {
    const now = Date.now();
    const [idSnap, userSnap] = await Promise.all([tx.get(idRef), tx.get(userRef)]);

    const u = userSnap.data();
    const uFresh = !u || now - Number(u.windowStart ?? 0) > OTP_WINDOW_MS;
    const uCount = uFresh ? 0 : Number(u.count ?? 0);
    if (uCount >= MAX_OTP_SENDS_PER_USER) {
      throw new HttpsError(
        "resource-exhausted",
        "Maximum OTP resend attempts reached. Please try again after 30 mins",
      );
    }

    const d = idSnap.data();
    const fresh = !d || now - Number(d.windowStart ?? 0) > OTP_WINDOW_MS;
    const count = fresh ? 0 : Number(d.count ?? 0);
    if (count >= MAX_OTP_SENDS_PER_ID) {
      throw new HttpsError(
        "resource-exhausted",
        "Maximum OTP resend attempts reached. Please try again after 30 mins",
      );
    }
    if (!fresh && now - Number(d.lastAt ?? 0) < OTP_RESEND_WAIT_MS) {
      throw new HttpsError("failed-precondition", "Wait 60 seconds before resending.");
    }

    tx.set(idRef, {windowStart: fresh ? now : d.windowStart, count: count + 1, lastAt: now});
    tx.set(userRef, {windowStart: uFresh ? now : u.windowStart, count: uCount + 1, lastAt: now});
    return 2 - count;
  });
}

async function findExistingLink(
  db: FirebaseFirestore.Firestore,
  clinicId: string,
  abhaNumber: string,
): Promise<string | null> {
  const digits = digitsOnly(abhaNumber);
  if (digits.length !== 14) return null;
  const hash = hmacOf(clinicId, digits);
  const snap = await db.collection("abhaLinks").doc(`${clinicId}_${hash}`).get();
  if (!snap.exists) return null;
  const patientId = String(snap.data()?.patientId ?? "");
  if (!patientId) return null;
  const pSnap = await db.collection("patients").doc(patientId).get();
  if (pSnap.exists && pSnap.data()?.isActive === false) return null;
  return patientId;
}

function validateMobile(raw: string): string {
  const d = digitsOnly(raw);
  if (d.length !== 10) {
    throw new HttpsError("invalid-argument", "Please enter a valid mobile number.");
  }
  return d;
}

function validateAadhaar(raw: string): string {
  const d = digitsOnly(raw);
  if (d.length !== 12) {
    throw new HttpsError("invalid-argument", "Aadhaar Number is not valid");
  }
  return d;
}

function validateAbhaNumber(raw: string): string {
  const d = digitsOnly(raw);
  if (d.length !== 14) {
    throw new HttpsError("invalid-argument", "Please enter a valid 14-digit ABHA number.");
  }
  return formatAbhaNumber(d);
}

function validateOtp(raw: string): string {
  const d = digitsOnly(raw);
  if (d.length !== 6) {
    throw new HttpsError("invalid-argument", "OTP must be 6 digits.");
  }
  return d;
}

/**
 * ABDM can answer a wrong OTP with HTTP 200 and `authResult` other than
 * success. Pass [userToken] where a successful check must also return one.
 */
function assertAuthSucceeded(res: Record<string, unknown>, userToken?: string): void {
  const result = String(res.authResult ?? "").toLowerCase();
  if ((result && result !== "success") || userToken === "") {
    throw new HttpsError("failed-precondition",
      String(res.message ?? "Incorrect OTP. Please try again."));
  }
}

export async function handleAbdmAction(
  db: FirebaseFirestore.Firestore,
  client: AbdmClient,
  uid: string,
  clinicId: string,
  data: Record<string, unknown>,
): Promise<Record<string, unknown>> {
  const action = String(data.action ?? "");
  const pepper = getPepper();
  const expiresAt = Timestamp.fromMillis(Date.now() + FLOW_TTL_MS);

  try {
    switch (action) {
    case "searchMobile": {
      const mobile = validateMobile(String(data.mobile ?? ""));
      await consumeSearchQuota(db, clinicId, uid);
      const encMobile = await client.encrypt(mobile);
      let reply: unknown;
      try {
        reply = await client.requestAbha<unknown>("POST", "/profile/account/abha/search", {
          body: {scope: ["search-abha"], mobile: encMobile},
        });
      } catch (err) {
        if (err instanceof AbdmError && (err.status === 404 || /not found/i.test(err.message))) {
          return {flowId: null, accounts: []};
        }
        throw err;
      }
      const first = Array.isArray(reply) ? (reply[0] ?? {}) : (reply ?? {});
      const obj = first as Record<string, unknown>;
      const txnId = String(obj.txnId ?? "");
      const rawList = Array.isArray(obj.ABHA) ? obj.ABHA : [];
      const accounts = rawList.map((item) => {
        const a = item as Record<string, unknown>;
        return {
          index: a.index,
          name: String(a.name ?? ""),
          gender: String(a.gender ?? ""),
          abhaNumberMasked: String(a.ABHANumber ?? ""),
        };
      });
      if (accounts.length === 0) {
        return {flowId: null, accounts: []};
      }
      const flowId = crypto.randomUUID();
      await db.collection("abdmFlows").doc(flowId).set({
        clinicId,
        uid,
        kind: "mobileSearch",
        mobileHash: hmacOf(clinicId, mobile),
        scope: ["abha-login", "mobile-verify"],
        txnId,
        xToken: "",
        verified: false,
        abhaNumberHash: "",
        expiresAt,
      });
      return {flowId, accounts};
    }

    case "searchAddress": {
      const abhaAddress = String(data.abhaAddress ?? "").trim();
      if (!abhaAddress) {
        throw new HttpsError("invalid-argument", "ABHA address is required.");
      }
      await consumeSearchQuota(db, clinicId, uid);
      const reply = await client.requestAbha<Record<string, unknown>>(
        "POST",
        "/phr/web/login/abha/search",
        {
          body: {abhaAddress},
          skipAuth: true,
        },
      );
      const authMethods = Array.isArray(reply.authMethods) ?
        reply.authMethods.map((m) => String(m)) : [];
      const blocked = new Set(
        Array.isArray(reply.blockedAuthMethods) ?
          reply.blockedAuthMethods.map((m) => String(m)) : [],
      );
      const methods: string[] = [];
      for (const m of authMethods) {
        if (blocked.has(m)) continue;
        if (m === "MOBILE_OTP") methods.push("mobile");
        if (m === "AADHAAR_OTP") methods.push("aadhaar");
      }
      const flowId = crypto.randomUUID();
      await db.collection("abdmFlows").doc(flowId).set({
        clinicId,
        uid,
        kind: "addressSearch",
        scope: [],
        txnId: "",
        xToken: "",
        verified: false,
        abhaNumberHash: "",
        expiresAt,
      });
      return {
        flowId,
        methods,
        name: String(reply.fullName ?? reply.name ?? ""),
        mobileMasked: String(reply.mobile ?? reply.mobileMasked ?? ""),
      };
    }

    case "sendOtp": {
      const kind = String(data.kind ?? "");
      const channel = String(data.channel ?? "");
      const identifier = String(data.identifier ?? "").trim();
      const existingFlowId = data.flowId ? String(data.flowId) : "";

      let existingFlow: {
        ref: FirebaseFirestore.DocumentReference;
        data: Record<string, unknown>;
      } | null = null;
      if (existingFlowId) {
        existingFlow = await loadFlow(db, existingFlowId, clinicId, uid);
      }

      // Only a resend inside an enrolment flow may skip consent: any other
      // flow id (a search, a login) has no consent record behind it.
      const startsEnrolment = kind === "create" && existingFlow?.data.kind !== "create";
      if (startsEnrolment && data.consent !== true) {
        throw new HttpsError("failed-precondition", "Patient consent is required.");
      }

      // Reject bad input before it uses up one of the three sends.
      if (kind === "create" || kind === "aadhaar") validateAadhaar(identifier);
      if (kind === "abhaNumber") validateAbhaNumber(identifier);
      if (kind === "commMobile") validateMobile(identifier);

      let limitKey = `${kind}:${identifier.toLowerCase()}`;
      if (kind === "index") {
        if (!existingFlow) {
          throw new HttpsError("invalid-argument", "flowId is required for index OTP.");
        }
        // Keyed by the searched mobile, so searching again cannot reset it.
        const searched = String(existingFlow.data.mobileHash ?? existingFlowId);
        limitKey = `index:${searched}:${String(data.index ?? "")}`;
      } else if (kind === "abhaNumber") {
        limitKey = `abhaNumber:${digitsOnly(identifier)}`;
      } else if (kind === "aadhaar" || kind === "create") {
        limitKey = `${kind}:${digitsOnly(identifier)}`;
      } else if (kind === "commMobile") {
        limitKey = `commMobile:${digitsOnly(identifier)}`;
      }

      const resendsLeft = await consumeOtpQuota(db, clinicId, uid, limitKey);

      let txnId = "";
      let message = "OTP sent";
      let scope: string[] = [];
      let nextKind = kind;

      if (kind === "create") {
        const aadhaar = validateAadhaar(identifier);
        scope = ["abha-enrol"];
        const res = await client.requestAbha<Record<string, unknown>>(
          "POST",
          "/enrollment/request/otp",
          {
            body: {
              scope,
              loginHint: "aadhaar",
              loginId: await client.encrypt(aadhaar),
              otpSystem: "aadhaar",
            },
          },
        );
        txnId = String(res.txnId ?? "");
        message = String(res.message ?? message);
      } else if (kind === "commMobile") {
        if (!existingFlow) {
          throw new HttpsError("invalid-argument", "flowId is required.");
        }
        const mobile = validateMobile(identifier);
        scope = ["abha-enrol", "mobile-verify"];
        const res = await client.requestAbha<Record<string, unknown>>(
          "POST",
          "/enrollment/request/otp",
          {
            body: {
              txnId: String(existingFlow.data.txnId ?? ""),
              scope,
              loginHint: "mobile",
              loginId: await client.encrypt(mobile),
              otpSystem: "abdm",
            },
          },
        );
        txnId = String(res.txnId ?? "");
        message = String(res.message ?? message);
      } else if (kind === "abhaNumber") {
        const formatted = validateAbhaNumber(identifier);
        const isMobile = channel === "mobile";
        scope = isMobile ? ["abha-login", "mobile-verify"] : ["abha-login", "aadhaar-verify"];
        const res = await client.requestAbha<Record<string, unknown>>(
          "POST",
          "/profile/login/request/otp",
          {
            body: {
              scope,
              loginHint: "abha-number",
              loginId: await client.encrypt(formatted),
              otpSystem: isMobile ? "abdm" : "aadhaar",
            },
          },
        );
        txnId = String(res.txnId ?? "");
        message = String(res.message ?? message);
      } else if (kind === "aadhaar") {
        const aadhaar = validateAadhaar(identifier);
        scope = ["abha-login", "aadhaar-verify"];
        const res = await client.requestAbha<Record<string, unknown>>(
          "POST",
          "/profile/login/request/otp",
          {
            body: {
              scope,
              loginHint: "aadhaar",
              loginId: await client.encrypt(aadhaar),
              otpSystem: "aadhaar",
            },
          },
        );
        txnId = String(res.txnId ?? "");
        message = String(res.message ?? message);
      } else if (kind === "index") {
        if (!existingFlow) {
          throw new HttpsError("invalid-argument", "flowId is required.");
        }
        const indexVal = String(data.index ?? "").trim();
        if (!indexVal) {
          throw new HttpsError("invalid-argument", "index is required.");
        }
        scope = ["abha-login", "mobile-verify"];
        const res = await client.requestAbha<Record<string, unknown>>(
          "POST",
          "/profile/login/request/otp",
          {
            body: {
              scope: ["abha-login", "search-abha", "mobile-verify"],
              loginHint: "index",
              loginId: await client.encrypt(indexVal),
              otpSystem: "abdm",
              txnId: String(existingFlow.data.txnId ?? ""),
            },
          },
        );
        txnId = String(res.txnId ?? "");
        message = String(res.message ?? message);
      } else if (kind === "address") {
        if (!identifier) {
          throw new HttpsError("invalid-argument", "ABHA address is required.");
        }
        const isMobile = channel === "mobile";
        const v = isMobile ? "mobile-verify" : "aadhaar-verify";
        const s = isMobile ? "abdm" : "aadhaar";
        scope = ["abha-address-login", v];
        const res = await client.requestAbha<Record<string, unknown>>(
          "POST",
          "/phr/web/login/abha/request/otp",
          {
            body: {
              scope,
              loginHint: "abha-address",
              loginId: await client.encrypt(identifier),
              otpSystem: s,
            },
          },
        );
        txnId = String(res.txnId ?? "");
        message = String(res.message ?? message);
        nextKind = "address";
      } else {
        throw new HttpsError("invalid-argument", `Unsupported sendOtp kind: ${kind}`);
      }

      const flowId = existingFlowId || crypto.randomUUID();
      if (existingFlow) {
        // A new login on an old flow must not inherit the earlier person's
        // verification. The mobile check belongs to the same enrolment.
        await existingFlow.ref.update({
          kind: nextKind,
          scope,
          txnId,
          expiresAt,
          ...(kind === "commMobile" ? {} : {verified: false, xToken: "", abhaNumberHash: ""}),
        });
      } else {
        await db.collection("abdmFlows").doc(flowId).set({
          clinicId,
          uid,
          kind: nextKind,
          scope,
          txnId,
          xToken: "",
          verified: false,
          abhaNumberHash: "",
          expiresAt,
        });
      }
      if (startsEnrolment) {
        await db.collection("abdmConsents").doc(flowId).set({
          clinicId,
          uid,
          code: "abha-enrollment",
          version: "1.4",
          agreedAt: FieldValue.serverTimestamp(),
        });
      }
      return {flowId, message, resendsLeft};
    }

    case "verifyOtp": {
      const flowId = String(data.flowId ?? "");
      const otp = validateOtp(String(data.otp ?? ""));
      const {ref, data: flow} = await loadFlow(db, flowId, clinicId, uid);
      const kind = String(flow.kind ?? "");
      const txnId = String(flow.txnId ?? "");
      const encOtp = await client.encrypt(otp);

      if (kind === "create") {
        const mobile = validateMobile(String(data.mobile ?? ""));
        const res = await client.requestAbha<Record<string, unknown>>(
          "POST",
          "/enrollment/enrol/byAadhaar",
          {
            body: {
              authData: {
                authMethods: ["otp"],
                otp: {txnId, otpValue: encOtp, mobile},
              },
              consent: {code: "abha-enrollment", version: "1.4"},
            },
          },
        );
        const tokens = (res.tokens ?? {}) as Record<string, unknown>;
        const xToken = String(tokens.token ?? "");
        const rawProfile = (res.ABHAProfile ?? {}) as Record<string, unknown>;
        const profile = toProfile(rawProfile);
        if (!profile.abhaNumber) {
          throw new HttpsError("failed-precondition",
            String(res.message ?? "ABHA could not be created. Please try again."));
        }
        const rawMobile = digitsOnly(String(rawProfile.mobile ?? ""));
        const needsMobileOtp = !rawMobile || rawMobile !== mobile;
        const abhaNumberHash = hmacOf(clinicId, digitsOnly(profile.abhaNumber));

        await ref.update({
          txnId: String(res.txnId ?? txnId),
          xToken: xToken ? seal(xToken, pepper) : "",
          verified: true,
          abhaNumberHash,
          expiresAt,
        });
        // So the consent says whose it was even if no patient is ever linked.
        await db.collection("abdmConsents").doc(flowId).update({abhaNumberHash});

        const existingPatientId = await findExistingLink(db, clinicId, profile.abhaNumber);
        return {
          profile,
          isNew: Boolean(res.isNew),
          needsMobileOtp,
          existingPatientId,
        };
      }

      if (kind === "commMobile") {
        const check = await client.requestAbha<Record<string, unknown>>(
          "POST",
          "/enrollment/auth/byAbdm",
          {
            body: {
              scope: ["abha-enrol", "mobile-verify"],
              authData: {authMethods: ["otp"], otp: {txnId, otpValue: encOtp}},
            },
          },
        );
        assertAuthSucceeded(check);
        const xToken = open(String(flow.xToken ?? ""), pepper);
        const account = await client.requestAbha<Record<string, unknown>>("GET", "/profile/account", {
          xToken,
        });
        const profile = toProfile(account);
        const existingPatientId = await findExistingLink(db, clinicId, profile.abhaNumber);
        return {profile, existingPatientId};
      }

      if (kind === "address") {
        const scope = Array.isArray(flow.scope) ? flow.scope.map((s) => String(s)) : [];
        const res = await client.requestAbha<Record<string, unknown>>(
          "POST",
          "/phr/web/login/abha/verify",
          {
            body: {
              scope,
              authData: {authMethods: ["otp"], otp: {txnId, otpValue: encOtp}},
            },
          },
        );
        const tokens = (res.tokens ?? {}) as Record<string, unknown>;
        const xToken = String(tokens.token ?? res.token ?? "");
        assertAuthSucceeded(res, xToken);
        const profileData = await client.requestAbha<Record<string, unknown>>(
          "GET",
          "/phr/web/login/profile/abha-profile",
          {xToken},
        );
        const profile = toProfile(profileData);
        const abhaNumberHash = profile.abhaNumber ?
          hmacOf(clinicId, digitsOnly(profile.abhaNumber)) : "";
        await ref.update({
          xToken: xToken ? seal(xToken, pepper) : "",
          verified: true,
          abhaNumberHash,
          expiresAt,
        });
        const existingPatientId = await findExistingLink(db, clinicId, profile.abhaNumber);
        return {profile, existingPatientId};
      }

      // abhaNumber, aadhaar, index
      const scope = Array.isArray(flow.scope) ? flow.scope.map((s) => String(s)) : [];
      const res = await client.requestAbha<Record<string, unknown>>(
        "POST",
        "/profile/login/verify",
        {
          body: {
            scope,
            authData: {authMethods: ["otp"], otp: {txnId, otpValue: encOtp}},
          },
        },
      );
      const xToken = String(res.token ?? ((res.tokens as Record<string, unknown> | undefined)?.token ?? ""));
      assertAuthSucceeded(res, xToken);
      const account = await client.requestAbha<Record<string, unknown>>("GET", "/profile/account", {
        xToken,
      });
      const profile = toProfile(account);
      const abhaNumberHash = profile.abhaNumber ?
        hmacOf(clinicId, digitsOnly(profile.abhaNumber)) : "";
      await ref.update({
        xToken: xToken ? seal(xToken, pepper) : "",
        verified: true,
        abhaNumberHash,
        expiresAt,
      });
      const existingPatientId = await findExistingLink(db, clinicId, profile.abhaNumber);
      return {profile, existingPatientId};
    }

    case "suggestAddress": {
      const flowId = String(data.flowId ?? "");
      const {data: flow} = await loadFlow(db, flowId, clinicId, uid);
      const res = await client.requestAbha<Record<string, unknown>>(
        "GET",
        "/enrollment/enrol/suggestion",
        {
          headers: {TRANSACTION_ID: String(flow.txnId ?? "")},
        },
      );
      const addresses = Array.isArray(res.abhaAddressList) ?
        res.abhaAddressList.map((a) => String(a)) : [];
      return {addresses};
    }

    case "setAddress": {
      const flowId = String(data.flowId ?? "");
      const rawAddress = String(data.abhaAddress ?? "").trim().replace(/@.*$/, "");
      if (!rawAddress) {
        throw new HttpsError("invalid-argument", "ABHA address is required.");
      }
      const {data: flow} = await loadFlow(db, flowId, clinicId, uid);
      const res = await client.requestAbha<Record<string, unknown>>(
        "POST",
        "/enrollment/enrol/abha-address",
        {
          body: {
            txnId: String(flow.txnId ?? ""),
            abhaAddress: rawAddress,
            preferred: 1,
          },
        },
      );
      return {abhaAddress: String(res.preferredAbhaAddress ?? rawAddress)};
    }

    case "card": {
      const flowId = String(data.flowId ?? "");
      const {data: flow} = await loadFlow(db, flowId, clinicId, uid);
      if (flow.verified !== true || !flow.xToken) {
        throw new HttpsError("failed-precondition", "ABHA verification is required.");
      }
      const xToken = open(String(flow.xToken), pepper);
      const path = flow.kind === "address" ?
        "/phr/web/login/profile/abha/phr-card" :
        "/profile/account/abha-card";
      return await client.requestAbhaBinary(path, {xToken});
    }

    case "link": {
      const flowId = String(data.flowId ?? "");
      const patientId = String(data.patientId ?? "").trim();
      if (!patientId) {
        throw new HttpsError("invalid-argument", "patientId is required.");
      }
      const {data: flow} = await loadFlow(db, flowId, clinicId, uid);
      const abhaNumberHash = String(flow.abhaNumberHash ?? "");
      if (flow.verified !== true || !abhaNumberHash) {
        throw new HttpsError("failed-precondition", "ABHA verification is required before linking.");
      }
      const linkRef = db.collection("abhaLinks").doc(`${clinicId}_${abhaNumberHash}`);
      const consentRef = db.collection("abdmConsents").doc(flowId);

      return await db.runTransaction(async (tx) => {
        // Firestore requires every read before the first write.
        const linkSnap = await tx.get(linkRef);
        const consentSnap = await tx.get(consentRef);
        const patientSnap = await tx.get(db.collection("patients").doc(patientId));
        if (patientSnap.exists && patientSnap.data()?.doctorId !== clinicId) {
          throw new HttpsError("permission-denied", "That patient belongs to another clinic.");
        }
        if (linkSnap.exists) {
          const existingId = String(linkSnap.data()?.patientId ?? "");
          if (existingId && existingId !== patientId) {
            const existingPatientSnap = await tx.get(db.collection("patients").doc(existingId));
            if (!existingPatientSnap.exists || existingPatientSnap.data()?.isActive !== false) {
              return {linked: false, existingPatientId: existingId};
            }
          }
        }
        tx.set(linkRef, {
          clinicId,
          patientId,
          linkedBy: uid,
          linkedAt: Timestamp.now(),
        });
        if (consentSnap.exists) {
          tx.update(consentRef, {patientId});
        }
        return {linked: true};
      });
    }

    case "facility": {
      const snap = await db.collection("abdmFacilities")
        .where("clinicId", "==", clinicId)
        .where("approved", "==", true)
        .limit(1)
        .get();
      if (snap.empty) {
        return {hipId: null};
      }
      return {
        hipId: snap.docs[0].id,
        qrBaseUrl: getAbdmConfig().qrBaseUrl,
      };
    }

    default:
      throw new HttpsError("invalid-argument", `Unknown ABDM action: ${action}`);
    }
  } catch (err) {
    if (err instanceof HttpsError) throw err;
    if (err instanceof AbdmError) {
      throw new HttpsError("failed-precondition", err.message);
    }
    throw new HttpsError("internal", "ABDM request failed.");
  }
}

/** One client per instance, so the gateway token and public key stay cached. */
let cachedClient: {key: string; client: AbdmClient} | null = null;

function sharedClient(clientId: string, clientSecret: string): AbdmClient {
  const key = `${clientId}:${clientSecret}`;
  if (cachedClient?.key !== key) {
    cachedClient = {key, client: createAbdmClient({clientId, clientSecret})};
  }
  return cachedClient.client;
}

export const abdm = onCall(
  {
    region: "asia-south1",
    maxInstances: 10,
    secrets: [abdmClientId, abdmClientSecret, patientKekPepperSecret],
  },
  async (request: CallableRequest) => {
    rejectSuperAdmin(request);
    const clinicId = String(request.data?.clinicId ?? "");
    const caller = await loadCaller(request, clinicId);
    requirePerm(caller, "patients.edit");
    const db = admin.firestore();
    await assertEntitledAccount(db, clinicId);

    return handleAbdmAction(
      db,
      sharedClient(abdmClientId.value(), abdmClientSecret.value()),
      caller.uid,
      clinicId,
      (request.data ?? {}) as Record<string, unknown>,
    );
  },
);
