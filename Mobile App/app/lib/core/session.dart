import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'api/api_client.dart';
import 'api/models.dart';
import 'auth/auth_service.dart';
import 'prefs.dart';

const _bookKey = 'paisa.book';

/// Where the person is in the way in. The screens switch on this and nothing else.
sealed class SessionState {
  const SessionState();
}

class SignedOut extends SessionState {
  const SignedOut();
}

/// Signed in to Firebase, but the ledger has no household for this account
/// (`403 INVITE_REQUIRED`): they need an invitation or an administrator's approval.
class NoHousehold extends SessionState {
  const NoHousehold();
}

class Ready extends SessionState {
  const Ready({required this.me, required this.books, required this.book});

  final Me me;
  final List<Book> books;

  /// Null while somebody with several books has not chosen one.
  final Book? book;

  Ready withBook(Book? chosen) => Ready(me: me, books: books, book: chosen);
}

final authServiceProvider = Provider<AuthService>((ref) => throw UnimplementedError('Override authServiceProvider'));

final signedInProvider = StreamProvider<bool>((ref) => ref.watch(authServiceProvider).signedInChanges);

final apiClientProvider = Provider<ApiClient>((ref) {
  final client = ApiClient(baseUrl: AppConfig.apiUrl, auth: ref.watch(authServiceProvider));
  ref.onDispose(client.close);
  return client;
});

class SessionController extends AsyncNotifier<SessionState> {
  @override
  Future<SessionState> build() async {
    // Both dependencies are read before the first await so they are tracked.
    final api = ref.watch(apiClientProvider);
    final signedIn = await ref.watch(signedInProvider.future);
    if (!signedIn) return const SignedOut();
    try {
      final me = Me.fromJson(await api.get('/v1/me') as Map<String, dynamic>);
      final json = await api.get('/v1/books') as Map<String, dynamic>;
      final books = [for (final item in json['items'] as List) Book.fromJson(item as Map<String, dynamic>)];
      return Ready(me: me, books: books, book: _remembered(books));
    } on ApiError catch (error) {
      if (error.status == 403 && error.code == 'INVITE_REQUIRED') return const NoHousehold();
      // The token was refreshed once already inside the client. A second 401
      // means this sign-in is no good any more.
      if (error.isUnauthenticated) {
        await ref.read(authServiceProvider).signOut();
        return const SignedOut();
      }
      rethrow;
    }
  }

  Book? _remembered(List<Book> books) {
    if (books.length == 1) return books.single;
    final saved = ref.read(sharedPreferencesProvider).getString(_bookKey);
    for (final book in books) {
      if (book.id == saved) return book;
    }
    return null;
  }

  Future<void> chooseBook(Book book) async {
    final current = state.value;
    if (current is! Ready) return;
    await ref.read(sharedPreferencesProvider).setString(_bookKey, book.id);
    state = AsyncData(current.withBook(book));
  }

  /// Forget the choice so the picker shows again.
  Future<void> changeBook() async {
    final current = state.value;
    if (current is! Ready) return;
    await ref.read(sharedPreferencesProvider).remove(_bookKey);
    state = AsyncData(current.withBook(null));
  }

  Future<void> signOut() async {
    // Nothing of this person may survive on the phone for the next one.
    await ref.read(sharedPreferencesProvider).remove(_bookKey);
    await ref.read(authServiceProvider).signOut();
  }

  Future<void> reload() async {
    ref.invalidateSelf();
    await future;
  }
}

final sessionProvider = AsyncNotifierProvider<SessionController, SessionState>(SessionController.new);

/// The book everything below the picker works on, or null if none is chosen.
final bookProvider = Provider<Book?>((ref) {
  final session = ref.watch(sessionProvider).value;
  return session is Ready ? session.book : null;
});
