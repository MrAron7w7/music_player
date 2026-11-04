import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../providers/settings_providers.dart';

/// Avatar circular del usuario. Muestra la foto elegida en Ajustes o un
/// marcador con el icono de persona si todavía no hay ninguna.
class ProfileAvatar extends ConsumerWidget {
  const ProfileAvatar({
    super.key,
    this.size = 46,
    this.onTap,
  });

  final double size;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final path = ref.watch(profilePhotoProvider);
    final theme = Theme.of(context);
    final file = path == null ? null : File(path);
    final hasPhoto = file != null && file.existsSync();

    final placeholder = Icon(
      Icons.person_rounded,
      size: size * .52,
      color: theme.colorScheme.primary,
    );

    return Semantics(
      button: onTap != null,
      label: hasPhoto ? 'Foto de perfil' : 'Añadir foto de perfil',
      child: InkResponse(
        onTap: onTap,
        radius: size / 2 + 8,
        child: Container(
          width: size,
          height: size,
          clipBehavior: Clip.antiAlias,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: theme.colorScheme.primary.withValues(alpha: .14),
            border: Border.all(
              color: theme.colorScheme.primary.withValues(alpha: .3),
              width: 1.4,
            ),
          ),
          child: hasPhoto
              ? Image.file(
                  file,
                  width: size,
                  height: size,
                  fit: BoxFit.cover,
                  errorBuilder: (_, _, _) => placeholder,
                )
              : placeholder,
        ),
      ),
    );
  }
}
