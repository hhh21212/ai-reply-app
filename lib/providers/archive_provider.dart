import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/database.dart';
import '../data/dao.dart';
import '../services/summary_service.dart';
import 'chat_provider.dart';
import 'settings_provider.dart';

final summaryServiceProvider = Provider<SummaryService>(
  (ref) => SummaryService(ref.watch(apiClientProvider)),
);

final archiveSearchProvider = StateProvider<String>((ref) => '');

final archiveEntriesProvider = StreamProvider<List<ArchiveEntry>>((ref) {
  final q = ref.watch(archiveSearchProvider);
  return ref.watch(databaseProvider).watchArchive(q);
});
