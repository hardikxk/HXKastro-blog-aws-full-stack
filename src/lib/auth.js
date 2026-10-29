import { CognitoJwtVerifier } from "aws-jwt-verify";

let verifier = null;

function getVerifier() {
  const userPoolId = process.env.COGNITO_USER_POOL_ID;
  const clientId = process.env.COGNITO_CLIENT_ID;

  if (!userPoolId || !clientId) {
    return null;
  }

  if (!verifier) {
    verifier = CognitoJwtVerifier.create({
      userPoolId,
      tokenUse: "id",
      clientId,
    });
  }
  return verifier;
}

/**
 * Verify authorization header from request.
 * Expected: "Bearer <token>"
 */
export async function verifyAuth(request) {
  const authHeader = request.headers.get("authorization") || "";
  const token = authHeader.replace(/^Bearer\s+/i, "").trim();

  if (!token) {
    return { ok: false, error: "Missing Authorization token" };
  }

  // If running in development without Cognito configured, allow dev bypass
  if (!process.env.COGNITO_USER_POOL_ID) {
    return { ok: true, payload: { "cognito:username": "local-admin" } };
  }

  try {
    const v = getVerifier();
    if (!v) {
      return { ok: false, error: "Cognito verifier not configured" };
    }
    const payload = await v.verify(token);
    return { ok: true, payload };
  } catch (err) {
    return { ok: false, error: err.message || "Invalid token" };
  }
}
