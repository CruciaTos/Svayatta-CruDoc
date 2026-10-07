import {onCall, HttpsError, CallableRequest} from "firebase-functions/v2/https";
import {onDocumentWritten} from "firebase-functions/v2/firestore";
import * as admin from "firebase-admin";

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
    return {
      uid,
      clinicId,
      isOwner: true,
      isAdmin: true,
      perms: [...PERMS],
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
  const perms = isAdmin ? [...PERMS] : normalizePerms(data.perms ?? []);
  return {
    uid,
    clinicId,
    isOwner: false,
    isAdmin,
    perms,
  };
}

/** isAdmin or perms includes perm. */
export function requirePerm(c: Caller, perm: string): void {
  if (c.isAdmin) return;
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
    at: admin.firestore.FieldValue.serverTimestamp(),
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
            joinedAt: admin.firestore.FieldValue.serverTimestamp(),
          });
        }

        if (needsUserClinicId) {
          batch.set(userRef, {clinicId: uid, memberKind: "owner"}, {merge: true});
        }

        addAuditLog(batch, uid, uid, "team.create", uid);
        await batch.commit();
        return {clinicId: uid};
      }

      const batch = db.batch();
      const clinicPayload: Record<string, unknown> = {
        name: clinicName,
        specialty,
        ownerUid: uid,
        seats: DEFAULT_SEATS,
        createdAt: admin.firestore.FieldValue.serverTimestamp(),
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
          updatedAt: admin.firestore.FieldValue.serverTimestamp(),
        });
      }

      const memberRef = clinicRef.collection("members").doc(uid);
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
        joinedAt: admin.firestore.FieldValue.serverTimestamp(),
      });

      batch.set(userRef, {clinicId: uid, memberKind: "owner"}, {merge: true});
      addAuditLog(batch, uid, uid, "team.create", uid);
      await batch.commit();

      return {clinicId: uid};
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
      for (const doc of invitesMap.values()) {
        const invData = doc.data();
        const exp = invData.expiresAt?.toMillis ?
          invData.expiresAt.toMillis() :
          (invData.expiresAt ? new Date(invData.expiresAt).getTime() : 0);
        if (exp > now) {
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
          joinedAt: admin.firestore.FieldValue.serverTimestamp(),
          invitedBy: inviteData.invitedBy || "",
        };

        if (inviteData.modules !== undefined && inviteData.modules !== null) {
          memberData.modules = inviteData.modules;
        }
        if (kind === "doctor" && inviteData.dentalFeatures !== undefined && inviteData.dentalFeatures !== null) {
          memberData.dentalFeatures = inviteData.dentalFeatures;
        }

        transaction.set(memberRef, memberData);
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
        if (!userData.createdAt) userUpdate.createdAt = admin.firestore.FieldValue.serverTimestamp();

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
        createdAt: admin.firestore.FieldValue.serverTimestamp(),
        expiresAt: admin.firestore.Timestamp.fromDate(expiresAt),
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
      batch.set(inviteRef, invitePayload);
      addAuditLog(batch, clinicId, caller.uid, "team.invite", inviteRef.id);
      await batch.commit();

      return {inviteId: inviteRef.id};
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
          updates.modules = admin.firestore.FieldValue.delete();
        } else {
          const norm = normalizeModules(data.modules);
          updates.modules = norm !== null ? norm : admin.firestore.FieldValue.delete();
        }
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
        removedAt: admin.firestore.FieldValue.serverTimestamp(),
        removedBy: caller.uid,
      });

      const userRef = db.collection("users").doc(targetUid);
      const userSnap = await userRef.get();
      if (userSnap.exists && userSnap.data()?.clinicId === clinicId) {
        batch.update(userRef, {
          clinicId: admin.firestore.FieldValue.delete(),
          memberKind: admin.firestore.FieldValue.delete(),
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
        updatedAt: admin.firestore.FieldValue.serverTimestamp(),
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
        update.enabledModules = admin.firestore.FieldValue.delete();
      }
    }

    // status
    if ((clinicData.status ?? null) !== (userData.status ?? null)) {
      if (userData.status !== undefined) {
        update.status = userData.status;
      } else {
        update.status = admin.firestore.FieldValue.delete();
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
        update.expiresDate = admin.firestore.FieldValue.delete();
      }
    }

    // subscriptionPlan
    if ((clinicData.subscriptionPlan ?? null) !== (userData.subscriptionPlan ?? null)) {
      if (userData.subscriptionPlan !== undefined) {
        update.subscriptionPlan = userData.subscriptionPlan;
      } else {
        update.subscriptionPlan = admin.firestore.FieldValue.delete();
      }
    }

    if (Object.keys(update).length > 0) {
      await clinicRef.update(update);
    }
  }
);
