const admin = require('firebase-admin');
const fs = require('fs');
const path = require('path');

// Initialize Firebase Admin
// You need to download service account key from Firebase Console:
// Project Settings > Service Accounts > Generate New Private Key
const serviceAccountPath = path.join(__dirname, '..', 'serviceAccountKey.json');

if (!fs.existsSync(serviceAccountPath)) {
  console.error('❌ Error: serviceAccountKey.json not found!');
  console.log('\nPlease download your service account key:');
  console.log('1. Go to Firebase Console: https://console.firebase.google.com/');
  console.log('2. Select your project: marketcoach-db8f4');
  console.log('3. Go to Project Settings > Service Accounts');
  console.log('4. Click "Generate New Private Key"');
  console.log('5. Save as serviceAccountKey.json in the project root');
  process.exit(1);
}

const serviceAccount = require(serviceAccountPath);

admin.initializeApp({
  credential: admin.credential.cert(serviceAccount)
});

const db = admin.firestore();

async function importLessons() {
  try {
    // Read the seed data
    const seedDataPath = process.argv[2] || path.join(__dirname, '..', 'rsi_lesson_seed.json');

    if (!fs.existsSync(seedDataPath)) {
      console.error(`❌ Seed file not found: ${seedDataPath}`);
      process.exit(1);
    }

    const seedData = JSON.parse(fs.readFileSync(seedDataPath, 'utf8'));

    console.log('📚 Importing lessons to Firestore...\n');

    // Import each lesson
    for (const [lessonId, lessonData] of Object.entries(seedData)) {
      console.log(`Importing lesson: ${lessonId}`);

      // Extract screens from lesson data
      const { screens, ...lessonDoc } = lessonData;

      // Convert published_at string to Firestore timestamp
      if (lessonDoc.published_at) {
        lessonDoc.published_at = admin.firestore.Timestamp.fromDate(new Date(lessonDoc.published_at));
      }

      // Create the lesson document
      const lessonRef = db.collection('lessons').doc(lessonId);
      await lessonRef.set(lessonDoc);
      console.log(`  ✓ Lesson document created`);

      // Create screens subcollection
      if (screens) {
        const batch = db.batch();
        let screenCount = 0;

        for (const [screenId, screenData] of Object.entries(screens)) {
          const screenRef = lessonRef.collection('screens').doc(screenId);
          batch.set(screenRef, screenData);
          screenCount++;
        }

        await batch.commit();
        console.log(`  ✓ ${screenCount} screens imported`);
      }

      console.log(`✅ ${lessonId} imported successfully\n`);
    }

    console.log('🎉 All lessons imported successfully!');
    process.exit(0);

  } catch (error) {
    console.error('❌ Import failed:', error);
    process.exit(1);
  }
}

importLessons();
