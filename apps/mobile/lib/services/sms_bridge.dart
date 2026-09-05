import 'package:flutter/services.dart';

import '../models/financial_event.dart';

class SmsBridge {
  static const _channel = MethodChannel('com.paisa.mobile/financial_sms');

  Future<bool> requestPermission() async =>
      await _channel.invokeMethod<bool>('requestPermissions') ?? false;

  Future<bool> hasPermission() async =>
      await _channel.invokeMethod<bool>('hasPermissions') ?? false;

  Future<List<FinancialEvent>> drainEvents() async {
    final values =
        await _channel.invokeListMethod<Map<dynamic, dynamic>>('drainEvents') ??
        const [];
    return values
        .map(
          (value) => FinancialEvent.fromJson(
            value.map((key, item) => MapEntry(key.toString(), item)),
          ),
        )
        .toList();
  }
}
