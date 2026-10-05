import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/session.dart';
import '../../core/widgets.dart';
import 'lock_controller.dart';

/// Sits above the whole navigator, so a dialog or a pushed screen is covered
/// too. The screens underneath stay alive (nobody loses their place) but are
/// hidden from the eye and from screen readers while locked.
class LockGate extends ConsumerStatefulWidget {
  const LockGate({super.key, required this.child});
  final Widget child;

  @override
  ConsumerState<LockGate> createState() => _LockGateState();
}

class _LockGateState extends ConsumerState<LockGate> with WidgetsBindingObserver {
  DateTime? _leftAt;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused) {
      _leftAt = DateTime.now();
    } else if (state == AppLifecycleState.resumed && _leftAt != null) {
      ref.read(lockProvider.notifier).resumedAfter(DateTime.now().difference(_leftAt!));
      _leftAt = null;
    }
  }

  @override
  Widget build(BuildContext context) {
    // Signing in just proved who this is, so do not ask again straight away.
    ref.listen<AsyncValue<bool>>(signedInProvider, (previous, next) {
      if (previous?.value == false && next.value == true) ref.read(lockProvider.notifier).clear();
    });
    final locked = ref.watch(lockProvider.select((state) => state.locked));
    final signedIn = ref.watch(signedInProvider).value ?? false;
    final covered = locked && signedIn;
    return Stack(
      children: [
        ExcludeSemantics(excluding: covered, child: widget.child),
        if (covered) const Positioned.fill(child: LockScreen()),
      ],
    );
  }
}

class LockScreen extends ConsumerStatefulWidget {
  const LockScreen({super.key});

  @override
  ConsumerState<LockScreen> createState() => _LockScreenState();
}

class _LockScreenState extends ConsumerState<LockScreen> {
  @override
  void initState() {
    super.initState();
    // Ask straight away; the button is for when the prompt was dismissed.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) ref.read(lockProvider.notifier).unlock();
    });
  }

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(32),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const PaisaMark(size: 56),
                const SizedBox(height: 20),
                Text('Paisa is locked', style: text.headlineMedium),
                const SizedBox(height: 8),
                Text('Use your fingerprint, face or screen lock to open it.', style: text.bodySmall, textAlign: TextAlign.center),
                const SizedBox(height: 24),
                FilledButton.icon(
                  onPressed: () => ref.read(lockProvider.notifier).unlock(),
                  icon: const Icon(Icons.lock_open),
                  label: const Text('Unlock'),
                ),
                const SizedBox(height: 8),
                // Someone whose sensor has failed must not be stuck for good.
                TextButton(
                  onPressed: () => ref.read(sessionProvider.notifier).signOut(),
                  child: const Text('Sign out instead'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
