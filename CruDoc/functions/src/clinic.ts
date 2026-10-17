import {onCall, HttpsError, CallableRequest} from "firebase-functions/v2/https";
import {onDocumentWritten} from "firebase-functions/v2/firestore";
import * as admin from "firebase-admin";
// Imported directly rather than read off admin.firestore: the Functions
// emulator wraps admin.firestore in a bound copy that drops these
// statics, so admin.firestore.Timestamp / .FieldValue are undefined there
// (production is unaffected; the classes are the same either way).
import {FieldValue, Timestamp} from "firebase-admin/firestore";
import {copyAssignmentsForClinic} from "./clinical-assignment";

// Keep in sync with lib/core/clinic/clinic_permission.dart and the rules.
export const PERMS = [
  "patients.view",
  "patients.edit",
  "clinical.view",
  "clinical.edit",
  "schedule",
  "billing",
  "revenue",
  "inventory",
  "messaging",
  "ai",
  "team",
  "settings",
];

export const IMPLIES: Record<string, string[]> = {
  "patients.edit": ["patients.view"],
  "clinical.view": ["patients.view"],
  "clinical.edit": ["clinical.view", "patients.view"],
};

/**
 * Reading or writing a patient's clinical record. Held apart from the rest
 * because running a clinic and treating its patients are different kinds of
 * authority: a practice manager needs staff, seats, billing and settings,
 * and none of that requires a diagnosis.
 *
 * Keep in sync with clinicalPerm() in firestore.rules and storage.rules.
 */
export const CLINICAL_PERMS = ["clinical.view", "clinical.edit"];

/**
 * What the `admin` role gets unconditionally: everything except the clinical
 * record itself. Clinical access is added only when the clinic owner has
 * turned on `clinics/{id}.adminClinicalAccess`.
 */
export const ADMIN_PERMS = PERMS.filter((p) => !CLINICAL_PERMS.includes(p));

export const ROLE_TEMPLATES = [
  {
    id: "admin",
    name: "Admin",
    kind: "staff",
    perms: [
      "patients.view",
      "patients.edit",
      "clinical.view",
      "clinical.edit",
      "schedule",
      "billing",
      "revenue",
      "inventory",
      "messaging",
      "ai",
      "team",
      "settings",
    ],
    isSystem: true,
  },
  {
    id: "doctor",
    name: "Doctor",
    kind: "doctor",
    perms: [
      "patients.view",
      "patients.edit",
      "clinical.view",
      "clinical.edit",
      "schedule",
      "billing",
      "messaging",
      "ai",
    ],
    isSystem: false,
  },
  {
    id: "receptionist",
    name: "Receptionist",
    kind: "staff",
    perms: [
      "patients.view",
      "patients.edit",
      "schedule",
      "billing",
      "messaging",
    ],
    isSystem: false,
  },
  {
    id: "assistant",
    name: "Assistant / Nurse",
    kind: "staff",
    perms: [
      "patients.view",
      "clinical.view",
      "schedule",
      "inventory",
    ],
    isSystem: false,
  },
  {
    id: "accountant",
    name: "Accountant",
    kind: "staff",
    perms: [
      "patients.view",
      "billing",
      "revenue",
    ],
    isSystem: false,
  },
];

// Same keys as DoctorFeatureGuard.defaultModules plus 'campaigns'.
export const MODULES = [
  "dashboard",
  "revenue",
  "patients",
  "appointments",
  "inventory",
  "home_visits",
  "ai_assistant",
  "ai_agentic_calling",
  "omnichannel_messaging",
  "multi_device_access",
  "queue",
  "campaigns",
];

export const DEFAULT_SEATS = {doctor: 5, staff: 10};
export const INVITE_DAYS = 7;
export const MAX_ROLES = 30;

// Keys of DentalFeature (lib/features/dental/dental_features.dart).
export const DENTAL_FEATURES = [
  "chairside",
  "radiology",
  "perio",
  "endo",
  "pedo",
  "ortho",
  "prostho",
  "surgery",
  "pathology",
  "oral_medicine",
  "sedation",
  "public_health",
];

/** Unknown keys dropped, implied added, sorted. */
export function normalizePerms(input: unknown): string[] {
  if (!Array.isArray(input)) return [];
  const valid = new Set<string>();
  for (const item of input) {
    if (typeof item === "string" && PERMS.includes(item)) {
      valid.add(item);
    }
  }
  // Implied permissions:
  // patients.edit -> patients.view
  // clinical.view -> patients.view
  // clinical.edit -> clinical.view + patients.view
  if (valid.has("clinical.edit")) {
    valid.add("clinical.view");
    valid.add("patients.view");
  }
  if (valid.has("clinical.view")) {
    valid.add("patients.view");
  }
  if (valid.has("patients.edit")) {
    valid.add("patients.view");
  }
  return Array.from(valid).sort();
}

/** Strip spaces/dashes; 10 digits -> "+91…"; "+…" kept; else throw invalid-argument. */
export function normalizePhone(raw: string): string {
  if (typeof raw !== "string") {
    throw new HttpsError("invalid-argument", "Phone number must be a string.");
  }
  const stripped = raw.replace(/[\s-]/g, "");
  if (/^\d{10}$/.test(stripped)) {
    return `+91${stripped}`;
  }
  if (/^\+\d{10,15}$/.test(stripped)) {
    return stripped;
  }
  throw new HttpsError("invalid-argument", "Invalid phone number format. Must be 10 digits or E.164.");
}

/** Null/undefined -> null; else keys in MODULES only, unique, sorted. */
export function normalizeModules(input: unknown): string[] | null {
  if (input === null || input === undefined) return null;
  if (!Array.isArray(input)) return null;
  const filtered = new Set<string>();
  for (const item of input) {
    if (typeof item === "string" && MODULES.includes(item)) {
      filtered.add(item);
    }
  }
  return Array.from(filtered).sort();
}

/** Like normalizeModules, against DENTAL_FEATURES; empty -> null. */
export function normalizeDental(input: unknown): string[] | null {
  if (input === null || input === undefined) return null;
  if (!Array.isArray(input)) return null;
  const filtered = new Set<string>();
  for (const item of input) {
    if (typeof item === "string" && DENTAL_FEATURES.includes(item)) {
      filtered.add(item);
    }
  }
  if (filtered.size === 0) return null;
  return Array.from(filtered).sort();
}

export interface Caller {
  uid: string;
  clinicId: string;
  isOwner: boolean;
  isAdmin: boolean;
  perms: string[];
}

/** Loads the caller's standing in [clinicId]; throws permission-denied if not an active member. */
export async function loadCaller(
  request: CallableRequest | {auth?: {uid?: string; token?: Record<string, unknown>}},
  clinicId: string
): Promise<Caller> {
  const uid = request.auth?.uid;
  if (!uid) {
    throw new HttpsError("unauthenticated", "Authentication required.");
  }
  if (!clinicId) {
    throw new HttpsError("invalid-argument", "clinicId is required.");
  }
  if (uid === clinicId) {
    // A manager who owns the clinic runs it but does not see medical
    // records. Only a clinic created that way says so; a solo doctor has no
    // clinic document, and an existing clinic has no such field, so both
    // keep every permission exactly as before.
    const clinic = await admin.firestore().collection("clinics").doc(clinicId).get();
    const ownerIsDoctor = clinic.data()?.ownerIsDoctor !== false;
    return {
      uid,
      clinicId,
      isOwner: true,
      isAdmin: true,
      perms: ownerIsDoctor ? [...PERMS] : [...ADMIN_PERMS],
    };
  }

  const memberSnap = await admin.firestore()
    .collection("clinics")
    .doc(clinicId)
    .collection("members")
    .doc(uid)
    .get();

  if (!memberSnap.exists) {
    throw new HttpsError("permission-denied", "Not a member of this clinic.");
  }
  const data = memberSnap.data() || {};
  if (data.active !== true) {
    throw new HttpsError("permission-denied", "Inactive clinic membership.");
  }

  const isAdmin = data.roleId === "admin";
  // The admin role no longer carries clinical access by default: being able
  // to run the clinic is not the same as being able to read its charts.
  const perms = isAdmin ?
    (await adminClinicalAllowed(clinicId) ? [...PERMS] : [...ADMIN_PERMS]) :
    normalizePerms(data.perms ?? []);
  return {
    uid,
    clinicId,
    isOwner: false,
    isAdmin,
    perms,
  };
}

/**
 * Whether this clinic's admins may reach clinical records.
 *
 * An absent field means a clinic created before the setting existed, and is
 * read as `true` so that a clinic whose backfill has not run cannot be
 * locked out of its own records. Once migrate_admin_clinical_access.js has
 * been applied everywhere, this default should become `false`.
 */
export async function adminClinicalAllowed(clinicId: string): Promise<boolean> {
  const snap = await admin.firestore().collection("clinics").doc(clinicId).get();
  return snap.data()?.adminClinicalAccess !== false;
}

/**
 * Whether the caller holds `perm`.
 *
 * There is deliberately no admin shortcut here: `loadCaller` already put
 * everything an admin is entitled to into `perms`, so a shortcut would
 * silently hand back the clinical access that was just withheld.
 */
/**
 * Like normalizePhone, for numbers typed into a phone's address book:
 * spaces, dashes, dots and brackets are dropped, a leading 0 (Indian trunk
 * prefix) or 00 (international prefix) is understood, and anything that
 * still isn't a phone number gives null instead of throwing.
 */
export function normalizeContactPhone(raw: unknown): string | null {
  if (typeof raw !== "string") return null;
  let n = raw.replace(/[\s\-().]/g, "");
  if (n.startsWith("00")) n = `+${n.slice(2)}`;
  if (/^0\d{10}$/.test(n)) n = n.slice(1);
  if (/^91\d{10}$/.test(n)) n = `+${n}`;
  if (/^\d{10}$/.test(n)) return `+91${n}`;
  if (/^\+\d{10,15}$/.test(n)) return n;
  return null;
}

/** The signed-in phone number, normalised; null when the account has none. */
function tokenPhone(token: Record<string, unknown> | undefined): string | null {
  const raw = token?.phone_number;
  if (!raw) return null;
  try {
    return normalizePhone(String(raw));
  } catch {
    return String(raw);
  }
}

/**
 * Whether an invite was sent to the signed-in person: its phone matches the
 * account's phone, or its email matches the account's verified email.
 */
export function inviteMatchesCaller(
  invite: Record<string, unknown>,
  token: Record<string, unknown> | undefined
): boolean {
  const phone = tokenPhone(token);
  let invitePhone: string | null = null;
  if (invite.phone) {
    try {
      invitePhone = normalizePhone(String(invite.phone));
    } catch {
      invitePhone = String(invite.phone);
    }
  }
  if (invitePhone && phone && invitePhone === phone) return true;
  const email = token?.email_verified && token?.email ?
    String(token.email).toLowerCase().trim() : null;
  const inviteEmail = invite.email ? String(invite.email).toLowerCase().trim() : null;
  return !!(inviteEmail && email && inviteEmail === email);
}

/** The account with this phone number, if there is one. */
async function uidForPhone(phone: string): Promise<string | null> {
  try {
    return (await admin.auth().getUserByPhoneNumber(phone)).uid;
  } catch (err) {
    if ((err as {code?: string}).code === "auth/user-not-found") return null;
    throw err;
  }
}

/**
 * users/{uid}/clinic_invites/{inviteId}: the invitee's copy of an invite,
 * which their app listens to so the invite pops up the moment it is sent.
 * Written only here (the rules refuse clients); the invite under the clinic
 * stays the one that counts when they accept.
 */
function inboxRef(uid: string, inviteId: string) {
  return admin.firestore().collection("users").doc(uid)
    .collection("clinic_invites").doc(inviteId);
}

function inboxEntry(inviteId: string, invite: Record<string, unknown>): Record<string, unknown> {
  return {
    inviteId,
    clinicId: invite.clinicId || "",
    clinicName: invite.clinicName || "",
    name: invite.name || "",
    kind: invite.kind || "staff",
    roleName: invite.roleName || "",
    specialty: invite.specialty || "",
    invitedByName: invite.invitedByName || "",
    expiresAt: invite.expiresAt ?? null,
    status: "pending",
    createdAt: FieldValue.serverTimestamp(),
  };
}

/** Whether people may find this account by its phone number (default yes). */
async function isDiscoverable(uid: string): Promise<boolean> {
  const snap = await admin.firestore().collection("users").doc(uid).get();
  return snap.data()?.discoverable !== false;
}

/** How many contact numbers one person may check per hour. */
export const MATCH_CONTACTS_PER_HOUR = 5000;
/** How many numbers one matchContacts call may carry. */
export const MATCH_CONTACTS_PER_CALL = 1000;

export function requirePerm(c: Caller, perm: string): void {
  if (!c.perms.includes(perm)) {
    throw new HttpsError("permission-denied", `Missing required permission: ${perm}.`);
  }
}

/**
 * Only the owner or an admin may hand out admin or team rights. Anyone else
 * may only hand out permissions they hold themselves; otherwise a manager
 * with `team` could create a role with revenue or clinical access and invite
 * a second phone of their own into it.
 */
export function checkEscalation(c: Caller, roleId?: string, perms?: unknown): void {
  if (c.isOwner || c.isAdmin) return;
  const list = Array.isArray(perms) ? perms.map(String) : [];
  if (roleId === "admin" || list.includes("team")) {
    throw new HttpsError("permission-denied", "Only clinic owner or admin may manage admin or team permissions.");
  }
  if (list.some((p) => !c.perms.includes(p))) {
    throw new HttpsError("permission-denied", "You can only give permissions you have yourself.");
  }
}

/**
 * Staff may *read* clinical records — an assistant or nurse needs the chart
 * they are assisting with, which is why the built-in Assistant role holds
 * `clinical.view` — but writing one is a clinical act, so `clinical.edit`
 * has no business on a staff role.
 *
 * The built-in `admin` role is exempt while it still carries every
 * permission; separating administrative authority from clinical privilege
 * is what removes that exemption. `saveRole` refuses to modify it anyway.
 */
export function assertStaffCannotWriteClinical(
  kind: "doctor" | "staff",
  perms: string[],
  roleId?: string
): void {
  if (roleId === "admin") return;
  if (kind === "staff" && perms.includes("clinical.edit")) {
    throw new HttpsError(
      "invalid-argument",
      "A staff role cannot write clinical records. Set the kind to doctor, " +
      "or remove clinical.edit from the role."
    );
  }
}

/** Helper to record an access_log audit entry into a batch or transaction. */
function addAuditLog(
  batchOrTx: admin.firestore.WriteBatch | admin.firestore.Transaction,
  clinicId: string,
  actorUid: string,
  action: string,
  target: string
): void {
  const logRef = admin.firestore().collection("access_logs").doc();
  const entry = {
    doctorId: clinicId,
    actorUid,
    action,
    target,
    platform: "server",
    at: FieldValue.serverTimestamp(),
  };
  if ("create" in batchOrTx) {
    (batchOrTx as admin.firestore.WriteBatch).set(logRef, entry);
  } else {
    (batchOrTx as admin.firestore.Transaction).set(logRef, entry);
  }
}

/** Checks seat limits for doctor or staff. */
async function checkSeats(
  clinicId: string,
  kind: "doctor" | "staff",
  excludeInviteId?: string,
  tx?: admin.firestore.Transaction
): Promise<void> {
  const db = admin.firestore();
  const clinicRef = db.collection("clinics").doc(clinicId);
  const clinicSnap = tx ? await tx.get(clinicRef) : await clinicRef.get();
  const clinicData = clinicSnap.data() || {};
  const seatsConfig = clinicData.seats || DEFAULT_SEATS;
  const maxSeats = Number(seatsConfig[kind] ?? DEFAULT_SEATS[kind]);

  const membersQuery = clinicRef
    .collection("members")
    .where("active", "==", true)
    .where("kind", "==", kind);
  const invitesQuery = clinicRef
    .collection("invites")
    .where("status", "==", "pending")
    .where("kind", "==", kind);

  const activeMembersSnap = tx ? await tx.get(membersQuery) : await membersQuery.get();
  const pendingInvitesSnap = tx ? await tx.get(invitesQuery) : await invitesQuery.get();

  const now = Date.now();
  let pendingCount = 0;
  for (const doc of pendingInvitesSnap.docs) {
    if (excludeInviteId && doc.id === excludeInviteId) continue;
    const invData = doc.data();
    const exp = invData.expiresAt?.toMillis ?
      invData.expiresAt.toMillis() :
      (invData.expiresAt ? new Date(invData.expiresAt).getTime() : 0);
    if (exp > now) {
      pendingCount++;
    }
  }

  const currentCount = activeMembersSnap.size + pendingCount;
  if (currentCount >= maxSeats) {
    throw new HttpsError(
      "resource-exhausted",
      `The clinic has reached its limit of ${maxSeats} ${kind} seats.`
    );
  }
}

export const clinicTeam = onCall(
  {region: "asia-south1", maxInstances: 10},
  async (request) => {
    if (!request.auth || !request.auth.uid) {
      throw new HttpsError("unauthenticated", "Authentication required.");
    }
    const uid = request.auth.uid;
    const db = admin.firestore();
    const data = request.data || {};
    const action = String(data.action ?? "");

    switch (action) {
    case "ensureClinic": {
      const userRef = db.collection("users").doc(uid);
      const userSnap = await userRef.get();
      if (!userSnap.exists) {
        throw new HttpsError("failed-precondition", "User profile does not exist.");
      }
      const userData = userSnap.data() || {};
      const clinicRef = db.collection("clinics").doc(uid);
      const clinicSnap = await clinicRef.get();

      const clinicName = String(data.clinicName || userData.clinicName || userData.name || "Clinic").trim();
      const ownerName = String(data.ownerName || userData.name || "Doctor").trim();
      const specialty = String(data.specialty || userData.specialty || "").trim();
      const phone = (request.auth.token.phone_number as string) || (userData.phone as string) || "";
      const email = (request.auth.token.email as string) || (userData.email as string) || "";

      if (clinicSnap.exists) {
        const memberRef = clinicRef.collection("members").doc(uid);
        const memberSnap = await memberRef.get();
        const needsUserClinicId = userData.clinicId !== uid || userData.memberKind !== "owner";

        if (memberSnap.exists && !needsUserClinicId) {
          return {clinicId: uid};
        }

        const batch = db.batch();
        if (!memberSnap.exists) {
          batch.set(memberRef, {
            name: ownerName,
            phone,
            email,
            kind: "doctor",
            roleId: "admin",
            roleName: "Admin",
            perms: PERMS,
            active: true,
            isOwner: true,
            specialty,
            qualification: userData.qualification || "",
            registrationNo: userData.registrationNo || "",
            joinedAt: FieldValue.serverTimestamp(),
          });
        }

        if (needsUserClinicId) {
          batch.set(userRef, {clinicId: uid, memberKind: "owner"}, {merge: true});
        }

        addAuditLog(batch, uid, uid, "team.create", uid);
        await batch.commit();
        return {clinicId: uid};
      }

      // Whether the person setting up the clinic treats patients. A manager
      // who owns the clinic runs it but does not see medical records — the
      // same line drawn for admins. Decided once, here, when the clinic is
      // created; an existing clinic (above) is never changed by this.
      // Absent means a doctor, which is what every clinic was before.
      const ownerIsDoctor = data.ownerIsDoctor !== false;

      if (!ownerIsDoctor) {
        // The rules read this from the token, so that a manager-owner is
        // restricted without an extra document read on every request — and
        // without any change at all for solo doctors, who never carry it.
        // Set before the clinic exists, so there is no moment in which the
        // clinic is up but its owner is unrestricted. Merged, never replaced:
        // claims hold other things (Super Admin's role) too.
        const existing = (await admin.auth().getUser(uid)).customClaims || {};
        await admin.auth().setCustomUserClaims(uid, {...existing, nonClinicalOwner: true});
      }

      const batch = db.batch();
      const clinicPayload: Record<string, unknown> = {
        name: clinicName,
        specialty,
        ownerUid: uid,
        ownerIsDoctor,
        seats: DEFAULT_SEATS,
        // Administrative authority is not clinical privilege: a new clinic's
        // admins get no access to clinical records until the owner grants it.
        // Clinics created before this field existed are backfilled to `true`
        // by migrate_admin_clinical_access.js, so nobody loses access on
        // deploy; the rules treat an absent field as `true` for the same
        // reason. See crudoc-rbac-decisions.
        adminClinicalAccess: false,
        createdAt: FieldValue.serverTimestamp(),
      };
      if (userData.enabledModules !== undefined) clinicPayload.enabledModules = userData.enabledModules;
      if (userData.status !== undefined) clinicPayload.status = userData.status;
      if (userData.expiresDate !== undefined) clinicPayload.expiresDate = userData.expiresDate;
      if (userData.subscriptionPlan !== undefined) clinicPayload.subscriptionPlan = userData.subscriptionPlan;

      batch.set(clinicRef, clinicPayload);

      for (const role of ROLE_TEMPLATES) {
        const roleRef = clinicRef.collection("roles").doc(role.id);
        batch.set(roleRef, {
          name: role.name,
          kind: role.kind,
          perms: role.perms,
          isSystem: role.id === "admin",
          updatedAt: FieldValue.serverTimestamp(),
        });
      }

      const memberRef = clinicRef.collection("members").doc(uid);
      batch.set(memberRef, {
        name: ownerName,
        phone,
        email,
        // A manager-owner is listed as staff: not offered as a doctor to
        // assign, and counted against staff seats rather than doctor seats.
        kind: ownerIsDoctor ? "doctor" : "staff",
        roleId: "admin",
        roleName: "Admin",
        perms: ownerIsDoctor ? PERMS : ADMIN_PERMS,
        active: true,
        isOwner: true,
        specialty,
        qualification: userData.qualification || "",
        registrationNo: userData.registrationNo || "",
        joinedAt: FieldValue.serverTimestamp(),
      });

      batch.set(userRef, {clinicId: uid, memberKind: "owner"}, {merge: true});
      addAuditLog(batch, uid, uid, "team.create", uid);
      try {
        await batch.commit();
      } catch (err) {
        if (!ownerIsDoctor) {
          // Undo the claim so a failed setup leaves the account as it was.
          const claims = {...((await admin.auth().getUser(uid)).customClaims || {})};
          delete claims.nonClinicalOwner;
          await admin.auth().setCustomUserClaims(uid, claims).catch(() => undefined);
        }
        throw err;
      }

      return {clinicId: uid, ownerIsDoctor};
    }

    case "myInvites": {
      let phone: string | null = null;
      if (request.auth.token.phone_number) {
        try {
          phone = normalizePhone(String(request.auth.token.phone_number));
        } catch {
          phone = String(request.auth.token.phone_number);
        }
      }

      let email: string | null = null;
      if (request.auth.token.email_verified && request.auth.token.email) {
        email = String(request.auth.token.email).toLowerCase().trim();
      }

      if (!phone && !email) {
        return {invites: []};
      }

      const queryPromises: Promise<admin.firestore.QuerySnapshot>[] = [];
      if (phone) {
        queryPromises.push(
          db.collectionGroup("invites")
            .where("phone", "==", phone)
            .where("status", "==", "pending")
            .get()
        );
      }
      if (email) {
        queryPromises.push(
          db.collectionGroup("invites")
            .where("email", "==", email)
            .where("status", "==", "pending")
            .get()
        );
      }

      const snapshots = await Promise.all(queryPromises);
      const invitesMap = new Map<string, admin.firestore.QueryDocumentSnapshot>();
      for (const snap of snapshots) {
        for (const doc of snap.docs) {
          invitesMap.set(doc.id, doc);
        }
      }

      const now = Date.now();
      const list = [];
      // Invites sent before this account existed (or before it had this
      // phone number) have no inbox copy yet; add one so the app's live
      // listener shows them too.
      const inboxBatch = db.batch();
      let inboxWrites = 0;
      for (const doc of invitesMap.values()) {
        const invData = doc.data();
        const exp = invData.expiresAt?.toMillis ?
          invData.expiresAt.toMillis() :
          (invData.expiresAt ? new Date(invData.expiresAt).getTime() : 0);
        if (exp > now) {
          inboxBatch.set(inboxRef(uid, doc.id), inboxEntry(doc.id, invData), {merge: true});
          inboxWrites += 1;
          list.push({
            id: doc.id,
            clinicId: invData.clinicId || "",
            clinicName: invData.clinicName || "",
            name: invData.name || "",
            kind: invData.kind || "staff",
            roleName: invData.roleName || "",
            invitedByName: invData.invitedByName || "",
            expiresAt: new Date(exp).toISOString(),
          });
        }
      }

      if (inboxWrites > 0) await inboxBatch.commit();
      return {invites: list};
    }

    case "acceptInvite": {
      const clinicId = String(data.clinicId ?? "").trim();
      const inviteId = String(data.inviteId ?? "").trim();
      if (!clinicId || !inviteId) {
        throw new HttpsError("invalid-argument", "clinicId and inviteId are required.");
      }

      const clinicRef = db.collection("clinics").doc(clinicId);
      const inviteRef = clinicRef.collection("invites").doc(inviteId);
      const memberRef = clinicRef.collection("members").doc(uid);
      const userRef = db.collection("users").doc(uid);

      return await db.runTransaction(async (transaction) => {
        const inviteSnap = await transaction.get(inviteRef);
        if (!inviteSnap.exists) {
          throw new HttpsError("not-found", "Invite not found.");
        }
        const inviteData = inviteSnap.data() || {};
        if (inviteData.status !== "pending") {
          throw new HttpsError("failed-precondition", "Invite is no longer pending.");
        }

        const now = Date.now();
        const exp = inviteData.expiresAt?.toMillis ?
          inviteData.expiresAt.toMillis() :
          (inviteData.expiresAt ? new Date(inviteData.expiresAt).getTime() : 0);
        if (exp <= now) {
          throw new HttpsError("failed-precondition", "Invite has expired.");
        }

        let tokenPhone: string | null = null;
        if (request.auth?.token.phone_number) {
          try {
            tokenPhone = normalizePhone(String(request.auth.token.phone_number));
          } catch {
            tokenPhone = String(request.auth.token.phone_number);
          }
        }

        let tokenEmail: string | null = null;
        if (request.auth?.token.email_verified && request.auth?.token.email) {
          tokenEmail = String(request.auth.token.email).toLowerCase().trim();
        }

        let invitePhone: string | null = null;
        if (inviteData.phone) {
          try {
            invitePhone = normalizePhone(String(inviteData.phone));
          } catch {
            invitePhone = String(inviteData.phone);
          }
        }

        const inviteEmail = inviteData.email ? String(inviteData.email).toLowerCase().trim() : null;

        const phoneMatch = !!(invitePhone && tokenPhone && invitePhone === tokenPhone);
        const emailMatch = !!(inviteEmail && tokenEmail && inviteEmail === tokenEmail);

        if (!phoneMatch && !emailMatch) {
          throw new HttpsError(
            "permission-denied",
            "Invite does not match signed-in phone number or verified email."
          );
        }

        const kind = (inviteData.kind === "doctor" ? "doctor" : "staff") as "doctor" | "staff";
        await checkSeats(clinicId, kind, inviteId, transaction);

        const roleRef = clinicRef.collection("roles").doc(String(inviteData.roleId ?? ""));
        const roleSnap = await transaction.get(roleRef);
        if (!roleSnap.exists) {
          throw new HttpsError("not-found", "Assigned role does not exist.");
        }
        const roleData = roleSnap.data() || {};
        const perms = roleSnap.id === "admin" ? [...PERMS] : normalizePerms(roleData.perms ?? []);

        const userSnap = await transaction.get(userRef);
        const userData = userSnap.data() || {};

        // One account belongs to one clinic. Someone who runs their own
        // clinic would otherwise be moved out of it without a word, and
        // someone already working elsewhere would silently switch clinics.
        if (clinicId !== uid) {
          const ownClinic = await transaction.get(db.collection("clinics").doc(uid));
          if (ownClinic.exists) {
            throw new HttpsError(
              "failed-precondition",
              "You run your own clinic on CruDoc, so this account can't join another clinic."
            );
          }
        }
        const currentClinic = typeof userData.clinicId === "string" ? userData.clinicId : "";
        if (currentClinic && currentClinic !== uid && currentClinic !== clinicId) {
          const currentMember = await transaction.get(
            db.collection("clinics").doc(currentClinic).collection("members").doc(uid)
          );
          if (currentMember.exists && currentMember.data()?.active === true) {
            throw new HttpsError(
              "failed-precondition",
              "You're already part of another clinic. Ask its admin to remove you first."
            );
          }
        }

        const memberData: Record<string, unknown> = {
          name: inviteData.name || (request.auth?.token.name as string) || (userData.name as string) || "",
          phone: inviteData.phone || (request.auth?.token.phone_number as string) || (userData.phone as string) || "",
          email: inviteData.email || (request.auth?.token.email as string) || (userData.email as string) || "",
          kind,
          roleId: inviteData.roleId,
          roleName: inviteData.roleName || roleData.name || "",
          perms,
          active: true,
          isOwner: false,
          specialty: inviteData.specialty || "",
          qualification: "",
          registrationNo: "",
          joinedAt: FieldValue.serverTimestamp(),
          invitedBy: inviteData.invitedBy || "",
        };

        if (inviteData.modules !== undefined && inviteData.modules !== null) {
          memberData.modules = inviteData.modules;
        }
        if (kind === "doctor" && inviteData.dentalFeatures !== undefined && inviteData.dentalFeatures !== null) {
          memberData.dentalFeatures = inviteData.dentalFeatures;
        }

        transaction.set(memberRef, memberData);
        transaction.delete(inboxRef(uid, inviteId));
        transaction.update(inviteRef, {
          status: "accepted",
          acceptedBy: uid,
        });

        const userUpdate: Record<string, unknown> = {
          clinicId,
          memberKind: kind,
        };
        if (!userData.name && memberData.name) userUpdate.name = memberData.name;
        if (!userData.phone && memberData.phone) userUpdate.phone = memberData.phone;
        if (!userData.email && memberData.email) userUpdate.email = memberData.email;
        if (!userData.createdAt) userUpdate.createdAt = FieldValue.serverTimestamp();

        transaction.set(userRef, userUpdate, {merge: true});
        addAuditLog(transaction, clinicId, uid, "team.join", uid);

        return {success: true, clinicId};
      });
    }

    case "invite": {
      const clinicId = String(data.clinicId ?? "").trim();
      const caller = await loadCaller(request, clinicId);
      requirePerm(caller, "team");

      const rawPhone = typeof data.phone === "string" ? data.phone.trim() : "";
      const rawEmail = typeof data.email === "string" ? data.email.trim() : "";

      if ((rawPhone && rawEmail) || (!rawPhone && !rawEmail)) {
        throw new HttpsError("invalid-argument", "Provide exactly one of phone or email.");
      }

      let phone: string | null = null;
      let email: string | null = null;
      if (rawPhone) {
        phone = normalizePhone(rawPhone);
      } else {
        const lowerEmail = rawEmail.toLowerCase();
        if (!/^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(lowerEmail)) {
          throw new HttpsError("invalid-argument", "Invalid email address format.");
        }
        email = lowerEmail;
      }

      const kind = (data.kind === "doctor" ? "doctor" : "staff") as "doctor" | "staff";
      const roleId = String(data.roleId ?? "").trim();
      if (!roleId) {
        throw new HttpsError("invalid-argument", "roleId is required.");
      }

      const roleRef = db.collection("clinics").doc(clinicId).collection("roles").doc(roleId);
      const roleSnap = await roleRef.get();
      if (!roleSnap.exists) {
        throw new HttpsError("not-found", "Role not found.");
      }
      const roleData = roleSnap.data() || {};
      checkEscalation(caller, roleId, roleData.perms);
      // The invite carries its own kind, which can differ from the role's, so
      // the invariant is checked against what the member would actually get.
      // A role created before this rule existed and holding clinical.edit on
      // a staff kind is refused here rather than propagated to a new member.
      assertStaffCannotWriteClinical(
        kind,
        normalizePerms(roleData.perms ?? []),
        roleId
      );

      const memberQuery = phone ?
        db.collection("clinics").doc(clinicId).collection("members")
          .where("active", "==", true).where("phone", "==", phone) :
        db.collection("clinics").doc(clinicId).collection("members")
          .where("active", "==", true).where("email", "==", String(email));

      const existingMemberSnap = await memberQuery.limit(1).get();
      if (!existingMemberSnap.empty) {
        throw new HttpsError(
          "already-exists",
          `An active member already has that ${phone ? "phone number" : "email"}.`
        );
      }

      const inviteQuery = phone ?
        db.collection("clinics").doc(clinicId).collection("invites")
          .where("status", "==", "pending").where("phone", "==", phone) :
        db.collection("clinics").doc(clinicId).collection("invites")
          .where("status", "==", "pending").where("email", "==", String(email));

      const existingInviteSnap = await inviteQuery.get();
      const now = Date.now();
      for (const invDoc of existingInviteSnap.docs) {
        const invData = invDoc.data();
        const exp = invData.expiresAt?.toMillis ?
          invData.expiresAt.toMillis() :
          (invData.expiresAt ? new Date(invData.expiresAt).getTime() : 0);
        if (exp > now) {
          throw new HttpsError(
            "already-exists",
            `A pending invite already exists for that ${phone ? "phone number" : "email"}.`
          );
        }
      }

      await checkSeats(clinicId, kind);

      const clinicSnap = await db.collection("clinics").doc(clinicId).get();
      const clinicName = clinicSnap.data()?.name || "Clinic";

      let invitedByName = "Clinic Admin";
      if (caller.uid === clinicId) {
        const ownerMemberSnap = await db.collection("clinics").doc(clinicId)
          .collection("members").doc(caller.uid).get();
        invitedByName = ownerMemberSnap.data()?.name || clinicName;
      } else {
        const callerMemberSnap = await db.collection("clinics").doc(clinicId)
          .collection("members").doc(caller.uid).get();
        invitedByName = callerMemberSnap.data()?.name || "Clinic Staff";
      }

      const expiresAt = new Date(Date.now() + INVITE_DAYS * 24 * 60 * 60 * 1000);
      const inviteRef = db.collection("clinics").doc(clinicId).collection("invites").doc();
      const invitePayload: Record<string, unknown> = {
        clinicId,
        clinicName,
        name: String(data.name || "").trim(),
        kind,
        roleId,
        roleName: roleData.name || roleId,
        status: "pending",
        invitedBy: caller.uid,
        invitedByName,
        createdAt: FieldValue.serverTimestamp(),
        expiresAt: Timestamp.fromDate(expiresAt),
      };

      if (phone) invitePayload.phone = phone;
      if (email) invitePayload.email = email;
      if (kind === "doctor" && data.specialty) invitePayload.specialty = String(data.specialty);

      const normModules = normalizeModules(data.modules);
      if (normModules !== null) invitePayload.modules = normModules;

      if (kind === "doctor") {
        const normDental = normalizeDental(data.dentalFeatures);
        if (normDental !== null) invitePayload.dentalFeatures = normDental;
      }

      const batch = db.batch();
      // Someone who already has an account with this number gets the
      // invite in their app straight away.
      const inviteeUid = phone ? await uidForPhone(phone) : null;
      if (inviteeUid) invitePayload.inviteeUid = inviteeUid;

      batch.set(inviteRef, invitePayload);
      if (inviteeUid) batch.set(inboxRef(inviteeUid, inviteRef.id), inboxEntry(inviteRef.id, invitePayload));
      addAuditLog(batch, clinicId, caller.uid, "team.invite", inviteRef.id);
      await batch.commit();

      // Only say they're on CruDoc if they let people find them; either way
      // the invite reaches them.
      const onCruDoc = inviteeUid ? await isDiscoverable(inviteeUid) : false;
      return {inviteId: inviteRef.id, onCruDoc};
    }

    case "createMember": {
      // The admin creates a person's account directly, rather than inviting
      // them to make one. The admin never sets or sees a password: an email
      // account gets a set-your-password link (sent by the admin's app), a
      // phone account signs in with a one-time code. Someone who already has
      // a CruDoc account is not touched — the app invites them instead.
      const clinicId = String(data.clinicId ?? "").trim();
      const caller = await loadCaller(request, clinicId);
      requirePerm(caller, "team");

      const name = String(data.name ?? "").trim();
      if (!name || name.length > 100) {
        throw new HttpsError("invalid-argument", "Add the person's name (up to 100 characters).");
      }

      const rawPhone = typeof data.phone === "string" ? data.phone.trim() : "";
      const rawEmail = typeof data.email === "string" ? data.email.trim() : "";
      if ((rawPhone && rawEmail) || (!rawPhone && !rawEmail)) {
        throw new HttpsError("invalid-argument", "Provide exactly one of phone or email.");
      }
      let phone: string | null = null;
      let email: string | null = null;
      if (rawPhone) {
        phone = normalizePhone(rawPhone);
      } else {
        const lowerEmail = rawEmail.toLowerCase();
        if (!/^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(lowerEmail)) {
          throw new HttpsError("invalid-argument", "Invalid email address format.");
        }
        email = lowerEmail;
      }

      const kind = (data.kind === "doctor" ? "doctor" : "staff") as "doctor" | "staff";
      const roleId = String(data.roleId ?? "").trim();
      if (!roleId) {
        throw new HttpsError("invalid-argument", "roleId is required.");
      }
      const roleSnap = await db.collection("clinics").doc(clinicId)
        .collection("roles").doc(roleId).get();
      if (!roleSnap.exists) {
        throw new HttpsError("not-found", "Role not found.");
      }
      const roleData = roleSnap.data() || {};
      checkEscalation(caller, roleId, roleData.perms);
      assertStaffCannotWriteClinical(kind, normalizePerms(roleData.perms ?? []), roleId);

      // An existing account belongs to someone already; creating a second one
      // is impossible and taking it over would be wrong. Tell the app to fall
      // back to an invite, which that person accepts themselves.
      try {
        if (phone) {
          await admin.auth().getUserByPhoneNumber(phone);
        } else {
          await admin.auth().getUserByEmail(String(email));
        }
        return {mode: "exists"};
      } catch (err) {
        if ((err as {code?: string}).code !== "auth/user-not-found") throw err;
      }

      await checkSeats(clinicId, kind);

      const clinicSnap = await db.collection("clinics").doc(clinicId).get();
      const clinicName = clinicSnap.data()?.name || "Clinic";

      const created = await admin.auth().createUser(phone ?
        {phoneNumber: phone, displayName: name} :
        {email: String(email), displayName: name, emailVerified: false});
      const newUid = created.uid;

      const memberData: Record<string, unknown> = {
        name,
        phone: phone || "",
        email: email || "",
        kind,
        roleId,
        roleName: roleData.name || roleId,
        perms: roleId === "admin" ? [...PERMS] : normalizePerms(roleData.perms ?? []),
        active: true,
        isOwner: false,
        specialty: kind === "doctor" ? String(data.specialty || "") : "",
        qualification: "",
        registrationNo: "",
        joinedAt: FieldValue.serverTimestamp(),
        createdBy: caller.uid,
      };
      const normModules = normalizeModules(data.modules);
      if (normModules !== null) memberData.modules = normModules;
      if (kind === "doctor") {
        const normDental = normalizeDental(data.dentalFeatures);
        if (normDental !== null) memberData.dentalFeatures = normDental;
      }

      try {
        const batch = db.batch();
        batch.set(db.collection("clinics").doc(clinicId).collection("members").doc(newUid), memberData);
        // The login screen requires a profile, and memberKind tells the app
        // this person works in a clinic, so they skip the owner's onboarding.
        batch.set(db.collection("users").doc(newUid), {
          uid: newUid,
          name,
          displayName: name,
          email: email || "",
          phone: phone || "",
          clinicId,
          memberKind: kind,
          clinicName,
          createdAt: FieldValue.serverTimestamp(),
        });
        addAuditLog(batch, clinicId, caller.uid, "team.createMember", newUid);
        await batch.commit();
      } catch (err) {
        // Never leave an account behind with no clinic to belong to.
        await admin.auth().deleteUser(newUid).catch(() => undefined);
        throw new HttpsError(
          "internal",
          "Could not finish setting up the account. Nothing was created; try again."
        );
      }

      return {mode: "created", uid: newUid, contact: phone ? "phone" : "email"};
    }

    case "cancelInvite": {
      const clinicId = String(data.clinicId ?? "").trim();
      const inviteId = String(data.inviteId ?? "").trim();
      if (!clinicId || !inviteId) {
        throw new HttpsError("invalid-argument", "clinicId and inviteId are required.");
      }

      const caller = await loadCaller(request, clinicId);
      requirePerm(caller, "team");

      const inviteRef = db.collection("clinics").doc(clinicId).collection("invites").doc(inviteId);
      const inviteSnap = await inviteRef.get();
      if (!inviteSnap.exists) {
        throw new HttpsError("not-found", "Invite not found.");
      }
      // An accepted invite is history; cancelling it would rewrite that.
      if (inviteSnap.data()?.status !== "pending") {
        throw new HttpsError("failed-precondition", "Invite is no longer pending.");
      }

      const batch = db.batch();
      batch.update(inviteRef, {
        status: "cancelled",
      });
      const cancelled = inviteSnap.data() || {};
      const inviteeUid = typeof cancelled.inviteeUid === "string" ? cancelled.inviteeUid :
        (cancelled.phone ? await uidForPhone(String(cancelled.phone)) : null);
      if (inviteeUid) batch.delete(inboxRef(inviteeUid, inviteId));
      addAuditLog(batch, clinicId, caller.uid, "invite.cancel", inviteId);
      await batch.commit();

      return {success: true};
    }

    case "updateMember": {
      const clinicId = String(data.clinicId ?? "").trim();
      const targetUid = String(data.uid ?? "").trim();
      if (!clinicId || !targetUid) {
        throw new HttpsError("invalid-argument", "clinicId and uid are required.");
      }

      const caller = await loadCaller(request, clinicId);
      requirePerm(caller, "team");

      if (targetUid === clinicId) {
        throw new HttpsError("invalid-argument", "Cannot update clinic owner.");
      }
      if (targetUid === caller.uid) {
        throw new HttpsError("invalid-argument", "Cannot update yourself.");
      }

      const memberRef = db.collection("clinics").doc(clinicId).collection("members").doc(targetUid);
      const memberSnap = await memberRef.get();
      if (!memberSnap.exists) {
        throw new HttpsError("not-found", "Member not found.");
      }
      const targetData = memberSnap.data() || {};
      if (targetData.active !== true) {
        throw new HttpsError("failed-precondition", "Cannot update inactive member.");
      }

      if (targetData.roleId === "admin" || (Array.isArray(targetData.perms) && targetData.perms.includes("team"))) {
        checkEscalation(caller, targetData.roleId, targetData.perms);
      }

      const updates: Record<string, unknown> = {};

      if (data.roleId !== undefined && data.roleId !== null) {
        const roleId = String(data.roleId).trim();
        const roleRef = db.collection("clinics").doc(clinicId).collection("roles").doc(roleId);
        const roleSnap = await roleRef.get();
        if (!roleSnap.exists) {
          throw new HttpsError("not-found", "Role not found.");
        }
        const roleData = roleSnap.data() || {};
        checkEscalation(caller, roleId, roleData.perms);
        updates.roleId = roleId;
        updates.roleName = roleData.name || roleId;
        updates.perms = roleId === "admin" ? [...PERMS] : normalizePerms(roleData.perms ?? []);
      }

      if (data.kind !== undefined && data.kind !== null) {
        const newKind = (data.kind === "doctor" ? "doctor" : "staff") as "doctor" | "staff";
        if (newKind !== targetData.kind) {
          await checkSeats(clinicId, newKind);
          updates.kind = newKind;
        }
      }

      if (data.specialty !== undefined) {
        updates.specialty = String(data.specialty || "");
      }

      if ("modules" in data) {
        if (data.modules === null) {
          updates.modules = FieldValue.delete();
        } else {
          const norm = normalizeModules(data.modules);
          updates.modules = norm !== null ? norm : FieldValue.delete();
        }
      }

      // Changing the role or the kind must not leave a staff member holding
      // clinical write access — flipping a doctor to staff while they keep a
      // doctor role's permissions would do exactly that, since `kind` and
      // `roleId` are updated independently. Checked only when one of the two
      // actually changes, so a member who predates this rule can still have
      // their specialty or modules updated.
      if (updates.roleId !== undefined || updates.kind !== undefined) {
        const effectiveKind = (updates.kind as "doctor" | "staff" | undefined) ??
          (targetData.kind === "doctor" ? "doctor" : "staff");
        const effectivePerms = (updates.perms as string[] | undefined) ??
          normalizePerms(targetData.perms ?? []);
        const effectiveRoleId = (updates.roleId as string | undefined) ??
          String(targetData.roleId ?? "");
        assertStaffCannotWriteClinical(effectiveKind, effectivePerms, effectiveRoleId);
      }

      if (Object.keys(updates).length === 0) {
        return {success: true};
      }

      const batch = db.batch();
      batch.update(memberRef, updates);
      addAuditLog(batch, clinicId, caller.uid, "team.update", targetUid);
      await batch.commit();

      return {success: true};
    }

    case "removeMember": {
      const clinicId = String(data.clinicId ?? "").trim();
      const targetUid = String(data.uid ?? "").trim();
      if (!clinicId || !targetUid) {
        throw new HttpsError("invalid-argument", "clinicId and uid are required.");
      }

      const caller = await loadCaller(request, clinicId);
      requirePerm(caller, "team");

      if (targetUid === clinicId) {
        throw new HttpsError("invalid-argument", "Cannot remove clinic owner.");
      }
      if (targetUid === caller.uid) {
        throw new HttpsError("invalid-argument", "Cannot remove yourself.");
      }

      const memberRef = db.collection("clinics").doc(clinicId).collection("members").doc(targetUid);
      const memberSnap = await memberRef.get();
      if (!memberSnap.exists) {
        throw new HttpsError("not-found", "Member not found.");
      }
      const targetData = memberSnap.data() || {};

      if (targetData.roleId === "admin" || (Array.isArray(targetData.perms) && targetData.perms.includes("team"))) {
        checkEscalation(caller, targetData.roleId, targetData.perms);
      }

      const batch = db.batch();
      batch.update(memberRef, {
        active: false,
        removedAt: FieldValue.serverTimestamp(),
        removedBy: caller.uid,
      });

      const userRef = db.collection("users").doc(targetUid);
      const userSnap = await userRef.get();
      if (userSnap.exists && userSnap.data()?.clinicId === clinicId) {
        batch.update(userRef, {
          clinicId: FieldValue.delete(),
          memberKind: FieldValue.delete(),
        });
      }

      const sessionsSnap = await userRef.collection("active_sessions").get();
      for (const sessionDoc of sessionsSnap.docs) {
        batch.delete(sessionDoc.ref);
      }

      addAuditLog(batch, clinicId, caller.uid, "team.remove", targetUid);
      await batch.commit();

      try {
        await admin.auth().revokeRefreshTokens(targetUid);
      } catch (err) {
        console.error("Failed to revoke refresh tokens for", targetUid, err);
      }

      return {success: true};
    }

    case "saveRole": {
      const clinicId = String(data.clinicId ?? "").trim();
      const caller = await loadCaller(request, clinicId);
      requirePerm(caller, "team");

      const rawRoleId = data.roleId ? String(data.roleId).trim() : "";
      if (rawRoleId === "admin") {
        throw new HttpsError("invalid-argument", "Cannot modify admin role.");
      }

      const name = String(data.name ?? "").trim();
      if (name.length < 1 || name.length > 40) {
        throw new HttpsError("invalid-argument", "Role name must be between 1 and 40 characters.");
      }

      const kind = (data.kind === "doctor" ? "doctor" : "staff") as "doctor" | "staff";
      const perms = normalizePerms(data.perms);
      checkEscalation(caller, undefined, perms);
      assertStaffCannotWriteClinical(kind, perms, rawRoleId);

      const rolesRef = db.collection("clinics").doc(clinicId).collection("roles");
      const allRolesSnap = await rolesRef.get();

      for (const rDoc of allRolesSnap.docs) {
        if (rDoc.id === rawRoleId) continue;
        if ((rDoc.data().name || "").trim().toLowerCase() === name.toLowerCase()) {
          throw new HttpsError("already-exists", `A role named "${name}" already exists in this clinic.`);
        }
      }

      let targetRoleId = rawRoleId;
      let isNew = false;
      if (!targetRoleId) {
        if (allRolesSnap.size >= MAX_ROLES) {
          throw new HttpsError("resource-exhausted", `Max role limit of ${MAX_ROLES} reached.`);
        }
        targetRoleId = rolesRef.doc().id;
        isNew = true;
      } else {
        const existing = allRolesSnap.docs.find((d) => d.id === targetRoleId);
        // Editing a role changes everyone who holds it, so its current
        // permissions must be within the caller's too.
        if (existing) checkEscalation(caller, targetRoleId, existing.data().perms);
        const exists = existing !== undefined;
        if (!exists) {
          if (allRolesSnap.size >= MAX_ROLES) {
            throw new HttpsError("resource-exhausted", `Max role limit of ${MAX_ROLES} reached.`);
          }
          isNew = true;
        }
      }

      const targetRoleRef = rolesRef.doc(targetRoleId);
      await targetRoleRef.set({
        name,
        kind,
        perms,
        isSystem: false,
        updatedAt: FieldValue.serverTimestamp(),
      });

      if (!isNew) {
        const membersSnap = await db.collection("clinics").doc(clinicId)
          .collection("members")
          .where("roleId", "==", targetRoleId)
          .get();

        const memberDocs = membersSnap.docs;
        for (let i = 0; i < memberDocs.length; i += 400) {
          const chunk = memberDocs.slice(i, i + 400);
          const memberBatch = db.batch();
          for (const mDoc of chunk) {
            memberBatch.update(mDoc.ref, {
              roleName: name,
              perms,
            });
          }
          await memberBatch.commit();
        }
      }

      const auditBatch = db.batch();
      addAuditLog(auditBatch, clinicId, caller.uid, "role.save", targetRoleId);
      await auditBatch.commit();

      return {roleId: targetRoleId};
    }

    case "setAdminClinicalAccess": {
      const clinicId = String(data.clinicId ?? "").trim();
      const caller = await loadCaller(request, clinicId);

      // Owner only, on purpose. An admin who could grant this to themselves
      // would make the separation meaningless, and `team` is not enough:
      // handing out clinical access to the whole admin role is the clinic
      // owner's call.
      if (!caller.isOwner) {
        throw new HttpsError(
          "permission-denied",
          "Only the clinic owner may change whether admins can open clinical records."
        );
      }

      if (typeof data.enabled !== "boolean") {
        throw new HttpsError("invalid-argument", "enabled must be true or false.");
      }
      const enabled = data.enabled;

      const clinicRef = db.collection("clinics").doc(clinicId);
      if (!(await clinicRef.get()).exists) {
        throw new HttpsError("not-found", "Clinic not found.");
      }

      const batch = db.batch();
      batch.update(clinicRef, {
        adminClinicalAccess: enabled,
        adminClinicalAccessSetBy: caller.uid,
        adminClinicalAccessSetAt: FieldValue.serverTimestamp(),
      });
      addAuditLog(
        batch,
        clinicId,
        caller.uid,
        enabled ? "clinic.adminClinical.grant" : "clinic.adminClinical.revoke",
        clinicId
      );
      await batch.commit();

      return {success: true, adminClinicalAccess: enabled};
    }

    case "setClinicalAccessScope": {
      const clinicId = String(data.clinicId ?? "").trim();
      const caller = await loadCaller(request, clinicId);

      // Owner only, like adminClinicalAccess: deciding whether doctors are
      // confined to their own patients is not a day-to-day admin task.
      if (!caller.isOwner) {
        throw new HttpsError(
          "permission-denied",
          "Only the clinic owner may change how doctors reach patients."
        );
      }

      const scope = String(data.scope ?? "");
      if (scope !== "clinic" && scope !== "assigned") {
        throw new HttpsError(
          "invalid-argument",
          "scope must be 'clinic' or 'assigned'."
        );
      }

      const clinicRef = db.collection("clinics").doc(clinicId);
      if (!(await clinicRef.get()).exists) {
        throw new HttpsError("not-found", "Clinic not found.");
      }

      // Records written before the assignment copy existed have none, and a
      // scoped doctor's sync narrows on it. Bring them up to date *before*
      // scoping starts, so no doctor's records go missing in between.
      const recordsUpdated = scope === "assigned" ?
        await copyAssignmentsForClinic(clinicId) :
        0;

      const batch = db.batch();
      batch.update(clinicRef, {
        clinicalAccessScope: scope,
        clinicalAccessScopeSetBy: caller.uid,
        clinicalAccessScopeSetAt: FieldValue.serverTimestamp(),
      });
      addAuditLog(
        batch,
        clinicId,
        caller.uid,
        `clinic.clinicalScope.${scope}`,
        clinicId
      );
      await batch.commit();

      return {success: true, clinicalAccessScope: scope, recordsUpdated};
    }

    case "assignPatient": {
      const clinicId = String(data.clinicId ?? "").trim();
      const patientId = String(data.patientId ?? "").trim();
      if (!clinicId || !patientId) {
        throw new HttpsError(
          "invalid-argument",
          "clinicId and patientId are required."
        );
      }

      const caller = await loadCaller(request, clinicId);
      // Deciding who treats a patient is a scheduling act, so the front desk
      // can do it; it is not a way to reach clinical records.
      requirePerm(caller, "patients.edit");

      // This runs with admin rights, so it must not become the way around
      // scoping: a doctor confined to their own patients could otherwise
      // assign themselves to anyone. In a scoped clinic only the owner and
      // unscoped staff (the front desk, admins) decide who treats whom.
      if (!caller.isOwner) {
        const [callerMember, clinicSnap] = await Promise.all([
          db.collection("clinics").doc(clinicId)
            .collection("members").doc(caller.uid).get(),
          db.collection("clinics").doc(clinicId).get(),
        ]);
        const scoped = clinicSnap.data()?.clinicalAccessScope === "assigned";
        if (scoped && callerMember.data()?.kind === "doctor") {
          throw new HttpsError(
            "permission-denied",
            "In this clinic, patients are assigned by the front desk or the owner."
          );
        }
      }

      if (!Array.isArray(data.doctorUids)) {
        throw new HttpsError("invalid-argument", "doctorUids must be a list.");
      }
      const requested: string[] = Array.from(
        new Set<string>(
          (data.doctorUids as unknown[]).map((u) => String(u).trim())
        )
      ).filter((u) => u.length > 0);
      if (requested.length > 50) {
        throw new HttpsError(
          "invalid-argument",
          "A patient cannot be assigned to more than 50 doctors."
        );
      }

      const patientRef = db.collection("patients").doc(patientId);
      const patientSnap = await patientRef.get();
      if (!patientSnap.exists) {
        throw new HttpsError("not-found", "Patient not found.");
      }
      // Never let an assignment move a record between clinics.
      if (patientSnap.data()?.doctorId !== clinicId) {
        throw new HttpsError(
          "permission-denied",
          "That patient belongs to another clinic."
        );
      }

      // Only active doctors of this clinic may be assigned. The owner counts
      // as one; anyone else has to be a doctor-kind member.
      for (const uid of requested) {
        if (uid === clinicId) {
          // The owner can be assigned only if they treat patients.
          const clinicDoc = await db.collection("clinics").doc(clinicId).get();
          if (clinicDoc.data()?.ownerIsDoctor === false) {
            throw new HttpsError(
              "invalid-argument",
              "Only doctors can be assigned to a patient."
            );
          }
          continue;
        }
        const memberSnap = await db.collection("clinics").doc(clinicId)
          .collection("members").doc(uid).get();
        const member = memberSnap.data();
        if (!memberSnap.exists || member?.active !== true) {
          throw new HttpsError(
            "invalid-argument",
            "Only active members of this clinic can be assigned."
          );
        }
        if (member?.kind !== "doctor") {
          throw new HttpsError(
            "invalid-argument",
            "Only doctors can be assigned to a patient."
          );
        }
      }

      const batch = db.batch();
      batch.update(patientRef, {
        assignedDoctorUids: requested,
        updatedAt: FieldValue.serverTimestamp(),
      });
      addAuditLog(batch, clinicId, caller.uid, "patient.assign", patientId);
      await batch.commit();

      return {success: true, assignedDoctorUids: requested};
    }

    case "declineInvite": {
      const clinicId = String(data.clinicId ?? "").trim();
      const inviteId = String(data.inviteId ?? "").trim();
      if (!clinicId || !inviteId) {
        throw new HttpsError("invalid-argument", "clinicId and inviteId are required.");
      }
      const inviteRef = db.collection("clinics").doc(clinicId).collection("invites").doc(inviteId);
      const inviteSnap = await inviteRef.get();
      const inbox = inboxRef(uid, inviteId);
      if (!inviteSnap.exists) {
        // Gone already: just tidy the inbox.
        await inbox.delete();
        return {success: true};
      }
      const invite = inviteSnap.data() || {};
      if (!inviteMatchesCaller(invite, request.auth.token as Record<string, unknown>)) {
        throw new HttpsError("permission-denied", "This invite isn't for you.");
      }
      const batch = db.batch();
      if (invite.status === "pending") {
        batch.update(inviteRef, {
          status: "declined",
          declinedBy: uid,
          declinedAt: FieldValue.serverTimestamp(),
        });
        addAuditLog(batch, clinicId, uid, "invite.decline", inviteId);
      }
      batch.delete(inbox);
      await batch.commit();
      return {success: true};
    }

    case "matchContacts": {
      // Which of the caller's phone contacts already use CruDoc, so an
      // admin can invite them in the app. Nothing sent here is stored: the
      // numbers are looked up and dropped. People who turned off "let
      // clinics find me" are never reported.
      const clinicId = String(data.clinicId ?? "").trim();
      const caller = await loadCaller(request, clinicId);
      requirePerm(caller, "team");

      if (!Array.isArray(data.phones)) {
        throw new HttpsError("invalid-argument", "phones must be a list.");
      }
      if (data.phones.length > MATCH_CONTACTS_PER_CALL) {
        throw new HttpsError(
          "invalid-argument",
          `Send at most ${MATCH_CONTACTS_PER_CALL} numbers at a time.`
        );
      }

      // Raw number as sent -> E.164, so the reply can name the caller's own
      // entries and the app never has to normalise the same way.
      const byE164 = new Map<string, string[]>();
      for (const raw of data.phones as unknown[]) {
        const e164 = normalizeContactPhone(raw);
        if (!e164) continue;
        const list = byE164.get(e164) ?? [];
        if (!list.includes(String(raw))) list.push(String(raw));
        byE164.set(e164, list);
      }

      // Rate limit by numbers checked per hour, so the check can't be used
      // to test every number there is.
      const limitRef = db.collection("rate_limits").doc(caller.uid);
      await db.runTransaction(async (tx) => {
        const snap = await tx.get(limitRef);
        const prev = snap.data()?.matchContacts || {};
        const now = Date.now();
        const windowStart = typeof prev.windowStart === "number" && now - prev.windowStart < 3600_000 ?
          prev.windowStart : now;
        const used = windowStart === prev.windowStart ? Number(prev.count || 0) : 0;
        if (used + byE164.size > MATCH_CONTACTS_PER_HOUR) {
          throw new HttpsError(
            "resource-exhausted",
            "That's a lot of contacts in one go. Try again in an hour."
          );
        }
        tx.set(limitRef, {matchContacts: {windowStart, count: used + byE164.size}}, {merge: true});
      });

      const numbers = [...byE164.keys()];
      const found = new Map<string, string>(); // e164 -> uid
      for (let i = 0; i < numbers.length; i += 100) {
        const chunk = numbers.slice(i, i + 100).map((phoneNumber) => ({phoneNumber}));
        const res = await admin.auth().getUsers(chunk);
        for (const u of res.users) {
          if (u.phoneNumber && u.uid !== caller.uid) found.set(u.phoneNumber, u.uid);
        }
      }
      if (found.size === 0) return {matches: []};

      const clinicRef = db.collection("clinics").doc(clinicId);
      const [members, invites, profiles] = await Promise.all([
        clinicRef.collection("members").where("active", "==", true).get(),
        clinicRef.collection("invites").where("status", "==", "pending").get(),
        Promise.all([...found.values()].map((u) => db.collection("users").doc(u).get())),
      ]);
      const memberUids = new Set(members.docs.map((d) => d.id));
      const now = Date.now();
      const invitedPhones = new Set<string>();
      for (const d of invites.docs) {
        const inv = d.data();
        const exp = inv.expiresAt?.toMillis ? inv.expiresAt.toMillis() :
          (inv.expiresAt ? new Date(inv.expiresAt).getTime() : 0);
        if (exp > now && inv.phone) invitedPhones.add(String(inv.phone));
      }
      const hidden = new Set(profiles.filter((p) => p.data()?.discoverable === false).map((p) => p.id));

      const matches: {phone: string; status: string}[] = [];
      for (const [e164, foundUid] of found) {
        if (hidden.has(foundUid)) continue;
        const status = memberUids.has(foundUid) ? "member" :
          invitedPhones.has(e164) ? "invited" : "available";
        for (const raw of byE164.get(e164) ?? []) matches.push({phone: raw, status});
      }
      return {matches};
    }

    case "deleteRole": {
      const clinicId = String(data.clinicId ?? "").trim();
      const roleId = String(data.roleId ?? "").trim();
      if (!clinicId || !roleId) {
        throw new HttpsError("invalid-argument", "clinicId and roleId are required.");
      }

      const caller = await loadCaller(request, clinicId);
      requirePerm(caller, "team");

      if (roleId === "admin") {
        throw new HttpsError("invalid-argument", "Cannot delete admin role.");
      }

      const roleRef = db.collection("clinics").doc(clinicId).collection("roles").doc(roleId);
      const roleSnap = await roleRef.get();
      if (!roleSnap.exists) {
        throw new HttpsError("not-found", "Role not found.");
      }

      const activeMemberSnap = await db.collection("clinics").doc(clinicId)
        .collection("members")
        .where("roleId", "==", roleId)
        .where("active", "==", true)
        .limit(1)
        .get();

      if (!activeMemberSnap.empty) {
        throw new HttpsError("failed-precondition", "Role is currently assigned to active members.");
      }

      const pendingInviteSnap = await db.collection("clinics").doc(clinicId)
        .collection("invites")
        .where("roleId", "==", roleId)
        .where("status", "==", "pending")
        .get();

      const now = Date.now();
      for (const invDoc of pendingInviteSnap.docs) {
        const invData = invDoc.data();
        const exp = invData.expiresAt?.toMillis ?
          invData.expiresAt.toMillis() :
          (invData.expiresAt ? new Date(invData.expiresAt).getTime() : 0);
        if (exp > now) {
          throw new HttpsError("failed-precondition", "Role is currently used by pending invites.");
        }
      }

      const batch = db.batch();
      batch.delete(roleRef);
      addAuditLog(batch, clinicId, caller.uid, "role.delete", roleId);
      await batch.commit();

      return {success: true};
    }

    default:
      throw new HttpsError("invalid-argument", `Unknown action: "${action}".`);
    }
  }
);

/** Keeps the clinic's plan in step with the owner's account (set by Super Admin). */
export const mirrorPlanToClinic = onDocumentWritten(
  {document: "users/{uid}", region: "asia-south1"},
  async (event) => {
    if (!event.data?.after.exists) return;
    const uid = event.params.uid;
    const clinicRef = admin.firestore().collection("clinics").doc(uid);
    const clinicSnap = await clinicRef.get();
    if (!clinicSnap.exists) return;

    const clinicData = clinicSnap.data() || {};
    const userData = event.data.after.data() || {};

    const update: Record<string, unknown> = {};

    // enabledModules
    if (JSON.stringify(clinicData.enabledModules ?? null) !== JSON.stringify(userData.enabledModules ?? null)) {
      if (userData.enabledModules !== undefined) {
        update.enabledModules = userData.enabledModules;
      } else {
        update.enabledModules = FieldValue.delete();
      }
    }

    // status
    if ((clinicData.status ?? null) !== (userData.status ?? null)) {
      if (userData.status !== undefined) {
        update.status = userData.status;
      } else {
        update.status = FieldValue.delete();
      }
    }

    // expiresDate
    const clinicExp = clinicData.expiresDate?.toMillis ?
      clinicData.expiresDate.toMillis() :
      clinicData.expiresDate;
    const userExp = userData.expiresDate?.toMillis ?
      userData.expiresDate.toMillis() :
      userData.expiresDate;
    if (clinicExp !== userExp) {
      if (userData.expiresDate !== undefined) {
        update.expiresDate = userData.expiresDate;
      } else {
        update.expiresDate = FieldValue.delete();
      }
    }

    // subscriptionPlan
    if ((clinicData.subscriptionPlan ?? null) !== (userData.subscriptionPlan ?? null)) {
      if (userData.subscriptionPlan !== undefined) {
        update.subscriptionPlan = userData.subscriptionPlan;
      } else {
        update.subscriptionPlan = FieldValue.delete();
      }
    }

    if (Object.keys(update).length > 0) {
      await clinicRef.update(update);
    }
  }
);
