import 'package:flutter/material.dart';

import 'text_utils.dart';

/// Portada representativa para un género o una mezcla por estado de ánimo.
///
/// Las tarjetas de Inicio y de "Ver todos" usan una fotografía real en lugar
/// de un color plano. Si el título no coincide con ninguna categoría conocida
/// se devuelve una portada musical neutra, así nunca queda un hueco vacío.
class GenreArtwork {
  const GenreArtwork({
    required this.imageUrl,
    required this.colors,
    required this.icon,
  });

  final String imageUrl;
  final List<Color> colors;
  final IconData icon;
}

class _ArtworkEntry {
  const _ArtworkEntry({
    required this.keywords,
    required this.photoId,
    required this.colors,
    required this.icon,
  });

  final List<String> keywords;
  final String photoId;
  final List<Color> colors;
  final IconData icon;
}

const _fallbackArtwork = _ArtworkEntry(
  keywords: <String>[],
  photoId: 'photo-1511379938547-c1f69419868d',
  colors: <Color>[Color(0xFF2F3B5A), Color(0xFF6A86C9)],
  icon: Icons.music_note_rounded,
);

/// El orden importa: las coincidencias más específicas van primero para que
/// "K-Pop" no termine usando la imagen genérica de "Pop" o "Afro Pop" no use
/// la de "Pop".
const _artworkEntries = <_ArtworkEntry>[
  _ArtworkEntry(
    keywords: ['sleep', 'dormir', 'descanso', 'sueno', 'lullaby'],
    photoId: 'photo-1541781774459-bb2af2f05b55',
    colors: [Color(0xFF25324A), Color(0xFF5B6E9E)],
    icon: Icons.bedtime_rounded,
  ),
  _ArtworkEntry(
    keywords: [
      'focus',
      'enfocado',
      'concentracion',
      'study',
      'estudiar',
      'work',
      'trabajo',
    ],
    photoId: 'photo-1499750310107-5fef28a66643',
    colors: [Color(0xFF2E4A3E), Color(0xFF5F9E7F)],
    icon: Icons.center_focus_strong_rounded,
  ),
  _ArtworkEntry(
    keywords: [
      'gym',
      'workout',
      'fitness',
      'entrenamiento',
      'ejercicio',
      'running',
      'correr',
    ],
    photoId: 'photo-1534438327276-14e5300c3a48',
    colors: [Color(0xFF5A2C2C), Color(0xFFC96A4B)],
    icon: Icons.fitness_center_rounded,
  ),
  _ArtworkEntry(
    keywords: ['gaming', 'games', 'game', 'videojuego', 'videojuegos'],
    photoId: 'photo-1542751371-adc38448a05e',
    colors: [Color(0xFF2E2350), Color(0xFF7554C9)],
    icon: Icons.sports_esports_rounded,
  ),
  _ArtworkEntry(
    keywords: [
      'party',
      'fiesta',
      'dance',
      'baile',
      'electronic',
      'electronica',
      'edm',
      'club',
      'feel good',
    ],
    photoId: 'photo-1492684223066-81342ee5ff30',
    colors: [Color(0xFF6A2B50), Color(0xFFD05C9B)],
    icon: Icons.celebration_rounded,
  ),
  _ArtworkEntry(
    keywords: [
      'chill',
      'relax',
      'calma',
      'tranquil',
      'acoustic',
      'acustico',
      'lofi',
      'lo fi',
      'ambient',
    ],
    photoId: 'photo-1507525428034-b723cf961d3e',
    colors: [Color(0xFF1D5560), Color(0xFF4EA7B5)],
    icon: Icons.spa_rounded,
  ),
  _ArtworkEntry(
    keywords: ['k pop', 'kpop', 'k-pop'],
    photoId: 'photo-1514525253161-7a46d19cd819',
    colors: [Color(0xFF5D254D), Color(0xFFE06AA8)],
    icon: Icons.star_rounded,
  ),
  _ArtworkEntry(
    keywords: ['anime', 'otaku', 'j pop', 'j-pop'],
    photoId: 'photo-1518709268805-4e9042af9f23',
    colors: [Color(0xFF392B5C), Color(0xFF8D6BE0)],
    icon: Icons.auto_awesome_rounded,
  ),
  _ArtworkEntry(
    keywords: ['hip hop', 'hip-hop', 'rap', 'trap'],
    photoId: 'photo-1516280440614-37939bbacd81',
    colors: [Color(0xFF3C3029), Color(0xFFA07A55)],
    icon: Icons.mic_external_on_rounded,
  ),
  _ArtworkEntry(
    keywords: ['r b', 'rnb', 'rhythm blues', 'soul', 'funk'],
    photoId: 'photo-1516450360452-9312f5e86fc7',
    colors: [Color(0xFF4A2B4A), Color(0xFFB06AA8)],
    icon: Icons.headphones_rounded,
  ),
  _ArtworkEntry(
    keywords: ['jazz', 'blues', 'swing'],
    photoId: 'photo-1415201364774-f6f0bb35f28f',
    colors: [Color(0xFF3B2F4A), Color(0xFF8D7BA8)],
    icon: Icons.piano_rounded,
  ),
  _ArtworkEntry(
    keywords: [
      'classical',
      'clasica',
      'piano',
      'orchestra',
      'orquesta',
      'soundtrack',
    ],
    photoId: 'photo-1507838153414-b4b713384a76',
    colors: [Color(0xFF4A3B2A), Color(0xFFB89A68)],
    icon: Icons.music_note_rounded,
  ),
  _ArtworkEntry(
    keywords: [
      'latin',
      'latina',
      'reggaeton',
      'salsa',
      'bachata',
      'cumbia',
      'caribbean',
    ],
    photoId: 'photo-1511671782779-c97d3d27a1d4',
    colors: [Color(0xFF6B2E28), Color(0xFFE07A52)],
    icon: Icons.local_fire_department_rounded,
  ),
  _ArtworkEntry(
    keywords: ['african', 'africa', 'afro', 'afrobeats', 'amapiano'],
    photoId: 'photo-1501386761578-eac5c94b800a',
    colors: [Color(0xFF4A351F), Color(0xFFD39945)],
    icon: Icons.public_rounded,
  ),
  _ArtworkEntry(
    keywords: ['country', 'folk'],
    photoId: 'photo-1510915361894-db8b60106cb1',
    colors: [Color(0xFF4B3B24), Color(0xFFB38B4D)],
    icon: Icons.nature_people_rounded,
  ),
  _ArtworkEntry(
    keywords: ['metal', 'heavy', 'hardcore', 'punk'],
    photoId: 'photo-1524368535928-5b5e00ddc76b',
    colors: [Color(0xFF2A2A2E), Color(0xFF787884)],
    icon: Icons.bolt_rounded,
  ),
  _ArtworkEntry(
    keywords: ['rock'],
    photoId: 'photo-1498038432885-c6f3f1b912ee',
    colors: [Color(0xFF4A252B), Color(0xFFC25C68)],
    icon: Icons.audiotrack_rounded,
  ),
  _ArtworkEntry(
    keywords: ['indie', 'alternative', 'alternativo'],
    photoId: 'photo-1499415479124-43c32433a620',
    colors: [Color(0xFF2E3E4A), Color(0xFF6F98B3)],
    icon: Icons.album_rounded,
  ),
  _ArtworkEntry(
    keywords: ['pop'],
    photoId: 'photo-1493225457124-a3eb161ffa5f',
    colors: [Color(0xFF4B2E6B), Color(0xFFB47AE0)],
    icon: Icons.star_outline_rounded,
  ),
  _ArtworkEntry(
    keywords: ['romance', 'romantico', 'love', 'amor'],
    photoId: 'photo-1516589178581-6cd7833ae3b2',
    colors: [Color(0xFF5C2A3E), Color(0xFFD9789C)],
    icon: Icons.favorite_rounded,
  ),
  _ArtworkEntry(
    keywords: ['sad', 'triste', 'melancolia', 'melancolico', 'depres'],
    photoId: 'photo-1499209974431-9dddcece7f88',
    colors: [Color(0xFF263447), Color(0xFF6B87A8)],
    icon: Icons.water_drop_rounded,
  ),
  _ArtworkEntry(
    keywords: ['travel', 'viaje', 'road trip', 'commute'],
    photoId: 'photo-1488646953014-85cb44e25828',
    colors: [Color(0xFF244B5A), Color(0xFF5FA5B8)],
    icon: Icons.explore_rounded,
  ),
  _ArtworkEntry(
    keywords: ['kids', 'ninos', 'infantil', 'children'],
    photoId: 'photo-1492684223066-81342ee5ff30',
    colors: [Color(0xFF4F5A26), Color(0xFFC4C95E)],
    icon: Icons.toys_rounded,
  ),
  _ArtworkEntry(
    keywords: ['wellness', 'meditation', 'meditacion', 'yoga', 'spa'],
    photoId: 'photo-1506126613408-eca07ce68773',
    colors: [Color(0xFF2F4A3B), Color(0xFF79B58F)],
    icon: Icons.self_improvement_rounded,
  ),
  _ArtworkEntry(
    keywords: ['podcast'],
    photoId: 'photo-1478737270239-2f02b77fc618',
    colors: [Color(0xFF3A3A3A), Color(0xFF9A9A9A)],
    icon: Icons.podcasts_rounded,
  ),
];

GenreArtwork genreArtworkFor(String title) {
  final normalized = normalize(title);
  if (normalized.isNotEmpty) {
    for (final entry in _artworkEntries) {
      for (final keyword in entry.keywords) {
        final needle = normalize(keyword);
        if (needle.isNotEmpty && normalized.contains(needle)) {
          return GenreArtwork(
            imageUrl: _photoUrl(entry.photoId),
            colors: entry.colors,
            icon: entry.icon,
          );
        }
      }
    }
  }
  return GenreArtwork(
    imageUrl: _photoUrl(_fallbackArtwork.photoId),
    colors: _fallbackArtwork.colors,
    icon: _fallbackArtwork.icon,
  );
}

String _photoUrl(String id) =>
    'https://images.unsplash.com/$id?auto=format&fit=crop&w=800&q=75';
