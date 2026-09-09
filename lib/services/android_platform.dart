import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// Android uses app-private storage and the system document picker. No shared
/// storage permission, desktop HOME directory, or filesystem URI is required.
class AndroidPlatform {
  static bool get isAndroid =>
      !kIsWeb && defaultTargetPlatform == TargetPlatform.android;

  static const channel = MethodChannel('book_and_quill/android');

  static Future<Directory> dataDirectory() async {
    final path = await channel.invokeMethod<String>('getDataDirectory');
    if (path == null || path.isEmpty) {
      throw const FileSystemException('Android app storage is unavailable.');
    }
    return Directory(path);
  }

  static Future<bool> exportDocument(String name, String contents) async =>
      await channel.invokeMethod<bool>('exportBook', <String, String>{
        'filename': name,
        'contents': contents,
      }) ?? false;

  static Future<String?> importDocument() =>
      channel.invokeMethod<String>('importBook');
}
