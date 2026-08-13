import 'package:flutter/services.dart';

abstract final class ContentProtection {
  static const _channel = MethodChannel('com.starforge.staff/privacy');

  static Future<void> setProtected(
    bool enabled, {
    required String languageCode,
  }) async {
    try {
      await _channel.invokeMethod<void>('setProtected', {
        'enabled': enabled,
        'language': languageCode,
      });
    } on MissingPluginException {
      // The UI remains protected by product policy on unsupported test hosts.
    }
  }
}
