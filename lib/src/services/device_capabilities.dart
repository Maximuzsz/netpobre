import 'package:flutter/services.dart';

abstract final class DeviceCapabilities {
  static const _channel = MethodChannel('netpobre/device');

  static Future<bool> isTelevision() async {
    try {
      return await _channel.invokeMethod<bool>('isTelevision') ?? false;
    } on MissingPluginException {
      return false;
    } on PlatformException {
      return false;
    }
  }
}
