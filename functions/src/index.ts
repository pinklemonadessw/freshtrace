import {setGlobalOptions} from "firebase-functions";
import {onCall, HttpsError} from "firebase-functions/https";
import * as logger from "firebase-functions/logger";
import * as admin from "firebase-admin";

admin.initializeApp();
const db = admin.firestore();

setGlobalOptions({maxInstances: 10});

/**
 * Grants or revokes the admin custom claim on a user, and mirrors the
 * value into the user's Firestore doc for UI gating. Only callable by
 * an existing admin (bootstrap the first one manually with the Admin
 * SDK; see project README / docs).
 */
export const setAdminClaim = onCall(async (req) => {
  if (req.auth?.token.admin !== true) {
    throw new HttpsError("permission-denied", "Admins only");
  }

  const uid = req.data?.uid as string | undefined;
  const makeAdmin = req.data?.admin === true;
  if (!uid) throw new HttpsError("invalid-argument", "uid required");

  await admin.auth().setCustomUserClaims(uid, {admin: makeAdmin});
  await db.collection("users").doc(uid).set(
    {isAdmin: makeAdmin},
    {merge: true},
  );

  logger.info("setAdminClaim", {actor: req.auth.uid, uid, makeAdmin});
  return {ok: true};
});

/**
 * Recursively deletes a kitchen, its inventory, members, and clears
 * activeKitchenId on every user still pointing at it.
 *
 * Uses the Admin SDK so it bypasses security rules (safer and simpler
 * than a client cascade). Writes an auditLogs entry before destruction
 * so there's a record even if the recursive delete fails partway.
 */
export const adminDeleteKitchen = onCall(async (req) => {
  if (req.auth?.token.admin !== true) {
    throw new HttpsError("permission-denied", "Admins only");
  }

  const kitchenId = req.data?.kitchenId as string | undefined;
  if (!kitchenId) {
    throw new HttpsError("invalid-argument", "kitchenId required");
  }

  const kitchenRef = db.collection("kitchens").doc(kitchenId);
  const kitchenSnap = await kitchenRef.get();
  if (!kitchenSnap.exists) {
    throw new HttpsError("not-found", `Kitchen ${kitchenId} does not exist`);
  }

  // 1. Clear activeKitchenId on every user still pointing at this kitchen.
  const affectedUsers = await db
    .collection("users")
    .where("activeKitchenId", "==", kitchenId)
    .get();

  // Batched writes cap out at 500 ops; chunk defensively.
  for (let i = 0; i < affectedUsers.size; i += 400) {
    const chunk = affectedUsers.docs.slice(i, i + 400);
    const batch = db.batch();
    chunk.forEach((doc) => batch.update(doc.ref, {activeKitchenId: null}));
    await batch.commit();
  }

  // 2. Audit log BEFORE destruction.
  await db.collection("auditLogs").add({
    action: "adminDeleteKitchen",
    actorUid: req.auth.uid,
    kitchenId,
    kitchenName: kitchenSnap.data()?.name ?? null,
    clearedUsers: affectedUsers.size,
    at: admin.firestore.FieldValue.serverTimestamp(),
  });

  // 3. Recursive delete (walks inventory + members subcollections too).
  await db.recursiveDelete(kitchenRef);

  logger.info("kitchen deleted", {
    actor: req.auth.uid,
    kitchenId,
    clearedUsers: affectedUsers.size,
  });
  return {ok: true, clearedUsers: affectedUsers.size};
});
