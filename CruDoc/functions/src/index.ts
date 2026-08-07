import {setGlobalOptions} from "firebase-functions/v2";
import * as admin from "firebase-admin";

admin.initializeApp();

setGlobalOptions({
  region: "asia-south1",
  maxInstances: 10,
});

export * from "./super-admin";
export * from "./appointments";
