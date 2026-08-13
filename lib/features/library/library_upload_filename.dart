String normalizeLibraryUploadFilename(String filename) {
  final basename = filename.replaceAll('\\', '/').split('/').last.trim();
  final dot = basename.lastIndexOf('.');
  final extension = dot > 0 ? basename.substring(dot + 1).toLowerCase() : '';
  final originalStem = dot > 0 ? basename.substring(0, dot) : basename;
  var stem = originalStem
      .replaceAll(RegExp(r'[^A-Za-z0-9._-]+'), '_')
      .replaceAll(RegExp(r'_+'), '_')
      .replaceAll(RegExp(r'^\.+'), '');
  if (stem.replaceAll(RegExp(r'[._-]'), '').isEmpty) {
    stem = 'starforge_file';
  }
  if (!RegExp(r'^[A-Za-z0-9_]').hasMatch(stem)) stem = '_$stem';
  final suffix = extension.isEmpty ? '' : '.$extension';
  final maxStemLength = 255 - suffix.length;
  if (stem.length > maxStemLength) stem = stem.substring(0, maxStemLength);
  return '$stem$suffix';
}

/// Formats the staff app can render internally after upload. Keeping this list
/// beside the MIME mapper prevents offering a view-only file that the app would
/// then be unable to display.
const libraryUploadExtensions = <String>[
  'pdf',
  'mp3',
  'm4a',
  'mp4',
  'jpg',
  'jpeg',
  'png',
  'webp',
];

String? libraryUploadContentType(String filename) {
  final extension = filename.contains('.')
      ? filename.split('.').last.toLowerCase()
      : '';
  return switch (extension) {
    'jpg' || 'jpeg' => 'image/jpeg',
    'png' => 'image/png',
    'webp' => 'image/webp',
    'mp4' => 'video/mp4',
    'mp3' => 'audio/mpeg',
    'm4a' => 'audio/mp4',
    'pdf' => 'application/pdf',
    _ => null,
  };
}
