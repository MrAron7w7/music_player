import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/constants/app_constants.dart';
import '../../../providers/library_providers.dart';

enum GlassQuality { automatic, high, medium, low, off }

extension GlassQualityRank on GlassQuality {
  int get rank => switch (this) {
    GlassQuality.automatic => 2,
    GlassQuality.high => 3,
    GlassQuality.medium => 2,
    GlassQuality.low => 1,
    GlassQuality.off => 0,
  };
}

final glassQualityProvider = StateProvider<GlassQuality>((ref) {
  final value = ref
      .watch(localRepositoryProvider)
      .settings
      .get(
        AppConstants.glassQualityKey,
        defaultValue: GlassQuality.automatic.name,
      );
  return GlassQuality.values.firstWhere(
    (quality) => quality.name == value,
    orElse: () => GlassQuality.automatic,
  );
});

final adaptiveGlassQualityProvider = StateProvider<GlassQuality>(
  (ref) => GlassQuality.medium,
);

extension GlassQualityLabel on GlassQuality {
  String get label => switch (this) {
    GlassQuality.automatic => 'Automático',
    GlassQuality.high => 'Alto',
    GlassQuality.medium => 'Medio',
    GlassQuality.low => 'Bajo',
    GlassQuality.off => 'Desactivado',
  };

  String get description => switch (this) {
    GlassQuality.automatic => 'Ajusta el efecto según el rendimiento observado',
    GlassQuality.high => 'Desenfoque más visible',
    GlassQuality.medium => 'Desenfoque ligero y equilibrado',
    GlassQuality.low => 'Sin desenfoque; conserva el tinte y el borde',
    GlassQuality.off => 'Superficies opacas, sin transparencia ni desenfoque',
  };
}
