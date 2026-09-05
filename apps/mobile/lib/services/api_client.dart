import 'dart:convert';

import 'package:http/http.dart' as http;

import '../models/financial_event.dart';

class ApiClient {
  ApiClient({String? baseUrl, http.Client? client})
    : baseUrl =
          baseUrl ??
          const String.fromEnvironment(
            'API_URL',
            defaultValue: 'http://10.0.2.2:4000',
          ),
      _client = client ?? http.Client();

  final String baseUrl;
  final http.Client _client;

  Future<void> uploadEvent(
    FinancialEvent event, {
    String bookId = 'book_arjun',
    String? firebaseToken,
    String? appCheckToken,
  }) async {
    final response = await _client.post(
      Uri.parse('$baseUrl/v1/books/$bookId/ingestion-events'),
      headers: {
        'content-type': 'application/json',
        'idempotency-key': 'android:${event.sourceHash}',
        if (firebaseToken != null)
          'authorization': 'Bearer $firebaseToken'
        else
          'x-dev-user-id': 'user_owner',
        'x-firebase-appcheck': ?appCheckToken,
      },
      body: jsonEncode(event.toJson()),
    );
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw StateError('API rejected event (${response.statusCode})');
    }
  }
}
