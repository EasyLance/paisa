import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import '../models/financial_event.dart';

class OfflineQueue {
  OfflineQueue([FlutterSecureStorage? storage])
    : _storage = storage ?? const FlutterSecureStorage();

  static const _key = 'pending_financial_events_v1';
  final FlutterSecureStorage _storage;

  Future<List<FinancialEvent>> read() async {
    final raw = await _storage.read(key: _key);
    if (raw == null) return [];
    return (jsonDecode(raw) as List)
        .map(
          (item) =>
              FinancialEvent.fromJson(Map<String, dynamic>.from(item as Map)),
        )
        .toList();
  }

  Future<void> addAll(Iterable<FinancialEvent> events) async {
    final current = await read();
    final byHash = {
      for (final event in [...current, ...events]) event.sourceHash: event,
    };
    await _storage.write(
      key: _key,
      value: jsonEncode(byHash.values.map((event) => event.toJson()).toList()),
    );
  }

  Future<void> remove(String hash) async {
    final events = await read();
    await _storage.write(
      key: _key,
      value: jsonEncode(
        events
            .where((event) => event.sourceHash != hash)
            .map((event) => event.toJson())
            .toList(),
      ),
    );
  }
}
