// Deletes Auth + Firestore users tagged as test1–test50.
// Looks up test1@yopmail.com … test50@yopmail.com via client Auth API,
// then deletes each Firestore profile with that user's token.
// Auth user deletion requires Admin credentials (optional if available).
//
// Usage: cd functions && node scripts/deleteTestUsers.js

const https = require('https');
const fs = require('fs');
const path = require('path');

const PROJECT_ID = 'spectroom-553a0';
const PASSWORD = 'Password1';
const COUNT = 50;

function readApiKey() {
  const plistPath = path.resolve(
    __dirname,
    '../../SpectRoom/GoogleService-Info.plist'
  );
  const plist = fs.readFileSync(plistPath, 'utf8');
  const match = plist.match(/<key>API_KEY<\/key>\s*<string>([^<]+)<\/string>/);
  if (!match) throw new Error(`API_KEY not found in ${plistPath}`);
  return match[1];
}

const API_KEY = readApiKey();

function request(method, url, body, headers = {}) {
  const data = body == null ? null : JSON.stringify(body);
  return new Promise((resolve, reject) => {
    const u = new URL(url);
    const req = https.request(
      {
        hostname: u.hostname,
        path: u.pathname + u.search,
        method,
        headers: {
          ...(data
            ? {
                'Content-Type': 'application/json',
                'Content-Length': Buffer.byteLength(data),
              }
            : {}),
          ...headers,
        },
      },
      (res) => {
        let chunks = '';
        res.on('data', (c) => (chunks += c));
        res.on('end', () => {
          let parsed = null;
          try {
            parsed = chunks ? JSON.parse(chunks) : null;
          } catch {
            parsed = { raw: chunks };
          }
          resolve({ status: res.statusCode, body: parsed, raw: chunks });
        });
      }
    );
    req.on('error', reject);
    if (data) req.write(data);
    req.end();
  });
}

async function signIn(email) {
  const res = await request(
    'POST',
    `https://identitytoolkit.googleapis.com/v1/accounts:signInWithPassword?key=${API_KEY}`,
    { email, password: PASSWORD, returnSecureToken: true }
  );
  if (res.status !== 200 || !res.body?.localId) {
    return null;
  }
  return { uid: res.body.localId, idToken: res.body.idToken };
}

async function deleteFirestoreProfile(uid, idToken) {
  const docName = `projects/${PROJECT_ID}/databases/(default)/documents/users/${uid}`;
  const res = await request(
    'POST',
    `https://firestore.googleapis.com/v1/projects/${PROJECT_ID}/databases/(default)/documents:commit`,
    {
      writes: [{ delete: docName }],
    },
    { Authorization: `Bearer ${idToken}` }
  );
  if (res.status !== 200) {
    throw new Error(`Firestore delete failed: ${res.raw}`);
  }
}

async function deleteAuthUser(idToken) {
  const res = await request(
    'POST',
    `https://identitytoolkit.googleapis.com/v1/accounts:delete?key=${API_KEY}`,
    { idToken }
  );
  if (res.status !== 200) {
    throw new Error(`Auth delete failed: ${res.raw}`);
  }
}

async function main() {
  console.log(`Deleting test1–test${COUNT} from ${PROJECT_ID}...\n`);
  let deleted = 0;
  let missing = 0;

  for (let i = 1; i <= COUNT; i++) {
    const email = `test${i}@yopmail.com`;
    process.stdout.write(`[${i}/${COUNT}] ${email} ... `);
    try {
      const auth = await signIn(email);
      if (!auth) {
        console.log('not found');
        missing += 1;
        continue;
      }
      await deleteFirestoreProfile(auth.uid, auth.idToken);
      await deleteAuthUser(auth.idToken);
      deleted += 1;
      console.log('deleted ✅');
    } catch (error) {
      console.log('FAILED ❌');
      console.error(`  ${error.message}`);
    }
    await new Promise((r) => setTimeout(r, 120));
  }

  console.log(`\nDone: deleted ${deleted}, missing ${missing}.`);
}

main().catch((error) => {
  console.error(error);
  process.exit(1);
});
