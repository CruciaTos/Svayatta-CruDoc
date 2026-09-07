import { createDownloadUrl } from "./s3";

async function testDownloadUrl() {
  try {
    const result = await createDownloadUrl(
      "doctors/test-doctor-123/patients/test-patient-456/documents/test-document-789.txt"
    );

    console.log("Download URL generated successfully!");
    console.log(result.url);
  } catch (error) {
    console.error("Download URL generation failed:", error);
  }
}

testDownloadUrl();