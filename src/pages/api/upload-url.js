import { S3Client, PutObjectCommand } from "@aws-sdk/client-s3";
import { getSignedUrl } from "@aws-sdk/s3-request-presigner";
import { verifyAuth } from "../../lib/auth.js";
import { randomUUID } from "crypto";

export const prerender = false;

const BUCKET = process.env.S3_MEDIA_BUCKET;
const REGION = process.env.AWS_REGION || "us-east-1";
const CDN_URL = process.env.MEDIA_CDN_URL || "";

export async function POST({ request }) {
  const auth = await verifyAuth(request);
  if (!auth.ok) {
    return new Response(JSON.stringify({ error: auth.error }), {
      status: 401,
      headers: { "Content-Type": "application/json" },
    });
  }

  if (!BUCKET) {
    return new Response(
      JSON.stringify({ error: "S3_MEDIA_BUCKET environment variable is not configured." }),
      { status: 500, headers: { "Content-Type": "application/json" } }
    );
  }

  try {
    const { filename, contentType } = await request.json();
    if (!filename || !contentType) {
      return new Response(
        JSON.stringify({ error: "filename and contentType are required" }),
        { status: 400, headers: { "Content-Type": "application/json" } }
      );
    }

    const ext = filename.split(".").pop();
    const uniqueName = `${randomUUID()}.${ext}`;
    const key = `originals/${uniqueName}`;
    const thumbKey = `thumbnails/${uniqueName}`;

    const s3 = new S3Client({ region: REGION });
    const command = new PutObjectCommand({
      Bucket: BUCKET,
      Key: key,
      ContentType: contentType,
    });

    const uploadUrl = await getSignedUrl(s3, command, { expiresIn: 300 });

    const originalUrl = CDN_URL ? `${CDN_URL}/${key}` : `https://${BUCKET}.s3.${REGION}.amazonaws.com/${key}`;
    const thumbnailUrl = CDN_URL ? `${CDN_URL}/${thumbKey}` : `https://${BUCKET}.s3.${REGION}.amazonaws.com/${thumbKey}`;

    return new Response(
      JSON.stringify({
        uploadUrl,
        originalUrl,
        thumbnailUrl,
        key,
      }),
      { status: 200, headers: { "Content-Type": "application/json" } }
    );
  } catch (err) {
    return new Response(JSON.stringify({ error: err.message }), {
      status: 500,
      headers: { "Content-Type": "application/json" },
    });
  }
}
