import fp from 'fastify-plugin';
import { createRemoteJWKSet, jwtVerify } from 'jose';
import { URL } from 'node:url';

const authKeys = createRemoteJWKSet(
  new URL('https://www.googleapis.com/service_accounts/v1/jwk/securetoken@system.gserviceaccount.com'),
);
const appCheckKeys = createRemoteJWKSet(
  new URL('https://firebaseappcheck.googleapis.com/v1/jwks'),
);

function requireEnvironment(name) {
  const value = process.env[name];
  if (!value) throw new Error(`${name} must be configured for Firebase authentication`);
  return value;
}

async function verifyFirebaseIdToken(token) {
  const projectId = requireEnvironment('FIREBASE_PROJECT_ID');
  const { payload, protectedHeader } = await jwtVerify(token, authKeys, {
    algorithms: ['RS256'],
    audience: projectId,
    issuer: `https://securetoken.google.com/${projectId}`,
  });
  const now = Math.floor(Date.now() / 1000);
  if (protectedHeader.typ && protectedHeader.typ !== 'JWT') throw new Error('Invalid token type');
  if (!payload.sub || payload.sub.length > 128) throw new Error('Invalid token subject');
  if (typeof payload.iat !== 'number' || payload.iat > now) throw new Error('Invalid issued-at time');
  if (typeof payload.auth_time !== 'number' || payload.auth_time > now) throw new Error('Invalid authentication time');
  return payload;
}

async function verifyFirebaseAppCheck(token) {
  const projectNumber = requireEnvironment('FIREBASE_PROJECT_NUMBER');
  const { payload, protectedHeader } = await jwtVerify(token, appCheckKeys, {
    algorithms: ['RS256'],
    audience: `projects/${projectNumber}`,
    issuer: `https://firebaseappcheck.googleapis.com/${projectNumber}`,
  });
  if (protectedHeader.typ !== 'JWT') throw new Error('Invalid App Check token type');
  const allowedApps = (process.env.FIREBASE_APP_IDS ?? '').split(',').filter(Boolean);
  if (allowedApps.length && (!payload.sub || !allowedApps.includes(payload.sub))) {
    throw new Error('App is not allowed');
  }
  return payload;
}

const selfProvisionEnabled = () => /^(1|true|yes)$/i.test(process.env.TENANT_SELF_PROVISION ?? '');

// Why a first-time sign-in did not get its own household, or null to go ahead.
async function provisioningBlockedBy(store, email) {
  if (!selfProvisionEnabled()) return 'TENANT_SELF_PROVISION is not enabled';
  // Someone invited to an existing book must join that book, not start a
  // separate household they would then have to abandon.
  if (await store.hasPendingInvitation(email)) return 'an invitation to an existing book is outstanding';
  // A profile on this email with a different Firebase uid means the seeded
  // placeholder was never replaced, or the account was recreated in Firebase.
  // Provisioning would collide on the unique email column.
  if (await store.getUserByEmail(email)) return 'another account already uses this email address';
  return null;
}

export default fp(async function authPlugin(app, options) {
  // Defaults to firebase. Dev mode trusts an x-dev-user-id header with no token
  // at all, so it has to be asked for explicitly - a missing or misspelt
  // NODE_ENV must never be the only thing standing between this and an open API.
  const mode = options.mode ?? process.env.AUTH_MODE ?? 'firebase';

  if (mode !== 'firebase' && process.env.NODE_ENV === 'production') {
    throw new Error('Production refuses to start unless AUTH_MODE=firebase');
  }
  if (mode === 'dev') {
    app.log?.warn('AUTH_MODE=dev: any request can claim any user with an x-dev-user-id header. Never expose this port.');
  }

  app.decorateRequest('actor', null);
  app.decorate('authenticate', async function authenticate(request, reply) {
    if (mode === 'dev') {
      const id = request.headers['x-dev-user-id'] ?? 'user_owner';
      request.actor = await app.store.getUserById(id);
      if (!request.actor) {
        return reply.code(401).send({ code: 'UNKNOWN_DEV_USER', message: 'Unknown development user' });
      }
      return;
    }

    const token = request.headers.authorization?.match(/^Bearer (.+)$/)?.[1];
    if (!token) return reply.code(401).send({ code: 'UNAUTHENTICATED', message: 'Bearer token required' });
    try {
      if ((process.env.APP_CHECK_MODE ?? 'enforce') === 'enforce') {
        const appCheckToken = request.headers['x-firebase-appcheck'];
        if (!appCheckToken || Array.isArray(appCheckToken)) {
          return reply.code(401).send({ code: 'APP_CHECK_REQUIRED', message: 'Firebase App Check token required' });
        }
        await verifyFirebaseAppCheck(appCheckToken);
      }
      const decoded = await verifyFirebaseIdToken(token);
      request.actor = await app.store.getUserByFirebaseUid(decoded.sub, decoded.email);
      const isInvitationAcceptance = request.method === 'POST' && request.url.split('?')[0] === '/v1/invitations/accept';
      const verifiedEmail = decoded.email_verified === true && typeof decoded.email === 'string';
      if (!request.actor && isInvitationAcceptance && verifiedEmail) {
        request.actor = { firebaseUid: decoded.sub, email: decoded.email, displayName: typeof decoded.name === 'string' ? decoded.name : null, provisional: true };
      }
      // A Firebase identity nobody has invited gets a household of its own.
      //
      // Deliberately NOT gated on a verified email. Accounts created from the
      // Firebase console - the intended way to invite someone - are always
      // unverified, and verification would not stop a self-registration anyway:
      // an attacker verifies their own address. Disabling public sign-up in the
      // Firebase project is the control that matters, which is why
      // TENANT_SELF_PROVISION is off until the operator has done it.
      if (!request.actor && !isInvitationAcceptance && typeof decoded.email === 'string') {
        const blocked = await provisioningBlockedBy(app.store, decoded.email);
        if (blocked) {
          // A 403 with no explanation sent us to the browser last time to find
          // out why. Say it here instead.
          request.log.warn({ email: decoded.email, reason: blocked }, 'Not provisioning a household');
        } else {
          request.actor = await app.store.provisionTenant({ firebaseUid: decoded.sub, email: decoded.email, displayName: typeof decoded.name === 'string' ? decoded.name : null });
          request.log.info({ email: decoded.email, userId: request.actor.id }, 'Provisioned a new household for a first-time sign-in');
        }
      }
      if (!request.actor || request.actor.disabledAt) {
        return reply.code(403).send({ code: 'INVITE_REQUIRED', message: 'This account is not active in a workspace' });
      }
    } catch (error) {
      // The client is told nothing beyond "invalid", but the operator needs the
      // reason: a wrong FIREBASE_PROJECT_ID, an unreachable JWKS endpoint and a
      // genuinely expired token are indistinguishable without it. The token
      // itself is never logged.
      request.log.warn({ reason: error?.message, code: error?.code }, 'Firebase token verification failed');
      return reply.code(401).send({ code: 'INVALID_TOKEN', message: 'Token is invalid or expired' });
    }
  });
});
