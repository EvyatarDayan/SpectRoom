// Updates every user document's `location` to a valid Stockholm address.
// Assigns addresses round-robin from a curated pool of real Stockholm streets.
//
// Setup (one-time):
//   1. Firebase Console → Project settings → Service accounts
//   2. "Generate new private key" → save as:
//        functions/serviceAccountKey.json
//   3. Do NOT commit that file
//
// Usage:
//   cd functions
//   node scripts/setStockholmAddresses.js --dry-run   # preview only
//   node scripts/setStockholmAddresses.js             # write to Firestore
//
// Or point at any key file:
//   GOOGLE_APPLICATION_CREDENTIALS=/path/to/key.json node scripts/setStockholmAddresses.js --dry-run

const fs = require('fs');
const path = require('path');
const admin = require('firebase-admin');

const PROJECT_ID = 'spectroom-553a0';
const DRY_RUN = process.argv.includes('--dry-run');

function resolveServiceAccountPath() {
  const candidates = [
    process.env.GOOGLE_APPLICATION_CREDENTIALS,
    path.resolve(__dirname, '../serviceAccountKey.json'),
    path.resolve(__dirname, '../service-account.json'),
    path.resolve(__dirname, '../../serviceAccountKey.json'),
  ].filter(Boolean);

  for (const candidate of candidates) {
    if (fs.existsSync(candidate)) {
      return candidate;
    }
  }
  return null;
}

function initAdmin() {
  const keyPath = resolveServiceAccountPath();
  if (!keyPath) {
    console.error(`
❌ Missing Firebase Admin credentials.

This script needs a service account JSON key (local ADC is not set up).

One-time setup:
  1. Open https://console.firebase.google.com/project/${PROJECT_ID}/settings/serviceaccounts/adminsdk
  2. Click "Generate new private key"
  3. Save the file as:
       ${path.resolve(__dirname, '../serviceAccountKey.json')}
  4. Re-run:
       node scripts/setStockholmAddresses.js --dry-run

Or set:
  export GOOGLE_APPLICATION_CREDENTIALS=/absolute/path/to/your-key.json
`);
    process.exit(1);
  }

  const serviceAccount = JSON.parse(fs.readFileSync(keyPath, 'utf8'));
  admin.initializeApp({
    credential: admin.credential.cert(serviceAccount),
    projectId: PROJECT_ID,
  });
  console.log(`🔑 Using credentials: ${keyPath}\n`);
}

initAdmin();

const db = admin.firestore();

/** Real Stockholm addresses with approximate WGS84 coordinates. */
const STOCKHOLM_ADDRESSES = [
  { displayString: 'Drottninggatan 45, 111 21 Stockholm, Sweden', city: 'Stockholm', latitude: 59.3326, longitude: 18.0649 },
  { displayString: 'Sveavägen 68, 111 34 Stockholm, Sweden', city: 'Stockholm', latitude: 59.3402, longitude: 18.0568 },
  { displayString: 'Kungsgatan 30, 111 35 Stockholm, Sweden', city: 'Stockholm', latitude: 59.3348, longitude: 18.0622 },
  { displayString: 'Birger Jarlsgatan 18, 114 34 Stockholm, Sweden', city: 'Stockholm', latitude: 59.3389, longitude: 18.0731 },
  { displayString: 'Östermalmsgatan 87, 114 59 Stockholm, Sweden', city: 'Stockholm', latitude: 59.3435, longitude: 18.0876 },
  { displayString: 'Karlavägen 58, 114 49 Stockholm, Sweden', city: 'Stockholm', latitude: 59.3418, longitude: 18.0812 },
  { displayString: 'Storgatan 10, 114 44 Stockholm, Sweden', city: 'Stockholm', latitude: 59.3365, longitude: 18.0845 },
  { displayString: 'Hornsgatan 54, 118 21 Stockholm, Sweden', city: 'Stockholm', latitude: 59.3178, longitude: 18.0556 },
  { displayString: 'Götgatan 78, 118 30 Stockholm, Sweden', city: 'Stockholm', latitude: 59.3124, longitude: 18.0748 },
  { displayString: 'Ringvägen 96, 118 61 Stockholm, Sweden', city: 'Stockholm', latitude: 59.3098, longitude: 18.0689 },
  { displayString: 'Folkingagatan 44, 118 26 Stockholm, Sweden', city: 'Stockholm', latitude: 59.3156, longitude: 18.0782 },
  { displayString: 'Södermannagatan 29, 116 23 Stockholm, Sweden', city: 'Stockholm', latitude: 59.3142, longitude: 18.0821 },
  { displayString: 'Vasagatan 12, 111 20 Stockholm, Sweden', city: 'Stockholm', latitude: 59.3312, longitude: 18.0584 },
  { displayString: 'Klarabergsgatan 37, 111 21 Stockholm, Sweden', city: 'Stockholm', latitude: 59.3319, longitude: 18.0601 },
  { displayString: 'Norrlandsgatan 14, 111 43 Stockholm, Sweden', city: 'Stockholm', latitude: 59.3341, longitude: 18.0708 },
  { displayString: 'Regeringsgatan 65, 111 56 Stockholm, Sweden', city: 'Stockholm', latitude: 59.3368, longitude: 18.0685 },
  { displayString: 'Odengatan 65, 113 22 Stockholm, Sweden', city: 'Stockholm', latitude: 59.3456, longitude: 18.0524 },
  { displayString: 'Upplandsgatan 38, 113 28 Stockholm, Sweden', city: 'Stockholm', latitude: 59.3448, longitude: 18.0489 },
  { displayString: 'Roslagsgatan 22, 113 55 Stockholm, Sweden', city: 'Stockholm', latitude: 59.3482, longitude: 18.0615 },
  { displayString: 'Valhallavägen 117, 115 31 Stockholm, Sweden', city: 'Stockholm', latitude: 59.3471, longitude: 18.0902 },
  { displayString: 'Lidingövägen 1, 114 86 Stockholm, Sweden', city: 'Stockholm', latitude: 59.3495, longitude: 18.1008 },
  { displayString: 'Strandvägen 7, 114 56 Stockholm, Sweden', city: 'Stockholm', latitude: 59.3328, longitude: 18.0842 },
  { displayString: 'Nybrogatan 11, 114 39 Stockholm, Sweden', city: 'Stockholm', latitude: 59.3356, longitude: 18.0779 },
  { displayString: 'Humlegårdsgatan 14, 114 46 Stockholm, Sweden', city: 'Stockholm', latitude: 59.3382, longitude: 18.0765 },
  { displayString: 'Hantverkargatan 25, 112 21 Stockholm, Sweden', city: 'Stockholm', latitude: 59.3289, longitude: 18.0412 },
  { displayString: 'Fleminggatan 41, 112 26 Stockholm, Sweden', city: 'Stockholm', latitude: 59.3321, longitude: 18.0368 },
  { displayString: 'Kungsholmsgatan 10, 112 27 Stockholm, Sweden', city: 'Stockholm', latitude: 59.3305, longitude: 18.0395 },
  { displayString: 'Sankt Eriksgatan 48, 112 34 Stockholm, Sweden', city: 'Stockholm', latitude: 59.3362, longitude: 18.0331 },
  { displayString: 'Fridhemsgatan 17, 112 40 Stockholm, Sweden', city: 'Stockholm', latitude: 59.3344, longitude: 18.0298 },
  { displayString: 'Scheelegatan 7, 112 28 Stockholm, Sweden', city: 'Stockholm', latitude: 59.3298, longitude: 18.0445 },
  { displayString: 'Tegnérgatan 8, 113 58 Stockholm, Sweden', city: 'Stockholm', latitude: 59.3405, longitude: 18.0589 },
  { displayString: 'Drottningholmsvägen 22, 112 42 Stockholm, Sweden', city: 'Stockholm', latitude: 59.3284, longitude: 18.0246 },
  { displayString: 'Rålambsvägen 17, 112 59 Stockholm, Sweden', city: 'Stockholm', latitude: 59.3271, longitude: 18.0189 },
  { displayString: 'Sibyllegatan 28, 114 42 Stockholm, Sweden', city: 'Stockholm', latitude: 59.3374, longitude: 18.0805 },
  { displayString: 'Kommendörsgatan 16, 114 48 Stockholm, Sweden', city: 'Stockholm', latitude: 59.3396, longitude: 18.0828 },
  { displayString: 'Artillerigatan 33, 114 51 Stockholm, Sweden', city: 'Stockholm', latitude: 59.3401, longitude: 18.0856 },
  { displayString: 'Greve Turegatan 9, 114 46 Stockholm, Sweden', city: 'Stockholm', latitude: 59.3369, longitude: 18.0752 },
  { displayString: 'Skeppsbron 20, 111 30 Stockholm, Sweden', city: 'Stockholm', latitude: 59.3245, longitude: 18.0741 },
  { displayString: 'Mäster Samuelsgatan 36, 111 57 Stockholm, Sweden', city: 'Stockholm', latitude: 59.3336, longitude: 18.0662 },
  { displayString: 'Hamngatan 18, 111 47 Stockholm, Sweden', city: 'Stockholm', latitude: 59.3329, longitude: 18.0715 },
];

function locationPayload(address, jitterSeed) {
  // Tiny jitter so users aren't stacked on the exact same pin.
  const jitter = ((jitterSeed * 9301 + 49297) % 233280) / 233280;
  const latJitter = (jitter - 0.5) * 0.004;
  const lonJitter = (((jitterSeed * 49297 + 9301) % 233280) / 233280 - 0.5) * 0.004;

  return {
    displayString: address.displayString,
    city: address.city,
    state: 'Stockholm County',
    country: 'Sweden',
    latitude: address.latitude + latJitter,
    longitude: address.longitude + lonJitter,
  };
}

async function setStockholmAddresses() {
  console.log(
    DRY_RUN
      ? '🔍 Dry run — no writes will be made.\n'
      : '✍️  Writing Stockholm addresses to all users...\n'
  );

  const usersSnapshot = await db.collection('users').get();
  console.log(`Found ${usersSnapshot.size} user document(s)\n`);

  if (usersSnapshot.empty) {
    console.log('Nothing to update.');
    return;
  }

  let updated = 0;
  let skipped = 0;
  const batchSize = 400;
  let batch = db.batch();
  let opsInBatch = 0;

  const commitBatch = async () => {
    if (opsInBatch === 0 || DRY_RUN) return;
    await batch.commit();
    batch = db.batch();
    opsInBatch = 0;
  };

  let index = 0;
  for (const userDoc of usersSnapshot.docs) {
    const data = userDoc.data() || {};
    const name = data.name || data.email || userDoc.id;
    const previous = data.location?.displayString || '(none)';
    const address = STOCKHOLM_ADDRESSES[index % STOCKHOLM_ADDRESSES.length];
    const location = locationPayload(address, index);

    if (
      previous === location.displayString &&
      data.location?.city === 'Stockholm' &&
      typeof data.location?.latitude === 'number'
    ) {
      skipped += 1;
      console.log(`  ⏭️  ${name}: already Stockholm (${previous})`);
      index += 1;
      continue;
    }

    console.log(`  ${DRY_RUN ? '👀' : '✅'} ${name}`);
    console.log(`      ${previous}`);
    console.log(`   →  ${location.displayString}`);

    if (!DRY_RUN) {
      batch.update(userDoc.ref, { location });
      opsInBatch += 1;
      if (opsInBatch >= batchSize) {
        await commitBatch();
      }
    }

    updated += 1;
    index += 1;
  }

  await commitBatch();

  console.log(
    `\n${DRY_RUN ? '🔍 Dry run complete.' : '✅ Done.'} ` +
      `${updated} to update, ${skipped} skipped (already Stockholm).`
  );
  if (DRY_RUN) {
    console.log('Re-run without --dry-run to apply changes.');
  }
}

setStockholmAddresses()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error('❌ Failed to set Stockholm addresses:', error);
    process.exit(1);
  });
