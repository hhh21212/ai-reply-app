import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/database.dart';
import '../data/dao.dart';

final databaseProvider = Provider<AppDatabase>(
  (ref) => throw UnimplementedError('在 main 中 override'),
);

final conversationsProvider = StreamProvider<List<Conversation>>((ref) {
  return ref.watch(databaseProvider).watchConversations();
});

final messagesProvider = StreamProvider.family<List<Message>, int>((ref, id) {
  return ref.watch(databaseProvider).watchMessages(id);
});
