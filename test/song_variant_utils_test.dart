import 'package:flutter_test/flutter_test.dart';
import 'package:music_app/core/utils/song_variant_utils.dart';
import 'package:music_app/data/models/song_model.dart';

void main() {
  group('songTitleKey', () {
    test('une la canción con sus créditos y versiones habituales', () {
      expect(songTitleKey('Payphone'), 'payphone');
      expect(songTitleKey('Payphone (feat. Wiz Khalifa)'), 'payphone');
      expect(songTitleKey('Payphone feat. Wiz Khalifa'), 'payphone');
      expect(songTitleKey('Payphone - Guitar Cover'), 'payphone');
      expect(songTitleKey('Payphone (Acoustic)'), 'payphone');
      expect(songTitleKey('Payphone - Remix'), 'payphone');
      expect(songTitleKey('Payphone - Live'), 'payphone');
      expect(songTitleKey('Payphone - Sped Up'), 'payphone');
      expect(songTitleKey('Payphone Sped Up'), 'payphone');
      expect(songTitleKey('Payphone Speed Up'), 'payphone');
      expect(songTitleKey('Payphone Lo-Fi'), 'payphone');
      expect(songTitleKey('Payphone 8 Bit'), 'payphone');
      expect(songTitleKey('Payphone - 8D Audio'), 'payphone');
      expect(songTitleKey('Payphone - Official Video'), 'payphone');
      expect(
        songTitleKey('Bohemian Rhapsody - Remastered 2011'),
        'bohemian rhapsody',
      );
    });

    test('respeta títulos que contienen palabras parecidas', () {
      expect(songTitleKey('Live and Let Die'), 'live and let die');
      expect(songTitleKey('Clean'), 'clean');
      expect(songTitleKey('Original Sin'), 'original sin');
      expect(songTitleKey('Song - Part 2'), 'song part 2');
    });

    test('reconoce variantes con el artista dentro del título', () {
      const seed = SongModel(
        id: 'seed',
        title: 'Payphone',
        artists: ['Maroon 5'],
      );
      const cover = SongModel(
        id: 'cover',
        title: 'Payphone - Boyce Avenue',
        artists: ['Boyce Avenue'],
      );
      const coverWithOriginalArtist = SongModel(
        id: 'cover-2',
        title: 'Payphone - Maroon 5 (Boyce Avenue cover)',
        artists: ['Boyce Avenue'],
      );
      const different = SongModel(
        id: 'other',
        title: 'Sugar',
        artists: ['Maroon 5'],
      );

      expect(isSameSongVariant(cover, seed), isTrue);
      expect(isSameSongVariant(coverWithOriginalArtist, seed), isTrue);
      expect(isSameSongVariant(different, seed), isFalse);
      expect(isSameSongVariant(seed, seed), isFalse);
    });
  });

  group('filterSongVariants', () {
    test('elimina covers, versiones y canciones ya presentes', () {
      const seed = SongModel(
        id: 'seed',
        title: 'Payphone',
        artists: ['Maroon 5'],
      );
      const songs = [
        SongModel(id: 'cover-1', title: 'Payphone (Guitar Cover)'),
        SongModel(id: 'cover-2', title: 'Payphone - Acoustic'),
        SongModel(id: 'same', title: 'Payphone'),
        SongModel(id: 'other-1', title: 'Sugar', artists: ['Maroon 5']),
        SongModel(id: 'other-2', title: 'Animals', artists: ['Maroon 5']),
        SongModel(id: 'other-1', title: 'Sugar (dup id)'),
      ];

      final result = filterSongVariants(
        songs,
        excludeTitleKeys: const {'animals'},
        reference: seed,
      );

      expect(result.map((song) => song.id), ['other-1']);
    });

    test('respeta el límite y no repite títulos entre artistas', () {
      const songs = [
        SongModel(id: 'a', title: 'Song', artists: ['Artist A']),
        SongModel(id: 'b', title: 'Song - Live', artists: ['Artist B']),
        SongModel(id: 'c', title: 'Other', artists: ['Artist C']),
        SongModel(id: 'd', title: 'Another', artists: ['Artist D']),
      ];

      final result = filterSongVariants(songs, limit: 2);

      expect(result.map((song) => song.id), ['a', 'c']);
    });
  });
}
