import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/api/api_client.dart';
import '../../core/api/models.dart';
import '../../core/theme/tokens.dart';
import '../../core/widgets.dart';
import '../activity/activity_logic.dart';
import '../activity/activity_providers.dart';
import '../dashboard/dashboard_providers.dart';
import 'import_logic.dart';
import 'import_providers.dart';
import 'office_crypto.dart';

/// Bring a bank statement (.xlsx, protected or not) into the ledger.
class ImportScreen extends ConsumerStatefulWidget {
  const ImportScreen({super.key, required this.book});
  final Book book;

  @override
  ConsumerState<ImportScreen> createState() => _ImportScreenState();
}

class _ImportScreenState extends ConsumerState<ImportScreen> {
  final _password = TextEditingController();
  PickedFile? _file;
  bool _encrypted = false;
  bool _showPassword = false;
  String? _accountId;
  bool _busy = false;
  String? _failure;
  ImportResult? _result;

  @override
  void dispose() {
    _password.dispose();
    super.dispose();
  }

  Future<void> _choose() async {
    setState(() => _failure = null);
    try {
      final picked = await ref.read(statementPickerProvider)();
      if (picked == null || !mounted) return;
      final refusal = refusalForName(picked.name);
      if (refusal != null) {
        setState(() => _failure = refusal);
        return;
      }
      if (picked.bytes.isEmpty) {
        setState(() => _failure = 'That file is empty, so there is nothing to import. Download the statement again and choose it once it has finished downloading.');
        return;
      }
      setState(() {
        _file = picked;
        _encrypted = isOfficeEncrypted(picked.bytes);
        _password.clear();
      });
    } on ImportProblem catch (problem) {
      if (mounted) setState(() => _failure = problem.message);
    }
  }

  Future<void> _import() async {
    final file = _file;
    if (file == null) return;
    if (_encrypted && _password.text.isEmpty) {
      setState(() => _failure = 'Enter the statement\'s password to open it.');
      return;
    }
    setState(() {
      _busy = true;
      _failure = null;
    });
    try {
      // Opened here, on the phone: the password is used for this and nothing else.
      final workbook = _encrypted ? await ref.read(decryptorProvider)(file.bytes, _password.text) : file.bytes;
      final prepared = prepareWorkbook(workbook);
      final result = await ref.read(ledgerApiProvider(widget.book.id)).importStatement(prepared.body(accountId: _accountId));
      if (!mounted) return;
      ref.invalidate(activityProvider);
      ref.invalidate(summaryProvider);
      setState(() {
        _result = result;
        // The statement and its password are not kept any longer than needed.
        _file = null;
        _password.clear();
      });
    } on WrongPasswordException {
      if (mounted) setState(() => _failure = 'That password did not open the file. Check it and try again.');
    } on UnsupportedEncryptionException catch (problem) {
      if (mounted) setState(() => _failure = '${problem.message}.');
    } on ImportProblem catch (problem) {
      if (mounted) setState(() => _failure = problem.message);
    } on ApiError catch (error) {
      // Too big and unreadable are the server's own words about the file, so
      // they are shown as sent; anything else gets the usual sentence.
      if (mounted) setState(() => _failure = error.status == 413 || error.status == 422 ? error.message : describeFailure(error));
    } catch (error) {
      if (mounted) setState(() => _failure = describeFailure(error));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final result = _result;
    return Scaffold(
      appBar: AppBar(title: const Text('Import statement')),
      body: ListView(padding: const EdgeInsets.fromLTRB(16, 8, 16, 32), children: [
        if (result != null) ..._resultView(context, result) else ..._formView(context),
      ]),
    );
  }

  List<Widget> _formView(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final accounts = ref.watch(accountsProvider(widget.book.id)).value ?? const <Account>[];
    final file = _file;
    return [
      const _PrivacyNote(),
      const SizedBox(height: 16),
      if (file == null) ...[
        Text('Download your statement from your bank as an Excel (.xlsx) file. If it asks for a password to open, you will be asked for it here.', style: text.bodyMedium),
        const SizedBox(height: 16),
        FilledButton.icon(onPressed: _busy ? null : _choose, icon: const Icon(Icons.upload_file), label: const Text('Choose a statement file')),
      ] else ...[
        Card(
          child: ListTile(
            leading: Icon(_encrypted ? Icons.lock_outline : Icons.description_outlined),
            title: Text(file.name, maxLines: 2, overflow: TextOverflow.ellipsis),
            subtitle: Text('${fileSize(file.bytes.length)}${_encrypted ? ' · password protected' : ''}'),
            trailing: TextButton(onPressed: _busy ? null : _choose, child: const Text('Change')),
          ),
        ),
        if (_encrypted) ...[
          const SizedBox(height: 16),
          TextField(
            controller: _password,
            obscureText: !_showPassword,
            enableSuggestions: false,
            autocorrect: false,
            enabled: !_busy,
            onSubmitted: (_) => _import(),
            decoration: InputDecoration(
              labelText: 'Statement password',
              helperText: 'Used on this phone to open the file. It is never sent or saved.',
              helperMaxLines: 2,
              suffixIcon: IconButton(
                tooltip: _showPassword ? 'Hide password' : 'Show password',
                icon: Icon(_showPassword ? Icons.visibility_off : Icons.visibility),
                onPressed: () => setState(() => _showPassword = !_showPassword),
              ),
            ),
          ),
        ],
        if (accounts.isNotEmpty) ...[
          const SizedBox(height: 16),
          DropdownButtonFormField<String?>(
            initialValue: _accountId,
            isExpanded: true,
            decoration: const InputDecoration(labelText: 'Which account is this? (optional)'),
            items: [
              const DropdownMenuItem<String?>(value: null, child: Text('Not sure / none')),
              for (final account in accounts) DropdownMenuItem<String?>(value: account.id, child: Text(account.label, overflow: TextOverflow.ellipsis)),
            ],
            onChanged: _busy ? null : (value) => setState(() => _accountId = value),
          ),
        ],
        const SizedBox(height: 20),
        FilledButton(
          onPressed: _busy ? null : _import,
          child: _busy ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2)) : const Text('Import statement'),
        ),
      ],
      if (_failure != null) Padding(padding: const EdgeInsets.only(top: 16), child: Notice(_failure!)),
    ];
  }

  List<Widget> _resultView(BuildContext context, ImportResult result) {
    final text = Theme.of(context).textTheme;
    final c = context.paisa;
    return [
      Card(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Icon(result.imported > 0 ? Icons.check_circle_outline : Icons.info_outline, color: result.imported > 0 ? c.positive : c.muted),
            const SizedBox(height: 8),
            Semantics(liveRegion: true, child: Text(importHeadline(result), style: text.titleLarge)),
            const SizedBox(height: 6),
            Text(
              result.imported > 0 ? 'Payments that could not be given a category wait in Activity under "Needs review".' : 'Importing the same statement again is safe: entries already in the ledger are skipped.',
              style: text.bodySmall,
            ),
          ]),
        ),
      ),
      const SizedBox(height: 12),
      Card(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(result.warnings.isEmpty ? 'No problems found' : 'Check these', style: text.titleLarge),
            const SizedBox(height: 8),
            if (result.warnings.isEmpty)
              Text('Every row was read and the running balance followed on each one.', style: text.bodySmall)
            else ...[
              Text('The bank\'s running balance did not follow on these rows. They were imported with the amounts the statement states, so check them against the statement.', style: text.bodySmall),
              const SizedBox(height: 8),
              for (final warning in result.warnings) Padding(padding: const EdgeInsets.symmetric(vertical: 4), child: Text(warning, style: text.bodyMedium)),
            ],
          ]),
        ),
      ),
      const SizedBox(height: 20),
      FilledButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Done')),
    ];
  }
}

/// What is kept and what is not, in the words the person needs before they pick
/// a file. It must stay true to the server: it keeps each payment's date, amount,
/// description and the balance after it, and nothing else of the statement.
class _PrivacyNote extends StatelessWidget {
  const _PrivacyNote();

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(color: scheme.primaryContainer, borderRadius: BorderRadius.circular(12)),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Icon(Icons.shield_outlined, color: scheme.onPrimaryContainer),
        const SizedBox(width: 12),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('Your bank details are not saved', style: text.titleSmall?.copyWith(color: scheme.onPrimaryContainer)),
            const SizedBox(height: 4),
            Text(
              'Your account number, name, address and the statement\'s header and footer are not saved anywhere, and neither is the file. Paisa keeps only the payments: date, amount, description and the balance after each one.',
              style: text.bodySmall?.copyWith(color: scheme.onPrimaryContainer),
            ),
          ]),
        ),
      ]),
    );
  }
}
