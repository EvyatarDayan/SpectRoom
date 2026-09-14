// Creates Auth + Firestore profiles for test1@yopmail.com … test50@yopmail.com
// Password: Password1
// Tagged with isTestUser=true and testAccountKey="test1-test50" for bulk delete.
//
// Usage: cd functions && node scripts/seedTestUsers.js

const https = require('https');
const fs = require('fs');
const path = require('path');

const PROJECT_ID = 'spectroom-553a0';
const TEST_ACCOUNT_KEY = 'test1-test50';
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

const FIRST_NAMES = [
  'Emma', 'Olivia', 'Astrid', 'Clara', 'Freja', 'Saga', 'Maja', 'Ella', 'Alma', 'Nora',
  'Liam', 'Noah', 'William', 'Lucas', 'Oliver', 'Hugo', 'Elias', 'Oscar', 'Axel', 'Leo',
  'Sofia', 'Isabella', 'Elin', 'Vera', 'Agnes', 'Ebba', 'Alice', 'Wilma', 'Selma', 'Tyra',
  'Viktor', 'Erik', 'Filip', 'Isak', 'Nils', 'Otto', 'Theo', 'Adam', 'Jonas', 'Melvin',
  'Nova', 'Liv', 'Indie', 'Meja', 'Lo', 'Juli', 'Ronja', 'Molly', 'Stella', 'Leah',
];

const LAST_NAMES = [
  'Andersson', 'Johansson', 'Karlsson', 'Nilsson', 'Eriksson', 'Larsson', 'Olsson',
  'Persson', 'Svensson', 'Gustafsson', 'Pettersson', 'Jonsson', 'Jansson', 'Hansson',
  'Bengtsson', 'Jönsson', 'Lindberg', 'Jakobsson', 'Magnusson', 'Olofsson', 'Lindström',
  'Lindqvist', 'Lindgren', 'Berg', 'Axelsson', 'Bergström', 'Lundberg', 'Lundgren',
  'Sandberg', 'Holm', 'Sjöberg', 'Forsberg', 'Hellström', 'Engström', 'Eklund',
];

const INTERESTS = [
  'Photography', 'Music', 'Art', 'Reading', 'Cooking', 'Travel', 'Sports', 'Gaming',
  'Movies', 'Nature', 'Technology', 'Fitness', 'Dancing', 'Writing', 'Gardening',
  'Animals', 'Science', 'History', 'Languages', 'Volunteering',
];

const GENDERS = ['Man', 'Woman', 'Non-binary'];
const LOOKING_FOR = ['Friendship', 'Relationship', 'Not sure yet'];
const LIFESTYLES = ['independent', 'familySupport', 'assistedSetting'];
const BODY_TYPES = ['slim', 'average', 'athletic', 'fullBodied'];
const FIRST_DATES = [
  'relaxingParkWalk',
  'cozyCafeMeet',
  'museumGalleryStroll',
  'cinemaMovieNight',
  'friendlyVideoChat',
];

const CITIES = [
  { city: 'Stockholm', latitude: 59.3293, longitude: 18.0686 },
  { city: 'Göteborg', latitude: 57.7089, longitude: 11.9746 },
  { city: 'Malmö', latitude: 55.6050, longitude: 13.0038 },
  { city: 'Uppsala', latitude: 59.8586, longitude: 17.6389 },
  { city: 'Västerås', latitude: 59.6099, longitude: 16.5448 },
  { city: 'Örebro', latitude: 59.2753, longitude: 15.2134 },
  { city: 'Linköping', latitude: 58.4108, longitude: 15.6214 },
  { city: 'Helsingborg', latitude: 56.0465, longitude: 12.6945 },
  { city: 'Jönköping', latitude: 57.7826, longitude: 14.1618 },
  { city: 'Norrköping', latitude: 58.5877, longitude: 16.1924 },
  { city: 'Lund', latitude: 55.7047, longitude: 13.1910 },
  { city: 'Umeå', latitude: 63.8258, longitude: 20.2630 },
  { city: 'Gävle', latitude: 60.6749, longitude: 17.1413 },
  { city: 'Borås', latitude: 57.7210, longitude: 12.9401 },
  { city: 'Sundsvall', latitude: 62.3908, longitude: 17.3069 },
];

const BIOS = [
  'Love exploring new cafés and weekend hikes. Looking for genuine conversations and shared adventures around the city.',
  'Music festivals, cooking experiments, and long walks by the water. Curious about people who light up a room quietly.',
  'Bookworm with a soft spot for board games and spontaneous road trips. Always up for trying a new recipe together.',
  'Fitness mornings, film nights, and learning languages. Hoping to meet someone kind, curious, and a little playful.',
  'Nature lover who also enjoys museum days. I value honesty, humor, and making ordinary Tuesdays feel special.',
  'Photographer at heart, traveler when I can be. Searching for friendship or something more with warm energy.',
  'Tech by day, painting and plants by night. Let’s trade stories over coffee and maybe a gallery stroll afterward.',
  'Dog walks, vinyl records, and spicy food challenges. Looking for someone open-minded who enjoys quiet evenings too.',
];

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
          ...(data ? { 'Content-Type': 'application/json', 'Content-Length': Buffer.byteLength(data) } : {}),
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

function pick(arr, rng) {
  return arr[Math.floor(rng() * arr.length)];
}

function pickN(arr, n, rng) {
  const copy = [...arr];
  const out = [];
  while (out.length < n && copy.length) {
    const idx = Math.floor(rng() * copy.length);
    out.push(copy.splice(idx, 1)[0]);
  }
  return out;
}

function mulberry32(seed) {
  return function () {
    let t = (seed += 0x6d2b79f5);
    t = Math.imul(t ^ (t >>> 15), t | 1);
    t ^= t + Math.imul(t ^ (t >>> 7), t | 61);
    return ((t ^ (t >>> 14)) >>> 0) / 4294967296;
  };
}

function firestoreValue(value) {
  if (value === null || value === undefined) return { nullValue: null };
  if (typeof value === 'string') return { stringValue: value };
  if (typeof value === 'boolean') return { booleanValue: value };
  if (typeof value === 'number') {
    if (Number.isInteger(value)) return { integerValue: String(value) };
    return { doubleValue: value };
  }
  if (Array.isArray(value)) {
    return { arrayValue: { values: value.map(firestoreValue) } };
  }
  if (typeof value === 'object') {
    const fields = {};
    for (const [k, v] of Object.entries(value)) {
      fields[k] = firestoreValue(v);
    }
    return { mapValue: { fields } };
  }
  throw new Error(`Unsupported value type: ${typeof value}`);
}

function toFirestoreFields(obj) {
  const fields = {};
  for (const [k, v] of Object.entries(obj)) {
    fields[k] = firestoreValue(v);
  }
  return fields;
}

function buildProfile(index) {
  const rng = mulberry32(1000 + index * 97);
  const gender = pick(GENDERS, rng);
  const interestedIn =
    gender === 'Man'
      ? pick([['Woman'], ['Woman', 'Non-binary'], ['Anyone']], rng)
      : gender === 'Woman'
        ? pick([['Man'], ['Man', 'Non-binary'], ['Anyone']], rng)
        : pick([['Anyone'], ['Man', 'Woman'], ['Non-binary']], rng);

  const age = 21 + Math.floor(rng() * 18); // 21–38
  const birthYear = new Date().getFullYear() - age;
  const birthMonth = 1 + Math.floor(rng() * 12);
  const birthDay = 1 + Math.floor(rng() * 28);
  const dateOfBirth = Date.UTC(birthYear, birthMonth - 1, birthDay) / 1000;

  const city = pick(CITIES, rng);
  const first = FIRST_NAMES[(index - 1) % FIRST_NAMES.length];
  const last = pick(LAST_NAMES, rng);
  const name = `${first} ${last}`;

  const preferredAgeMin = Math.max(18, age - 5 - Math.floor(rng() * 3));
  const preferredAgeMax = Math.min(60, age + 5 + Math.floor(rng() * 6));

  const photoSeed = `spectroom-test${index}`;
  const photos = [1, 2, 3].map(
    (n) => `https://picsum.photos/seed/${photoSeed}-${n}/800/1000`
  );
  const profilePhotoURL = `https://picsum.photos/seed/${photoSeed}-avatar/600/600`;

  return {
    name,
    email: `test${index}@yopmail.com`,
    age,
    dateOfBirth,
    bio: pick(BIOS, rng),
    interests: pickN(INTERESTS, 3 + Math.floor(rng() * 3), rng),
    gender,
    interestedIn,
    lookingFor: pickN(LOOKING_FOR, 1 + Math.floor(rng() * 2), rng),
    preferredAgeMin,
    preferredAgeMax,
    lifestyle: pick(LIFESTYLES, rng),
    shareLifestyle: rng() > 0.3,
    bodyType: pick(BODY_TYPES, rng),
    shareBodyType: rng() > 0.4,
    idealFirstDate: pickN(FIRST_DATES, 1 + Math.floor(rng() * 2), rng),
    shareIdealFirstDate: rng() > 0.35,
    energyLevel: Math.floor(rng() * 5),
    location: {
      displayString: `${city.city}, Sweden`,
      city: city.city,
      state: '',
      country: 'Sweden',
      latitude: city.latitude + (rng() - 0.5) * 0.04,
      longitude: city.longitude + (rng() - 0.5) * 0.04,
    },
    profilePhotoURL,
    photos,
    isOnline: false,
    lastSeen: Date.now() / 1000,
    appIsActive: false,
    unreadBadgeCount: 0,
    // Deletion markers
    isTestUser: true,
    testAccountKey: TEST_ACCOUNT_KEY,
    testAccountIndex: index,
  };
}

async function ensureAuthUser(email, password) {
  const signUp = await request(
    'POST',
    `https://identitytoolkit.googleapis.com/v1/accounts:signUp?key=${API_KEY}`,
    { email, password, returnSecureToken: true }
  );

  if (signUp.status === 200 && signUp.body.localId) {
    return {
      uid: signUp.body.localId,
      idToken: signUp.body.idToken,
      created: true,
    };
  }

  const errMsg = signUp.body?.error?.message || '';
  if (errMsg.includes('EMAIL_EXISTS')) {
    const signIn = await request(
      'POST',
      `https://identitytoolkit.googleapis.com/v1/accounts:signInWithPassword?key=${API_KEY}`,
      { email, password, returnSecureToken: true }
    );
    if (signIn.status !== 200 || !signIn.body.localId) {
      throw new Error(`Sign-in failed for ${email}: ${signIn.raw}`);
    }
    return {
      uid: signIn.body.localId,
      idToken: signIn.body.idToken,
      created: false,
    };
  }

  throw new Error(`Sign-up failed for ${email}: ${signUp.raw}`);
}

async function writeProfile(uid, idToken, profile) {
  const docName = `projects/${PROJECT_ID}/databases/(default)/documents/users/${uid}`;
  const res = await request(
    'POST',
    `https://firestore.googleapis.com/v1/projects/${PROJECT_ID}/databases/(default)/documents:commit`,
    {
      writes: [
        {
          update: {
            name: docName,
            fields: toFirestoreFields(profile),
          },
        },
      ],
    },
    { Authorization: `Bearer ${idToken}` }
  );

  if (res.status !== 200) {
    throw new Error(`Firestore write failed for ${uid}: ${res.raw}`);
  }
}

async function main() {
  console.log(`Creating ${COUNT} test profiles in ${PROJECT_ID}...`);
  console.log(`Tagged with testAccountKey="${TEST_ACCOUNT_KEY}" / isTestUser=true\n`);

  const summary = [];

  for (let i = 1; i <= COUNT; i++) {
    const email = `test${i}@yopmail.com`;
    const profile = buildProfile(i);
    process.stdout.write(`[${i}/${COUNT}] ${email} (${profile.name}) ... `);

    try {
      const auth = await ensureAuthUser(email, PASSWORD);
      await writeProfile(auth.uid, auth.idToken, profile);
      summary.push({
        index: i,
        email,
        uid: auth.uid,
        name: profile.name,
        created: auth.created,
      });
      console.log(auth.created ? 'created ✅' : 'updated ✅');
    } catch (error) {
      console.log('FAILED ❌');
      console.error(`  ${error.message}`);
      summary.push({ index: i, email, error: error.message });
    }

    // Gentle pacing to avoid rate limits
    await new Promise((r) => setTimeout(r, 120));
  }

  const outPath = path.join(__dirname, 'seedTestUsers.result.json');
  fs.writeFileSync(outPath, JSON.stringify(summary, null, 2));
  const ok = summary.filter((s) => !s.error).length;
  console.log(`\nDone: ${ok}/${COUNT} succeeded. Summary: ${outPath}`);
}

main().catch((error) => {
  console.error(error);
  process.exit(1);
});
