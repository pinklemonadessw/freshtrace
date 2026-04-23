/**
 * One-off bootstrap script to grant (or revoke) the `admin` Firebase Auth
 * custom claim on a user. Run locally with a service-account key.
 *
 * Usage:
 *   cd functions
 *   GOOGLE_APPLICATION_CREDENTIALS=./service-account.json \
 *     node scripts/grant-admin.js <uid> [--revoke]
 *
 * After running:
 *   1. Sign out and back in on the device (or call
 *      FirebaseAuth.instance.currentUser.getIdToken(true) in-app) so the
 *      client's cached ID token picks up the new claim.
 *   2. Delete the service-account JSON when you're done.
 *
 * Note: this script mirrors the claim into `users/{uid}.isAdmin` for UI
 * gating, matching what the `setAdminClaim` Cloud Function does.
 */

const admin = require("firebase-admin");

const [, , uid, flag] = process.argv;
if (!uid) {
  console.error("Usage: node scripts/grant-admin.js <uid> [--revoke]");
  process.exit(1);
}
const makeAdmin = flag !== "--revoke";

admin.initializeApp();

(async () => {
  try {
    await admin.auth().setCustomUserClaims(uid, { admin: makeAdmin });
    await admin
      .firestore()
      .collection("users")
      .doc(uid)
      .set({ isAdmin: makeAdmin }, { merge: true });

    console.log(
      `${makeAdmin ? "Granted" : "Revoked"} admin for uid=${uid}.\n` +
        "Sign out and back in on the device to refresh the ID token."
    );
    process.exit(0);
  } catch (err) {
    console.error("Failed:", err);
    process.exit(1);
  }
})();
