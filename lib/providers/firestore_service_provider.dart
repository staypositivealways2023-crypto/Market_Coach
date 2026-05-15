import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../data/firestore_service.dart';
import 'firebase_provider.dart';

final firestoreServiceProvider = Provider<FirestoreService>((ref) {
  final db = ref.watch(firebaseProvider);
  return FirestoreService(db);
});
