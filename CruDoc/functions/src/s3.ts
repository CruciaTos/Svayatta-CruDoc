import {
  GetObjectCommand,
  PutObjectCommand,
  S3Client,
} from "@aws-sdk/client-s3";

import { getSignedUrl } from "@aws-sdk/s3-request-presigner";

const isDevelopment = process.env.NODE_ENV !== "production";

export const s3Client = new S3Client({
  region: process.env.AWS_REGION || "us-east-1",

  credentials: {
    accessKeyId: process.env.AWS_ACCESS_KEY_ID || "test",
    secretAccessKey: process.env.AWS_SECRET_ACCESS_KEY || "test",
  },

  ...(isDevelopment && {
    endpoint: process.env.AWS_S3_ENDPOINT || "http://127.0.0.1:4566",
    forcePathStyle: true,
  }),
});

//upload logic to s3 bucket
export async function uploadObject(
  key: string,
  body: Buffer | Uint8Array | string,
  contentType: string
) {
  const bucket = process.env.AWS_S3_BUCKET;

  if (!bucket) {
    throw new Error("AWS_S3_BUCKET is not configured");
  }

  const command = new PutObjectCommand({
    Bucket: bucket,
    Key: key,
    Body: body,
    ContentType: contentType,
  });

  await s3Client.send(command);

  return {
    bucket,
    key,
  };
}
//Presigned url logic
export async function createUploadUrl(
  key: string,
  contentType: string
) {
  const bucket = process.env.AWS_S3_BUCKET;

  if (!bucket) {
    throw new Error("AWS_S3_BUCKET is not configured");
  }

  const command = new PutObjectCommand({
    Bucket: bucket,
    Key: key,
    ContentType: contentType,
  });

  const url = await getSignedUrl(s3Client, command, {
    expiresIn: 600,
  });

  return {
    url,
    bucket,
    key,
    expiresIn: 600,
  };
}
//Presigned download url logic
export async function createDownloadUrl(key: string) {
  const bucket = process.env.AWS_S3_BUCKET;

  if (!bucket) {
    throw new Error("AWS_S3_BUCKET is not configured");
  }

  const command = new GetObjectCommand({
    Bucket: bucket,
    Key: key,
  });

  const url = await getSignedUrl(s3Client, command, {
    expiresIn: 600,
  });

  return {
    url,
    bucket,
    key,
    expiresIn: 600,
  };
}