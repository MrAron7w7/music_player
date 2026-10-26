import 'package:flutter_test/flutter_test.dart';
import 'package:music_app/data/models/song_model.dart';

void main() {
  test('SongModel.fromJson normaliza artistas y duración', () {
    final song = SongModel.fromJson({
      'videoId': 'abc123',
      'title': 'Canción de prueba',
      'artists': [
        {'name': 'Artista A'},
        {'name': 'Artista B'},
      ],
      'durationSeconds': 215,
    });

    expect(song.id, 'abc123');
    expect(song.title, 'Canción de prueba');
    expect(song.artists, ['Artista A', 'Artista B']);
    expect(song.duration, const Duration(seconds: 215));
  });

  test('SongModel serializa y recupera los mismos datos', () {
    const original = SongModel(
      id: 'abc123',
      title: 'Canción de prueba',
      artists: ['Artista A'],
      duration: Duration(seconds: 215),
    );

    final restored = SongModel.fromJson(original.toJson());

    expect(restored.id, original.id);
    expect(restored.title, original.title);
    expect(restored.artists, original.artists);
    expect(restored.duration, original.duration);
  });
}
