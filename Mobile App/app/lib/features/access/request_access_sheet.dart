import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/api/api_client.dart';
import '../../core/session.dart';
import '../../core/widgets.dart';

enum _Outcome { received, pending, granted }

// What the server already knows decides the wording, as on the web. The three
// cases are distinct on purpose: telling someone to wait when they have been
// let in sends them back here a third time.
const _outcomes = {
  _Outcome.received: ('Request sent', 'Thank you. The administrator can see your request. You will get an email with a link to set a password once they let you in.'),
  _Outcome.pending: ('Already on the list', 'You have asked for access before and it is still waiting for the administrator. Nothing more to do. Please wait your turn.'),
  _Outcome.granted: ('You already have access', 'This address has been approved. Check your email for the link to set a password, then sign in. There is no need to ask again.'),
};

Future<void> showRequestAccess(BuildContext context, {String? email}) => showModalBottomSheet<void>(
  context: context,
  isScrollControlled: true,
  showDragHandle: true,
  builder: (_) => RequestAccessSheet(email: email),
);

class RequestAccessSheet extends ConsumerStatefulWidget {
  const RequestAccessSheet({super.key, this.email});
  final String? email;

  @override
  ConsumerState<RequestAccessSheet> createState() => _RequestAccessSheetState();
}

class _RequestAccessSheetState extends ConsumerState<RequestAccessSheet> {
  final _form = GlobalKey<FormState>();
  final _name = TextEditingController();
  late final _email = TextEditingController(text: widget.email);
  bool _busy = false;
  String? _error;
  _Outcome? _outcome;

  @override
  void dispose() {
    _name.dispose();
    _email.dispose();
    super.dispose();
  }

  Future<void> _send() async {
    if (!_form.currentState!.validate()) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final reply = await ref.read(apiClientProvider).post('/v1/access-requests', body: {
        'name': _name.text.trim(),
        'email': _email.text.trim().toLowerCase(),
      });
      final status = reply is Map ? reply['status'] : null;
      if (mounted) setState(() => _outcome = _Outcome.values.firstWhere((o) => o.name == status, orElse: () => _Outcome.received));
    } on ApiError catch (error) {
      if (mounted) {
        setState(() => _error = error.isRateLimited
            ? 'Too many requests from here. Try again in a few minutes.'
            : error.isNetwork
                ? 'Cannot reach Paisa. Check your connection and try again.'
                : error.message);
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final outcome = _outcome;
    return Padding(
      padding: EdgeInsets.fromLTRB(20, 0, 20, 20 + MediaQuery.viewInsetsOf(context).bottom),
      child: SingleChildScrollView(
        child: outcome != null
            ? Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
                Text(_outcomes[outcome]!.$1, style: text.headlineSmall),
                const SizedBox(height: 8),
                Text(_outcomes[outcome]!.$2),
                const SizedBox(height: 20),
                SizedBox(width: double.infinity, child: FilledButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Close'))),
              ])
            : Form(
                key: _form,
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
                  Text('Request access', style: text.headlineSmall),
                  const SizedBox(height: 8),
                  const Text('Paisa is invite-only. Leave your name and email and the administrator will set up an account for you.'),
                  const SizedBox(height: 16),
                  TextFormField(
                    controller: _name,
                    decoration: const InputDecoration(labelText: 'Name'),
                    textCapitalization: TextCapitalization.words,
                    autofillHints: const [AutofillHints.name],
                    maxLength: 120,
                    validator: (value) => (value ?? '').trim().isEmpty ? 'Enter your name' : null,
                  ),
                  const SizedBox(height: 4),
                  TextFormField(
                    controller: _email,
                    decoration: const InputDecoration(labelText: 'Email'),
                    keyboardType: TextInputType.emailAddress,
                    autofillHints: const [AutofillHints.email],
                    maxLength: 320,
                    validator: (value) => RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$').hasMatch((value ?? '').trim()) ? null : 'Enter a valid email address',
                  ),
                  if (_error != null) ...[const SizedBox(height: 8), Notice(_error!)],
                  const SizedBox(height: 12),
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton(onPressed: _busy ? null : _send, child: Text(_busy ? 'Sending…' : 'Send request')),
                  ),
                  const SizedBox(height: 8),
                  Text('Only your name and email are stored, and only so somebody can reply to you.', style: text.bodySmall),
                ]),
              ),
      ),
    );
  }
}
