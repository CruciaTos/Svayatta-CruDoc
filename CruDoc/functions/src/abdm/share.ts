import * as crypto from "crypto";
import * as admin from "firebase-admin";
import {FieldValue, Timestamp} from "firebase-admin/firestore";
import {onDocumentCreated} from "firebase-functions/v2/firestore";
import {onRequest} from "firebase-functions/v2/https";
import {
  decryptField,
  encryptField,
  getPepper,
  PatientKeyring,
  patientKekPepperSecret,
  phoneIndexOf,
} from "../crypto/patientCipher";
import {AbdmClient, createAbdmClient} from "./client";
import {abdmCallbackKey, abdmClientId, abdmClientSecret} from "./config";
import {open, seal} from "./crypto";
import {hmacOf} from "./index";

const SHARE_RATE_WINDOW_MS = 10 * 60 * 1000;
const SHARE_RATE_MAX = 120;
const SHARE_TTL_MS = 24 * 60 * 60 * 1000;

/** A refusal whose message is safe to send to ABDM and store. */
class ShareRefused extends Error {}

let sharedClient: AbdmClient | null = null;
let sharedKeyring: PatientKeyring | null = null;

function getSharedClient(): AbdmClient {
  sharedClient ??= createAbdmClient({
    clientId: abdmClientId.value(),
    clientSecret: abdmClientSecret.value(),
  });
  return sharedClient;
}

function getSharedKeyring(db: FirebaseFirestore.Firestore): PatientKeyring {
  sharedKeyring ??= new PatientKeyring(db);
  return sharedKeyring;
}

/**
 * Verifies the ABDM callback Authorization Bearer token.
 * TODO(onboarding): verify ABDM callback JWT signature once NHA publishes keys.
 */
export function verifyAbdmToken(authHeader: string | undefined): boolean {
  if (!authHeader || typeof authHeader !== "string") return false;
  const match = authHeader.match(/^Bearer\s+(\S+)$/i);
  return Boolean(match && match[1].length > 0);
}

function timingSafeMatch(a: string, b: string): boolean {
  const bufA = Buffer.from(a, "utf8");
  const bufB = Buffer.from(b, "utf8");
  if (bufA.length !== bufB.length) return false;
  return crypto.timingSafeEqual(bufA, bufB);
}

function digitsOnly(value: string): string {
  return value.replace(/\D/g, "");
}

function formatAbhaNumber(digits: string): string {
  return `${digits.slice(0, 2)}-${digits.slice(2, 6)}-${digits.slice(6, 10)}-${digits.slice(10, 14)}`;
}

function mapGender(raw: unknown): string {
  switch (String(raw ?? "").trim().toUpperCase()) {
  case "M":
    return "Male";
  case "F":
    return "Female";
  case "O":
  case "D":
  case "T":
  case "U":
    return "Other";
  default:
    return "";
  }
}

function parseShareDob(patient: Record<string, unknown>): Date | null {
  const y = Number(String(patient.yearOfBirth ?? "").trim());
  const m = Number(String(patient.monthOfBirth ?? "").trim());
  const d = Number(String(patient.dayOfBirth ?? "").trim());
  if (
    !Number.isInteger(y) || y < 1900 || y > 2100 ||
    !Number.isInteger(m) || m < 1 || m > 12 ||
    !Number.isInteger(d) || d < 1 || d > 31
  ) {
    return null;
  }
  const dt = new Date(Date.UTC(y, m - 1, d));
  if (dt.getUTCFullYear() !== y || dt.getUTCMonth() !== m - 1 || dt.getUTCDate() !== d) {
    return null;
  }
  return dt;
}

export function queueDateKeyKolkata(now: Date = new Date()): string {
  return new Intl.DateTimeFormat("en-CA", {
    timeZone: "Asia/Kolkata",
    year: "numeric",
    month: "2-digit",
    day: "2-digit",
  }).format(now);
}

function readMillis(ts: unknown): number | null {
  if (!ts) return null;
  if (typeof ts === "number") return ts;
  if (ts instanceof Date) return ts.getTime();
  if (typeof (ts as {toMillis?: () => number}).toMillis === "function") {
    return (ts as {toMillis: () => number}).toMillis();
  }
  return null;
}

function planAllowsQueue(plan: Record<string, unknown> | undefined): boolean {
  if (!plan) return true;
  const mods = Array.isArray(plan.enabledModules) ?
    plan.enabledModules.map((m) => String(m).toLowerCase()) : null;
  const expMs = readMillis(plan.expiresDate);
  const expired = String(plan.status ?? "").toLowerCase() === "expired" ||
    (expMs !== null && expMs < Date.now());
  return (mods === null || mods.includes("queue")) && !expired;
}

export interface CallbackRequestLike {
  method: string;
  path?: string;
  url?: string;
  headers: Record<string, string | string[] | undefined>;
  body: unknown;
}

export interface CallbackResponseLike {
  status(code: number): CallbackResponseLike;
  json(body: unknown): void;
  end(): void;
}

function getHeader(req: CallbackRequestLike, name: string): string {
  const lower = name.toLowerCase();
  for (const [k, v] of Object.entries(req.headers)) {
    if (k.toLowerCase() === lower) {
      return Array.isArray(v) ? String(v[0] ?? "") : String(v ?? "");
    }
  }
  return "";
}

export async function handleAbdmCallback(
  db: FirebaseFirestore.Firestore,
  callbackKey: string,
  req: CallbackRequestLike,
  res: CallbackResponseLike,
): Promise<void> {
  // 1. POST only and exact path /<key>/api/v3/hip/patient/share -> else 404
  const rawPath = (req.path ?? req.url ?? "").split("?")[0];
  const pathMatch = rawPath.match(/^\/([^/]+)\/api\/v3\/hip\/patient\/share$/);
  if (req.method.toUpperCase() !== "POST" || !pathMatch) {
    res.status(404).end();
    return;
  }
  if (!callbackKey || !timingSafeMatch(pathMatch[1], callbackKey)) {
    res.status(404).end();
    return;
  }

  // 2. Authorization: Bearer <non-empty> -> else 401
  if (!verifyAbdmToken(getHeader(req, "authorization"))) {
    res.status(401).end();
    return;
  }

  // 3. X-HIP-ID present, equals metaData.hipId, and approved facility -> else 403
  const hipId = getHeader(req, "x-hip-id").trim();
  const body = (req.body && typeof req.body === "object" ? req.body : {}) as Record<string, unknown>;
  const metaData = (body.metaData && typeof body.metaData === "object" ?
    body.metaData : {}) as Record<string, unknown>;
  if (!hipId || String(metaData.hipId ?? "").trim() !== hipId) {
    res.status(403).end();
    return;
  }
  const facilitySnap = await db.collection("abdmFacilities").doc(hipId).get();
  const facilityData = facilitySnap.data();
  const clinicId = typeof facilityData?.clinicId === "string" ? facilityData.clinicId.trim() : "";
  if (!facilitySnap.exists || facilityData?.approved !== true || !clinicId) {
    console.warn("abdmCallback rejected: unknown facility");
    res.status(403).end();
    return;
  }

  // 4. Validate payload fields -> else 400
  const requestId = getHeader(req, "request-id").trim();
  const intent = String(body.intent ?? "").trim();
  const context = String(metaData.context ?? "").trim();
  const profile = (body.profile && typeof body.profile === "object" ?
    body.profile : {}) as Record<string, unknown>;
  const patient = (profile.patient && typeof profile.patient === "object" ?
    profile.patient : {}) as Record<string, unknown>;
  const abhaAddress = String(patient.abhaAddress ?? "").trim();
  const name = String(patient.name ?? "").trim();
  const yearOfBirth = String(patient.yearOfBirth ?? "").trim();

  if (
    intent !== "PROFILE_SHARE" ||
    !requestId ||
    !abhaAddress || abhaAddress.length >= 200 ||
    !name || name.length >= 200 ||
    !/^\d{4}$/.test(yearOfBirth) ||
    !/^[A-Za-z0-9]{1,20}$/.test(context)
  ) {
    res.status(400).end();
    return;
  }

  // 5. Rate limit: 120 shares per facility per 10 minutes -> else 429
  const limitRef = db.collection("abdmOtpLimits").doc(`share_${hmacOf(clinicId, hipId)}`);
  const allowed = await db.runTransaction(async (tx) => {
    const snap = await tx.get(limitRef);
    const now = Date.now();
    const d = snap.data();
    const fresh = !d || now - Number(d.windowStart ?? 0) > SHARE_RATE_WINDOW_MS;
    const count = fresh ? 0 : Number(d.count ?? 0);
    if (count >= SHARE_RATE_MAX) {
      return false;
    }
    tx.set(limitRef, {
      windowStart: fresh ? now : d.windowStart,
      count: count + 1,
      lastAt: now,
    });
    return true;
  });
  if (!allowed) {
    res.status(429).end();
    return;
  }

  // 6. Create share document idempotently
  const shareId = hmacOf(hipId, requestId);
  const shareRef = db.collection("abdmShares").doc(shareId);
  const nowMs = Date.now();
  try {
    await shareRef.create({
      clinicId,
      hipId,
      counter: context,
      requestId,
      payload: seal(JSON.stringify(profile), getPepper()),
      status: "received",
      createdAt: Timestamp.fromMillis(nowMs),
      expiresAt: Timestamp.fromMillis(nowMs + SHARE_TTL_MS),
    });
  } catch (err) {
    const code = (err as {code?: unknown}).code;
    const msg = String((err as Error).message ?? "");
    if (code === 6 || code === "already-exists" || /already exists/i.test(msg)) {
      res.status(200).json({status: "ok"});
      return;
    }
    throw err;
  }

  res.status(200).json({status: "ok"});
}

export const abdmCallback = onRequest(
  {
    region: "asia-south1",
    maxInstances: 10,
    secrets: [abdmCallbackKey, patientKekPepperSecret],
  },
  async (req, res) => {
    await handleAbdmCallback(
      admin.firestore(),
      abdmCallbackKey.value(),
      req,
      res,
    );
  },
);

export async function processShare(
  db: FirebaseFirestore.Firestore,
  client: AbdmClient,
  shareId: string,
  keyringOverride?: PatientKeyring,
  nowDate: Date = new Date(),
): Promise<void> {
  const shareRef = db.collection("abdmShares").doc(shareId);
  const shareSnap = await shareRef.get();
  if (!shareSnap.exists) return;
  const share = shareSnap.data() ?? {};
  if (share.status !== "received" || typeof share.payload !== "string") return;

  const clinicId = String(share.clinicId ?? "");
  const counter = String(share.counter ?? "");
  const requestId = String(share.requestId ?? "");
  let abhaAddress = "";
  let tokenNumber: number | null;

  try {
    const profile = JSON.parse(open(share.payload, getPepper())) as Record<string, unknown>;
    const patient = (profile.patient && typeof profile.patient === "object" ?
      profile.patient : {}) as Record<string, unknown>;

    abhaAddress = String(patient.abhaAddress ?? "").trim();
    const abhaDigits = digitsOnly(String(patient.abhaNumber ?? ""));
    const name = String(patient.name ?? "").trim();
    const gender = mapGender(patient.gender);
    const dob = parseShareDob(patient);
    const birthYear = Number(String(patient.yearOfBirth ?? "").trim());
    const phoneRaw = String(patient.phoneNumber ?? "").trim();

    const keyring = keyringOverride ?? new PatientKeyring(db);
    const dek = await keyring.dekFor(clinicId);
    if (!dek) {
      throw new ShareRefused("No clinical key for clinic.");
    }

    const pIndex = phoneIndexOf(phoneRaw, dek);
    const todayKey = queueDateKeyKolkata(nowDate);
    const nameParts = name.split(/\s+/).filter(Boolean);
    const first = nameParts[0] ?? name;
    const rest = nameParts.slice(1).join(" ");

    const numLinkRef = abhaDigits.length === 14 ?
      db.collection("abhaLinks").doc(`${clinicId}_${hmacOf(clinicId, abhaDigits)}`) : null;
    const addrLinkRef = abhaAddress ?
      db.collection("abhaLinks").doc(`${clinicId}_addr_${hmacOf(clinicId, abhaAddress.toLowerCase())}`) :
      null;

    tokenNumber = await db.runTransaction(async (tx) => {
      // --- ALL READS FIRST ---
      const planRef = db.collection("users").doc(clinicId);
      const [
        shareNow, planSnap, numLinkSnap, addrLinkSnap, phoneQuerySnap, todayQueueSnap,
      ] = await Promise.all([
        tx.get(shareRef),
        tx.get(planRef),
        numLinkRef ? tx.get(numLinkRef) : Promise.resolve(null),
        addrLinkRef ? tx.get(addrLinkRef) : Promise.resolve(null),
        pIndex ?
          tx.get(
            db.collection("patients")
              .where("doctorId", "==", clinicId)
              .where("phoneIndex", "==", pIndex)
              .limit(10),
          ) :
          Promise.resolve(null),
        tx.get(
          db.collection("walk_in_queue")
            .where("doctorId", "==", clinicId)
            .where("queueDate", "==", todayKey),
        ),
      ]);

      const numLinkedId = numLinkSnap?.exists ? String(numLinkSnap.data()?.patientId ?? "") : "";
      const addrLinkedId = addrLinkSnap?.exists ? String(addrLinkSnap.data()?.patientId ?? "") : "";

      const [numPatientSnap, addrPatientSnap] = await Promise.all([
        numLinkedId ? tx.get(db.collection("patients").doc(numLinkedId)) : Promise.resolve(null),
        addrLinkedId && addrLinkedId !== numLinkedId ?
          tx.get(db.collection("patients").doc(addrLinkedId)) :
          Promise.resolve(null),
      ]);

      // --- CHECKS & WRITES ---
      // The trigger can be delivered twice; only the first one registers.
      if (shareNow.data()?.status !== "received") return null;
      if (!planAllowsQueue(planSnap.data())) {
        throw new ShareRefused("Queue feature is not available on this clinic plan.");
      }

      const isUsable = (snap: FirebaseFirestore.DocumentSnapshot | null): boolean => {
        if (!snap || !snap.exists) return false;
        const d = snap.data() ?? {};
        return d.doctorId === clinicId && d.isDeleted !== true && d.isActive !== false;
      };

      let matchedSnap: FirebaseFirestore.DocumentSnapshot | null = null;
      if (isUsable(numPatientSnap)) {
        matchedSnap = numPatientSnap;
      } else if (isUsable(addrPatientSnap)) {
        matchedSnap = addrPatientSnap;
      } else if (phoneQuerySnap) {
        matchedSnap = phoneQuerySnap.docs.find((doc) => {
          const d = doc.data();
          if (d.doctorId !== clinicId || d.isDeleted === true || d.isActive === false) {
            return false;
          }
          const decFirst = (decryptField(d.firstName, dek) ?? "").trim().split(/\s+/)[0]?.toLowerCase();
          if (decFirst !== first.toLowerCase()) return false;
          const dobMs = readMillis(d.dateOfBirth);
          if (dobMs === null) return false;
          // A relative or namesake already holding another ABHA is not them.
          const theirNumber = digitsOnly(decryptField(d.abhaNumber, dek) ?? "");
          if (theirNumber && abhaDigits && theirNumber !== abhaDigits) return false;
          // The app stores local midnight, so read the year in India: in UTC
          // a 1 January birthday falls in the year before.
          return Number(queueDateKeyKolkata(new Date(dobMs)).slice(0, 4)) === birthYear;
        }) ?? null;
      }

      const nowTs = Timestamp.fromDate(nowDate);
      let patientId: string;

      if (matchedSnap) {
        patientId = matchedSnap.id;
        const existing = matchedSnap.data() ?? {};
        const updates: Record<string, unknown> = {};
        const curNum = decryptField(existing.abhaNumber, dek) ?? "";
        const curAddr = decryptField(existing.abhaAddress, dek) ?? "";
        if (!curNum && abhaDigits.length === 14) {
          updates.abhaNumber = encryptField(formatAbhaNumber(abhaDigits), dek);
        }
        if (!curAddr && abhaAddress) {
          updates.abhaAddress = encryptField(abhaAddress, dek);
        }
        if (!existing.abhaVerifiedAt && (updates.abhaNumber || updates.abhaAddress)) {
          updates.abhaVerifiedAt = nowTs;
        }
        if (Object.keys(updates).length > 0) {
          updates.updatedAt = nowTs;
          tx.update(matchedSnap.ref, updates);
        }
      } else {
        const patientRef = db.collection("patients").doc();
        patientId = patientRef.id;
        const phoneDigits = digitsOnly(phoneRaw);
        const cleanPhone = phoneDigits.length >= 10 ? phoneDigits.slice(-10) : phoneRaw;
        const patientDoc: Record<string, unknown> = {
          doctorId: clinicId,
          firstName: encryptField(first, dek),
          lastName: encryptField(rest, dek),
          phone: encryptField(cleanPhone, dek),
          phoneIndex: pIndex,
          email: "",
          gender,
          diagnosis: "[]",
          notes: "",
          oldId: "",
          abhaNumber: abhaDigits.length === 14 ?
            encryptField(formatAbhaNumber(abhaDigits), dek) : "",
          abhaAddress: abhaAddress ? encryptField(abhaAddress, dek) : "",
          abhaVerifiedAt: nowTs,
          packageBalance: 0,
          isArchived: false,
          isActive: true,
          assignedDoctorUids: [],
          createdAt: nowTs,
          updatedAt: nowTs,
        };
        if (dob) {
          patientDoc.dateOfBirth = Timestamp.fromDate(dob);
        }
        tx.set(patientRef, patientDoc);
      }

      if (numLinkRef) {
        tx.set(numLinkRef, {
          clinicId,
          patientId,
          linkedBy: "abdm_share",
          linkedAt: nowTs,
        });
      }
      if (addrLinkRef) {
        tx.set(addrLinkRef, {
          clinicId,
          patientId,
          linkedBy: "abdm_share",
          linkedAt: nowTs,
        });
      }

      const activeToday = todayQueueSnap.docs.filter((d) => d.data().isDeleted !== true);
      const existingTokenDoc = activeToday.find((d) => {
        const st = String(d.data().status ?? "");
        return d.data().patientId === patientId && st !== "completed" && st !== "cancelled";
      });

      let assignedToken: number;
      if (existingTokenDoc) {
        assignedToken = Number(existingTokenDoc.data().tokenNumber ?? 1);
      } else {
        let maxToken = 0;
        for (const d of activeToday) {
          const n = Number(d.data().tokenNumber ?? 0);
          if (n > maxToken) maxToken = n;
        }
        assignedToken = maxToken + 1;
        const queueRef = db.collection("walk_in_queue").doc();
        tx.set(queueRef, {
          doctorId: clinicId,
          patientId,
          walkInName: null,
          walkInPhone: null,
          tokenNumber: assignedToken,
          queueDate: todayKey,
          status: "waiting",
          priority: "normal",
          reason: `ABHA scan (${counter})`,
          checkedInAt: nowTs,
          calledAt: null,
          consultationStartedAt: null,
          completedAt: null,
          linkedVisitId: null,
          groupId: null,
          isDeleted: false,
          attendingDoctorUid: "",
          createdByUid: "",
          createdAt: nowTs,
          updatedAt: nowTs,
        });
      }

      tx.update(shareRef, {
        status: "done",
        tokenNumber: assignedToken,
        payload: FieldValue.delete(),
      });

      return assignedToken;
    });
  } catch (err) {
    // Only our own wording leaves the server; other errors could quote data.
    const shortMsg = err instanceof ShareRefused ?
      err.message : "Unable to register the patient. Please check in at the desk.";
    try {
      await client.requestGateway("POST", "/patient-share/v3/on-share", {
        error: {
          code: "ABDM-1099",
          message: shortMsg,
        },
        response: {requestId},
      });
    } catch {
      // Ignore on-share notification failure when recording failed status.
    }
    await shareRef.update({
      status: "failed",
      error: shortMsg,
      payload: FieldValue.delete(),
    });
    return;
  }

  if (tokenNumber === null) return;
  try {
    await client.requestGateway("POST", "/patient-share/v3/on-share", {
      acknowledgement: {
        status: "SUCCESS",
        abhaAddress,
        profile: {
          context: counter,
          tokenNumber: String(tokenNumber),
          expiry: "1800",
        },
      },
      response: {requestId},
    });
  } catch {
    // The patient is registered and queued: never report that as a failure.
    await shareRef.update({status: "reply_failed"});
  }
}

export const onAbdmShare = onDocumentCreated(
  {
    document: "abdmShares/{id}",
    region: "asia-south1",
    secrets: [abdmClientId, abdmClientSecret, patientKekPepperSecret],
  },
  async (event) => {
    const shareId = event.params.id;
    const db = admin.firestore();
    await processShare(db, getSharedClient(), shareId, getSharedKeyring(db));
  },
);
