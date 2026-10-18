// The Budgets routes of the scripted API, kept out of fakes.dart so that file
// only gains one hook. State lives in an Expando keyed on the FakeServer.
import 'dart:convert';

import 'package:http/http.dart' as http;

import 'fakes.dart';

/// What the fake server holds and has been sent for budgets and recurring plans.
class BudgetState {
  /// The recorded plan list, copied so a test can change it. The real list route
  /// returns only active plans, and so does this.
  final List<Map<String, dynamic>> plans = [
    for (final item in (fixture('recurring_plans') as Map<String, dynamic>)['items'] as List) Map<String, dynamic>.from(item as Map<String, dynamic>),
  ];
  int? plansStatus;
  final planPuts = <Map<String, dynamic>>[];
  final planWrites = <({String method, String path, Map<String, dynamic> body})>[];

  /// Answers every write with this recorded response (`{status, body}`), once.
  Map<String, dynamic>? nextWriteError;

  /// A write is saved, then the connection drops before the reply arrives.
  bool dropNextPlanCreateReply = false;
}

final _states = Expando<BudgetState>('budget state');

BudgetState budgetState(FakeServer server) => _states[server] ??= BudgetState();

/// A recorded `{request, status, body}` fixture, as a response.
http.Response recorded(String name) {
  final saved = fixture(name) as Map<String, dynamic>;
  return jsonResponse(saved['status'] as int, saved['body'] as Object);
}

/// Handles `PUT budget-plan` and the recurring-plans routes; null for anything else.
http.Response? budgetRoutes(FakeServer server, http.Request request, String path) {
  final state = budgetState(server);
  final planRoute = RegExp(r'^/v1/books/[^/]+/budget-plan$').hasMatch(path);
  final recurring = RegExp(r'^/v1/books/[^/]+/recurring-plans(?:/([^/]+))?$').firstMatch(path);
  if (!(planRoute && request.method == 'PUT') && recurring == null) return null;

  if (request.method != 'GET') {
    final forced = state.nextWriteError;
    if (forced != null) {
      state.nextWriteError = null;
      return jsonResponse(forced['status'] as int, forced['body'] as Object);
    }
  }

  if (planRoute) {
    final body = jsonDecode(request.body) as Map<String, dynamic>;
    state.planPuts.add(body);
    final allocations = (body['allocations'] as List).cast<Map<String, dynamic>>();
    if (allocations.fold<int>(0, (sum, entry) => sum + (entry['percent'] as int)) > 100) return recorded('budget_plan_over_100_error');
    // As the server does: zero shares are dropped, biggest first.
    final items = [for (final entry in allocations) if ((entry['percent'] as int) > 0) {'groupName': entry['groupName'], 'percent': entry['percent']}]
      ..sort((a, b) => (b['percent'] as int).compareTo(a['percent'] as int));
    final current = server.planBody ?? fixture('budget_plan_set') as Map<String, dynamic>;
    server.planBody = {'items': items, 'baseIncomeMinor': current['baseIncomeMinor']};
    return jsonResponse(200, server.planBody!);
  }

  final id = recurring!.group(1);
  if (request.method == 'GET') {
    if (state.plansStatus != null) return jsonResponse(state.plansStatus!, {'code': 'ERROR', 'message': 'no'});
    return jsonResponse(200, {'items': [for (final plan in state.plans) if (plan['active'] == true) plan]});
  }
  final body = jsonDecode(request.body) as Map<String, dynamic>;
  state.planWrites.add((method: request.method, path: path, body: body));
  if (request.method == 'POST') {
    final created = <String, dynamic>{
      ...(fixture('recurring_created_expense') as Map<String, dynamic>)['body'] as Map<String, dynamic>,
      'id': 'plan_${state.plans.length}',
      ...body,
      'active': true,
    };
    state.plans.add(created);
    if (state.dropNextPlanCreateReply) {
      state.dropNextPlanCreateReply = false;
      throw http.ClientException('connection dropped');
    }
    return jsonResponse(201, created);
  }
  final plan = state.plans.where((item) => item['id'] == id).firstOrNull;
  if (plan == null) return recorded('recurring_patch_not_found');
  if ((body['amountMinor'] == null) != (body['kind'] == null)) return recorded('recurring_error_amount_without_kind');
  plan.addAll(body);
  return jsonResponse(200, plan);
}
