import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/repositories/display_settings_repository.dart';
import '../../domain/entities/display_settings.dart';

final displaySettingsRepositoryProvider = Provider<DisplaySettingsRepository>(
  (ref) => DisplaySettingsRepository(),
);

final displaySettingsProvider =
    AsyncNotifierProvider<DisplaySettingsNotifier, DisplaySettings>(
  DisplaySettingsNotifier.new,
);

class DisplaySettingsNotifier extends AsyncNotifier<DisplaySettings> {
  @override
  Future<DisplaySettings> build() async {
    final repo = ref.watch(displaySettingsRepositoryProvider);
    return repo.load();
  }

  Future<void> saveSettings(DisplaySettings settings) async {
    final repo = ref.read(displaySettingsRepositoryProvider);
    await repo.save(settings);
    state = AsyncData(settings);
  }
}
