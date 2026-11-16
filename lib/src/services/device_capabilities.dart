import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

abstract final class DeviceCapabilities {
  static const _channel = MethodChannel('netpobre/device');
  static final ValueNotifier<bool> pictureInPicture = ValueNotifier(false);
  static bool _handlerReady = false;

  static void _ensureHandler() {
    if (_handlerReady) return;
    _channel.setMethodCallHandler((call) async {
      if (call.method == 'pictureInPictureChanged') {
        pictureInPicture.value = call.arguments == true;
      }
    });
    _handlerReady = true;
  }

  static Future<bool> isTelevision() async {
    try {
      return await _channel.invokeMethod<bool>('isTelevision') ?? false;
    } on MissingPluginException {
      return false;
    } on PlatformException {
      return false;
    }
  }

  static Future<void> setKeepScreenOn(bool enabled) async {
    try {
      await _channel.invokeMethod<void>('setKeepScreenOn', {
        'enabled': enabled,
      });
    } on MissingPluginException {
      // Unsupported platforms keep their default screen timeout behavior.
    } on PlatformException {
      // Playback must continue even if the platform cannot change this flag.
    }
  }

  static Future<bool> setPictureInPictureEnabled(
    bool enabled, {
    double aspectRatio = 16 / 9,
  }) async {
    _ensureHandler();
    final height = 1000;
    final width = (height * aspectRatio).round().clamp(418, 2390);
    try {
      return await _channel.invokeMethod<bool>('setPictureInPictureEnabled', {
            'enabled': enabled,
            'width': width,
            'height': height,
          }) ??
          false;
    } on MissingPluginException {
      return false;
    } on PlatformException {
      return false;
    }
  }
}
