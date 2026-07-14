/**
 * One-off migration for the tightened security rules. For every existing
 * kitchen this script:
 *   1. Sets `createdBy` to the owner member's uid if missing (required by
 *      the new kitchen validation rules).
 *   2. Creates the `inviteCodes/{code}` lookup doc pointing at the kitchen
 *      (the join flow now reads this instead of querying all kitchens).
 *
 * Run locally with a service-account key:
 *   cd functions
 *   GOOGLE_APPLICATION_CREDENTIALS=./service-account.json \
 *     node scripts/backfill-invite-codes.js
 *
 * Safe to re-run; existing docs are left untouched. Delete the
 * service-account JSON when you're done.
 */

const admin = require("firebase-admin");

admin.initializeApp();
const db = admin.firestore();

(async () => {
  try {
    const kitchens = await db.collection("kitchens").get();
    let updated = 0;

    for (const kitchen of kitchens.docs) {
      const data = kitchen.data();
      const changes = [];

      if (!data.createdBy) {
        const owners = await kitchen.ref
          .collection("members")
          .where("role", "==", "owner")
          .limit(1)
          .get();
        if (owners.empty) {
          console.warn(`Kitchen ${kitchen.id} has no owner; skipping createdBy.`);
        } else {
          await kitchen.ref.update({ createdBy: owners.docs[0].id });
          changes.push("createdBy");
        }
      }

      if (data.inviteCode) {
        const codeRef = db.collection("inviteCodes").doc(data.inviteCode);
        const codeDoc = await codeRef.get();
        if (!codeDoc.exists) {
          await codeRef.set({ kitchenId: kitchen.id });
          changes.push("inviteCodes doc");
        }
      } else {
        console.warn(`Kitchen ${kitchen.id} has no inviteCode; skipping lookup doc.`);
      }

      if (changes.length > 0) {
        updated++;
        console.log(`Kitchen ${kitchen.id}: added ${changes.join(", ")}`);
      }
    }

    console.log(`Done. ${kitchens.size} kitchens scanned, ${updated} updated.`);
    process.exit(0);
  } catch (err) {
    console.error("Failed:", err);
    process.exit(1);
  }
})();
