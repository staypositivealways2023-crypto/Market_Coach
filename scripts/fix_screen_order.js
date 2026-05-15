const admin = require('firebase-admin');
const fs = require('fs');
const path = require('path');

// Initialize Firebase Admin
const serviceAccountPath = path.join(__dirname, '..', 'serviceAccountKey.json');

if (!fs.existsSync(serviceAccountPath)) {
  console.error('❌ Error: serviceAccountKey.json not found!');
  console.log('\nPlease download your service account key from Firebase Console');
  process.exit(1);
}

const serviceAccount = require(serviceAccountPath);

admin.initializeApp({
  credential: admin.credential.cert(serviceAccount)
});

const db = admin.firestore();

async function fixScreenOrder() {
  try {
    console.log('🔧 Fixing screen order fields in Firestore...\n');

    // Get all lessons
    const lessonsSnapshot = await db.collection('lessons').get();

    for (const lessonDoc of lessonsSnapshot.docs) {
      const lessonId = lessonDoc.id;
      console.log(`Processing lesson: ${lessonId}`);

      // Get all screens for this lesson
      const screensSnapshot = await db
        .collection('lessons')
        .doc(lessonId)
        .collection('screens')
        .get();

      if (screensSnapshot.empty) {
        console.log(`  ⚠️  No screens found`);
        continue;
      }

      const batch = db.batch();
      let updateCount = 0;

      for (const screenDoc of screensSnapshot.docs) {
        const screenId = screenDoc.id;
        const screenData = screenDoc.data();

        // Extract order number from screen ID (e.g., "screen_001" -> 1)
        const orderMatch = screenId.match(/(\d+)$/);
        if (orderMatch) {
          const order = parseInt(orderMatch[1], 10);

          // Only update if order field is missing
          if (screenData.order === undefined) {
            batch.update(screenDoc.ref, { order });
            console.log(`  ✓ ${screenId}: adding order = ${order}`);
            updateCount++;
          } else {
            console.log(`  - ${screenId}: order already exists (${screenData.order})`);
          }
        } else {
          console.log(`  ⚠️  ${screenId}: couldn't extract order from ID`);
        }
      }

      if (updateCount > 0) {
        await batch.commit();
        console.log(`  ✅ Updated ${updateCount} screens\n`);
      } else {
        console.log(`  ✓ All screens already have order field\n`);
      }
    }

    console.log('🎉 Screen order fields fixed successfully!');
    process.exit(0);

  } catch (error) {
    console.error('❌ Fix failed:', error);
    process.exit(1);
  }
}

fixScreenOrder();
