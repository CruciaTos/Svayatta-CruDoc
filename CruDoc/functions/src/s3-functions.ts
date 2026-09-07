import {onCall, HttpsError} from "firebase-functions/v2/https";
import {createDownloadUrl, createUploadUrl} from "./s3";

export const getS3DownloadUrl = onCall(
  {
    region: "asia-south1",
  },
  async (request) => {
    if (!request.auth) {
      throw new HttpsError(
        "unauthenticated",
        "You must be logged in to access documents.",
      );
    }

    const {objectKey} = request.data;

    if (!objectKey || typeof objectKey !== "string") {
      throw new HttpsError(
        "invalid-argument",
        "objectKey is required.",
      );
    }

    const url = await createDownloadUrl(objectKey);

    return {
      url,
    };
  },
);

export const getS3UploadUrl = onCall(
  {
    region: "asia-south1",
  },
  async (request) => {
    if (!request.auth) {
      throw new HttpsError(
        "unauthenticated",
        "You must be logged in to upload documents.",
      );
    }

    const {objectKey, contentType} = request.data;

    if (!objectKey || typeof objectKey !== "string") {
      throw new HttpsError(
        "invalid-argument",
        "objectKey is required.",
      );
    }

    if (!contentType || typeof contentType !== "string") {
      throw new HttpsError(
        "invalid-argument",
        "contentType is required.",
      );
    }

    const result = await createUploadUrl(
      objectKey,
      contentType,
    );

    return {
      url: result.url,
      bucket: result.bucket,
      key: result.key,
      expiresIn: result.expiresIn,
    };
  },
);