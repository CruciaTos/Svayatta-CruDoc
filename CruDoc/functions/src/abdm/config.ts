import {defineSecret} from "firebase-functions/params";

export const abdmClientId = defineSecret("ABDM_CLIENT_ID");
export const abdmClientSecret = defineSecret("ABDM_CLIENT_SECRET");
export const abdmCallbackKey = defineSecret("ABDM_CALLBACK_KEY");

export type AbdmEnv = "sandbox" | "production";

export interface AbdmConfig {
  env: AbdmEnv;
  gatewayBaseUrl: string;
  abhaBaseUrl: string;
  cmId: string;
  qrBaseUrl: string;
}

export function getAbdmConfig(envOverride?: string): AbdmConfig {
  const raw = (envOverride ?? process.env.ABDM_ENV ?? "sandbox").trim().toLowerCase();
  const env: AbdmEnv = raw === "production" || raw === "prod" ? "production" : "sandbox";
  if (env === "production") {
    return {
      env,
      gatewayBaseUrl: "https://apis.abdm.gov.in/api/hiecm",
      abhaBaseUrl: "https://abha.abdm.gov.in/api/abha/v3",
      cmId: "abdm",
      // Unconfirmed production QR host.
      qrBaseUrl: "https://phr.abdm.gov.in/share-profile",
    };
  }
  return {
    env: "sandbox",
    gatewayBaseUrl: "https://dev.abdm.gov.in/api/hiecm",
    abhaBaseUrl: "https://abhasbx.abdm.gov.in/abha/api/v3",
    cmId: "sbx",
    qrBaseUrl: "https://phrsbx.abdm.gov.in/share-profile",
  };
}
