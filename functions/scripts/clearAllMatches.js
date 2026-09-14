// Deletes every document in each user's matches subcollection.
// Usage: cd functions && node scripts/clearAllMatches.js

const admin = require('firebase-admin');

admin.initializeApp({
  projectId: 'spectroom-553a0',
});

const db = admin.firestore();

async function deleteCollectionDocs(docs) {
  const batchSize = 450;
  for (let i = 0; i < docs.length; i += batchSize) {
    const batch = db.batch();
    const chunk = docs.slice(i, i + batchSize);
    chunk.forEach((doc) => batch.delete(doc.ref));
    await batch.commit();
  }
}

async function clearAllMatches() {
  console.log('🗑️  Clearing all matches from spectroom-553a0...');

  const usersSnapshot = await db.collection('users').get();
  console.log(`Found ${usersSnapshot.size} user documents`);

  let totalDeleted = 0;

  for (const userDoc of usersSnapshot.docs) {
    const matchesSnapshot = await userDoc.ref.collection('matches').get();
    if (matchesSnapshot.empty) {
      continue;
    }

    await deleteCollectionDocs(matchesSnapshot.docs);
    totalDeleted += matchesSnapshot.size;
    console.log(`  ✅ ${userDoc.id}: deleted ${matchesSnapshot.size} match(es)`);
  }

  console.log(`\n✅ Done. Deleted ${totalDeleted} match document(s) total.`);
}

clearAllMatches()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error('❌ Failed to clear matches:', error);
    process.exit(1);
  });
