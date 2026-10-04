import {setGlobalOptions} from "firebase-functions/v2";
import * as admin from "firebase-admin";

if (!admin.apps.length) {
  admin.initializeApp();
}

setGlobalOptions({
  region: "asia-south1",
  maxInstances: 10,
});

export * from "./super-admin";
export * from "./appointments";
// WhatsApp endpoints are off until WhatsApp is set up; see
// whatsapp-endpoints.ts.
export * from "./ai";
export * from "./imaging";
