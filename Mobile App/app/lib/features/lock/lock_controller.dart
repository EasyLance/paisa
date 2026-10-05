import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:local_auth/local_auth.dart';

import '../../core/prefs.dart';

const _enabledKey = 'paisa.lock.enabled';
const _graceKey = 'paisa.lock.grace';

/// The one place that talks to the phone's biometric / screen-lock prompt, so
/// tests can replace it.
abstract class Authenticator {
  /// True if the phone has a screen lock or biometric the prompt can use.
  Future<bool> isAvailable();
  Future<bool> authenticate(String reason);
}

class DeviceAuthenticator implements Authenticator {
  final _auth = LocalAuthentication();

  @override
  Future<bool> isAvailable() => _auth.isDeviceSupported();

  @override
  Future<bool> authenticate(String reason) async {
    try {
      // Biometric or the phone's PIN, pattern or password, whichever the person
      // has. Insisting on biometrics would lock out anyone whose sensor fails.
      return await _auth.authenticate(localizedReason: reason);
    } on LocalAuthException {
      // Cancelled, timed out, or no credentials: all mean "not unlocked".
      return false;
    }
  }
}

final authenticatorProvider = Provider<Authenticator>((ref) => DeviceAuthenticator());

class LockState {
  const LockState({required this.enabled, required this.graceMinutes, required this.locked});

  final bool enabled;

  /// How long the app may sit in the background before it asks again. 0 asks
  /// every time.
  final int graceMinutes;
  final bool locked;

  LockState copyWith({bool? enabled, int? graceMinutes, bool? locked}) =>
      LockState(enabled: enabled ?? this.enabled, graceMinutes: graceMinutes ?? this.graceMinutes, locked: locked ?? this.locked);
}

const graceChoices = [0, 1, 5];

class LockController extends Notifier<LockState> {
  // The system prompt backgrounds the app on some phones. Coming back from it
  // must not count as coming back from the background.
  bool _prompting = false;

  @override
  LockState build() {
    final prefs = ref.read(sharedPreferencesProvider);
    final enabled = prefs.getBool(_enabledKey) ?? false;
    // A cold start is a fresh open: locked if the lock is on.
    return LockState(enabled: enabled, graceMinutes: prefs.getInt(_graceKey) ?? 1, locked: enabled);
  }

  Future<bool> _prompt(String reason) async {
    _prompting = true;
    try {
      return await ref.read(authenticatorProvider).authenticate(reason);
    } finally {
      _prompting = false;
    }
  }

  /// Turning the lock on proves it works first, so nobody locks themselves out
  /// of a phone with no screen lock. Returns false with the lock left off.
  Future<bool> enable() async {
    if (!await ref.read(authenticatorProvider).isAvailable()) return false;
    if (!await _prompt('Confirm to turn on the Paisa lock')) return false;
    await ref.read(sharedPreferencesProvider).setBool(_enabledKey, true);
    state = state.copyWith(enabled: true, locked: false);
    return true;
  }

  Future<bool> disable() async {
    if (!await _prompt('Confirm to turn off the Paisa lock')) return false;
    await ref.read(sharedPreferencesProvider).setBool(_enabledKey, false);
    state = state.copyWith(enabled: false, locked: false);
    return true;
  }

  Future<void> setGrace(int minutes) async {
    await ref.read(sharedPreferencesProvider).setInt(_graceKey, minutes);
    state = state.copyWith(graceMinutes: minutes);
  }

  Future<void> unlock() async {
    if (!state.locked) return;
    if (await _prompt('Unlock Paisa')) state = state.copyWith(locked: false);
  }

  /// Called when the app returns to the foreground after [away].
  void resumedAfter(Duration away) {
    if (_prompting || !state.enabled || state.locked) return;
    if (away >= Duration(minutes: state.graceMinutes)) state = state.copyWith(locked: true);
  }

  /// A fresh sign-in has just proved who this is.
  void clear() => state = state.copyWith(locked: false);
}

final lockProvider = NotifierProvider<LockController, LockState>(LockController.new);
