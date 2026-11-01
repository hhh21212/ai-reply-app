import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/database.dart';
import '../data/dao.dart';

final databaseProvider = Provider<AppDatabase>(
  (ref) => throw UnimplementedError('在 main 中 override'),
);

/// 底部导航当前 Tab 索引（chat=0 / archive=1 / settings=2），供档案页「调用到对话」跨页切换。
final homeTabProvider = StateProvider<int>((ref) => 0);

final conversationsProvider = StreamProvider<List<Conversation>>((ref) {
  return ref.watch(databaseProvider).watchConversations();
});

final messagesProvider = StreamProvider.family<List<Message>, int>((ref, id) {
  return ref.watch(databaseProvider).watchMessages(id);
});
