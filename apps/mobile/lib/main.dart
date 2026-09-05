import 'package:flutter/material.dart';

import 'services/api_client.dart';
import 'services/firebase_bootstrap.dart';
import 'services/offline_queue.dart';
import 'services/sms_bridge.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await FirebaseBootstrap.initialize();
  runApp(const PaisaApp());
}

class PaisaApp extends StatelessWidget {
  const PaisaApp({super.key});

  @override
  Widget build(BuildContext context) => MaterialApp(
    debugShowCheckedModeBanner: false,
    title: 'Paisa',
    theme: ThemeData(
      useMaterial3: true,
      colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xff1e5c45)),
      scaffoldBackgroundColor: const Color(0xfff6f5ef),
    ),
    home: const HomeScreen(),
  );
}

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final _sms = SmsBridge();
  final _queue = OfflineQueue();
  final _api = ApiClient();
  int _tab = 0;
  int _pending = 3;
  bool _syncing = false;
  bool _permission = false;

  @override
  void initState() {
    super.initState();
    _checkSms();
  }

  Future<void> _checkSms() async {
    try {
      final allowed = await _sms.hasPermission();
      if (mounted) setState(() => _permission = allowed);
      if (allowed) await _sync();
    } catch (_) {
      // The app remains useful with statement import and manual entry.
    }
  }

  Future<void> _enableSms() async {
    final allowed = await _sms.requestPermission();
    if (mounted) setState(() => _permission = allowed);
    if (allowed) await _sync();
  }

  Future<void> _sync() async {
    if (_syncing) return;
    setState(() => _syncing = true);
    try {
      await _queue.addAll(await _sms.drainEvents());
      final firebaseToken = await FirebaseBootstrap.idToken();
      final appCheckToken = await FirebaseBootstrap.appCheckToken();
      for (final event in await _queue.read()) {
        try {
          await _api.uploadEvent(
            event,
            firebaseToken: firebaseToken,
            appCheckToken: appCheckToken,
          );
          await _queue.remove(event.sourceHash);
        } catch (_) {
          break;
        }
      }
    } finally {
      if (mounted) setState(() => _syncing = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      backgroundColor: const Color(0xff153e31),
      foregroundColor: Colors.white,
      title: const Row(
        children: [PaisaLogo(), SizedBox(width: 10), Text('Paisa')],
      ),
      actions: [
        IconButton(
          onPressed: _sync,
          tooltip: 'Sync transactions',
          icon: _syncing
              ? const SizedBox.square(
                  dimension: 18,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: Colors.white,
                  ),
                )
              : const Icon(Icons.sync),
        ),
        const Padding(
          padding: EdgeInsets.only(right: 14),
          child: CircleAvatar(
            radius: 16,
            backgroundColor: Color(0xffdfe9c1),
            child: Text(
              'AM',
              style: TextStyle(
                fontSize: 10,
                color: Color(0xff264d3c),
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        ),
      ],
    ),
    body: IndexedStack(
      index: _tab,
      children: [
        OverviewPage(
          smsEnabled: _permission,
          pending: _pending,
          onEnableSms: _enableSms,
          onReviewed: () =>
              setState(() => _pending = (_pending - 1).clamp(0, 99)),
        ),
        const PlaceholderPage(
          icon: Icons.swap_horiz,
          title: 'Transactions',
          copy: 'Search, filter, split, and reconcile every payment.',
        ),
        const PlaceholderPage(
          icon: Icons.donut_large,
          title: 'Budgets',
          copy: 'Plan category limits and receive threshold alerts.',
        ),
        const PlaceholderPage(
          icon: Icons.people_outline,
          title: 'Books and access',
          copy: 'Manage private books, household sharing, and CA access.',
        ),
      ],
    ),
    bottomNavigationBar: NavigationBar(
      selectedIndex: _tab,
      onDestinationSelected: (index) => setState(() => _tab = index),
      destinations: const [
        NavigationDestination(
          icon: Icon(Icons.home_outlined),
          label: 'Overview',
        ),
        NavigationDestination(icon: Icon(Icons.swap_horiz), label: 'Activity'),
        NavigationDestination(icon: Icon(Icons.donut_large), label: 'Budgets'),
        NavigationDestination(
          icon: Icon(Icons.person_outline),
          label: 'Profile',
        ),
      ],
    ),
  );
}

class PaisaLogo extends StatelessWidget {
  const PaisaLogo({super.key});

  @override
  Widget build(BuildContext context) => Transform.rotate(
    angle: -.08,
    child: Container(
      width: 32,
      height: 32,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: const Color(0xffd9e8a8),
        borderRadius: BorderRadius.circular(10),
      ),
      child: const Text(
        '₹',
        style: TextStyle(
          color: Color(0xff173d31),
          fontSize: 20,
          fontWeight: FontWeight.w900,
        ),
      ),
    ),
  );
}

class OverviewPage extends StatelessWidget {
  const OverviewPage({
    super.key,
    required this.smsEnabled,
    required this.pending,
    required this.onEnableSms,
    required this.onReviewed,
  });

  final bool smsEnabled;
  final int pending;
  final VoidCallback onEnableSms;
  final VoidCallback onReviewed;

  @override
  Widget build(BuildContext context) => ListView(
    padding: const EdgeInsets.fromLTRB(16, 18, 16, 28),
    children: [
      const Text(
        'Good evening, Arjun',
        style: TextStyle(fontSize: 25, fontWeight: FontWeight.w600),
      ),
      const SizedBox(height: 4),
      Text(
        'Sample pilot data · 26 August',
        style: TextStyle(color: Colors.grey.shade600, fontSize: 12),
      ),
      const SizedBox(height: 18),
      if (smsEnabled)
        ReviewCard(pending: pending, onReviewed: onReviewed)
      else
        PermissionCard(onEnable: onEnableSms),
      const SizedBox(height: 16),
      const Row(
        children: [
          Expanded(
            child: MetricCard(
              label: 'INCOME',
              value: '₹5,87,867',
              accent: Color(0xffdfead5),
            ),
          ),
          SizedBox(width: 10),
          Expanded(
            child: MetricCard(
              label: 'SPENT',
              value: '₹2,87,550',
              accent: Color(0xfff2d7cc),
            ),
          ),
        ],
      ),
      const SizedBox(height: 10),
      const MetricCard(
        label: 'SAVED THIS MONTH',
        value: '₹3,00,317',
        accent: Color(0xffd9e7e1),
      ),
      const SizedBox(height: 16),
      const FinanceCard(
        title: 'Where your money went',
        child: Row(
          children: [
            SpendingRing(),
            SizedBox(width: 20),
            Expanded(
              child: Column(
                children: [
                  LegendRow(
                    label: 'Essentials',
                    value: '₹1,92,750',
                    color: Color(0xff244e3c),
                  ),
                  SizedBox(height: 14),
                  LegendRow(
                    label: 'Lifestyle',
                    value: '₹94,800',
                    color: Color(0xffa9c467),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
      const SizedBox(height: 16),
      const FinanceCard(
        title: 'Recent activity',
        child: Column(
          children: [
            TransactionRow(
              initial: 'S',
              name: 'Swiggy',
              category: 'Food delivery',
              amount: '−₹750',
            ),
            TransactionRow(
              initial: 'H',
              name: 'Hostel EMI',
              category: 'Needs review',
              amount: '−₹35,000',
            ),
            TransactionRow(
              initial: 'A',
              name: 'Acme Technologies',
              category: 'Salary',
              amount: '+₹5,87,867',
              positive: true,
            ),
          ],
        ),
      ),
    ],
  );
}

class PermissionCard extends StatelessWidget {
  const PermissionCard({super.key, required this.onEnable});
  final VoidCallback onEnable;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(17),
    decoration: BoxDecoration(
      color: const Color(0xfffff4df),
      borderRadius: BorderRadius.circular(14),
      border: Border.all(color: const Color(0xffeddbb5)),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Row(
          children: [
            Icon(Icons.sms_outlined, color: Color(0xff7d6333)),
            SizedBox(width: 10),
            Expanded(
              child: Text(
                'Turn on automatic payment capture',
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        const Text(
          'Paisa extracts only bank and UPI transaction details. Non-financial messages never leave your phone.',
          style: TextStyle(fontSize: 12, height: 1.4),
        ),
        const SizedBox(height: 12),
        FilledButton(
          onPressed: onEnable,
          child: const Text('Allow financial SMS'),
        ),
      ],
    ),
  );
}

class ReviewCard extends StatelessWidget {
  const ReviewCard({
    super.key,
    required this.pending,
    required this.onReviewed,
  });
  final int pending;
  final VoidCallback onReviewed;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(17),
    decoration: BoxDecoration(
      color: const Color(0xffeff5de),
      borderRadius: BorderRadius.circular(14),
      border: Border.all(color: const Color(0xffd7e2c0)),
    ),
    child: Row(
      children: [
        const CircleAvatar(
          backgroundColor: Color(0xffdbe8a9),
          child: Icon(Icons.check, color: Color(0xff315c43)),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '$pending payments need review',
                style: const TextStyle(fontWeight: FontWeight.bold),
              ),
              const Text(
                'Confirm while they are fresh.',
                style: TextStyle(fontSize: 11),
              ),
            ],
          ),
        ),
        FilledButton(
          onPressed: pending == 0 ? null : onReviewed,
          child: const Text('Review'),
        ),
      ],
    ),
  );
}

class MetricCard extends StatelessWidget {
  const MetricCard({
    super.key,
    required this.label,
    required this.value,
    required this.accent,
  });
  final String label;
  final String value;
  final Color accent;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(17),
    decoration: BoxDecoration(
      color: Colors.white,
      borderRadius: BorderRadius.circular(14),
      border: Border.all(color: const Color(0xffe6e7df)),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: TextStyle(
            fontSize: 10,
            color: Colors.grey.shade600,
            fontWeight: FontWeight.bold,
            letterSpacing: .8,
          ),
        ),
        const SizedBox(height: 9),
        Text(
          value,
          style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w600),
        ),
        Align(
          alignment: Alignment.centerRight,
          child: Container(
            width: 32,
            height: 7,
            decoration: BoxDecoration(
              color: accent,
              borderRadius: BorderRadius.circular(8),
            ),
          ),
        ),
      ],
    ),
  );
}

class FinanceCard extends StatelessWidget {
  const FinanceCard({super.key, required this.title, required this.child});
  final String title;
  final Widget child;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(18),
    decoration: BoxDecoration(
      color: Colors.white,
      borderRadius: BorderRadius.circular(14),
      border: Border.all(color: const Color(0xffe6e7df)),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
        ),
        const SizedBox(height: 18),
        child,
      ],
    ),
  );
}

class SpendingRing extends StatelessWidget {
  const SpendingRing({super.key});

  @override
  Widget build(BuildContext context) => Container(
    width: 105,
    height: 105,
    padding: const EdgeInsets.all(18),
    decoration: const BoxDecoration(
      shape: BoxShape.circle,
      gradient: SweepGradient(
        colors: [
          Color(0xff244e3c),
          Color(0xff244e3c),
          Color(0xffa9c467),
          Color(0xffa9c467),
        ],
        stops: [0, .67, .67, 1],
      ),
    ),
    child: Container(
      alignment: Alignment.center,
      decoration: const BoxDecoration(
        shape: BoxShape.circle,
        color: Colors.white,
      ),
      child: const Text('48.9%', style: TextStyle(fontWeight: FontWeight.bold)),
    ),
  );
}

class LegendRow extends StatelessWidget {
  const LegendRow({
    super.key,
    required this.label,
    required this.value,
    required this.color,
  });
  final String label;
  final String value;
  final Color color;

  @override
  Widget build(BuildContext context) => Row(
    children: [
      Container(
        width: 9,
        height: 9,
        decoration: BoxDecoration(shape: BoxShape.circle, color: color),
      ),
      const SizedBox(width: 8),
      Expanded(child: Text(label, style: const TextStyle(fontSize: 12))),
      Text(
        value,
        style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
      ),
    ],
  );
}

class TransactionRow extends StatelessWidget {
  const TransactionRow({
    super.key,
    required this.initial,
    required this.name,
    required this.category,
    required this.amount,
    this.positive = false,
  });
  final String initial;
  final String name;
  final String category;
  final String amount;
  final bool positive;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 9),
    child: Row(
      children: [
        CircleAvatar(
          radius: 17,
          backgroundColor: const Color(0xffeef1e9),
          child: Text(
            initial,
            style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                name,
                style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                ),
              ),
              Text(
                category,
                style: TextStyle(fontSize: 10, color: Colors.grey.shade600),
              ),
            ],
          ),
        ),
        Text(
          amount,
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.bold,
            color: positive ? const Color(0xff377252) : null,
          ),
        ),
      ],
    ),
  );
}

class PlaceholderPage extends StatelessWidget {
  const PlaceholderPage({
    super.key,
    required this.icon,
    required this.title,
    required this.copy,
  });
  final IconData icon;
  final String title;
  final String copy;

  @override
  Widget build(BuildContext context) => Center(
    child: Padding(
      padding: const EdgeInsets.all(32),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 48, color: const Color(0xff315b46)),
          const SizedBox(height: 16),
          Text(
            title,
            style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 8),
          Text(copy, textAlign: TextAlign.center),
        ],
      ),
    ),
  );
}
