import fp from 'fastify-plugin';
import { applicationDefault, cert, getApps, initializeApp } from 'firebase-admin/app';
import { getAuth } from 'firebase-admin/auth';

function firebaseApp() {
  if (getApps().length) return getApps()[0];
  const privateKey = process.env.FIREBASE_PRIVATE_KEY?.replace(/\\n/g, '\n');
  const credential = privateKey && process.env.FIREBASE_CLIENT_EMAIL
    ? cert({ projectId: process.env.FIREBASE_PROJECT_ID, clientEmail: process.env.FIREBASE_CLIENT_EMAIL, privateKey })
    : applicationDefault();
  return initializeApp({ credential, projectId: process.env.FIREBASE_PROJECT_ID });
}

export default fp(async function authPlugin(app, options) {
  const mode = options.mode ?? process.env.AUTH_MODE ?? 'dev';

  app.decorateRequest('actor', null);
  app.decorate('authenticate', async function authenticate(request, reply) {
    if (mode === 'dev') {
      const id = request.headers['x-dev-user-id'] ?? 'user_owner';
      request.actor = await app.store.getUserById(id);
      if (!request.actor) return reply.code(401).send({ code: 'UNKNOWN_DEV_USER', message: 'Unknown development user' });
      return;
    }

    const token = request.headers.authorization?.match(/^Bearer (.+)$/)?.[1];
    if (!token) return reply.code(401).send({ code: 'UNAUTHENTICATED', message: 'Bearer token required' });
    try {
      const decoded = await getAuth(firebaseApp()).verifyIdToken(token, true);
      request.actor = await app.store.getUserByFirebaseUid(decoded.uid, decoded.email);
      if (!request.actor) return reply.code(403).send({ code: 'INVITE_REQUIRED', message: 'This account has not been invited' });
    } catch {
      return reply.code(401).send({ code: 'INVALID_TOKEN', message: 'Token is invalid or revoked' });
    }
  });
});
