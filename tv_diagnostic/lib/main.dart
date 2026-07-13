import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:share_plus/share_plus.dart';

void main() {
  runApp(const TvDiagnosticApp());
}

class TvDiagnosticApp extends StatelessWidget {
  const TvDiagnosticApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'دیاگ ریموت دوو',
      debugShowCheckedModeBanner: false,
      theme: ThemeData.dark(useMaterial3: true).copyWith(
        scaffoldBackgroundColor: Colors.black,
      ),
      home: const DiagnosticScreen(),
    );
  }
}

class DiagnosticScreen extends StatefulWidget {
  const DiagnosticScreen({super.key});

  @override
  State<DiagnosticScreen> createState() => _DiagnosticScreenState();
}

class _DiagnosticScreenState extends State<DiagnosticScreen> {
  static const _keyChannel = EventChannel('daewoo_tv_diag/keys');
  static const _btChannel = EventChannel('daewoo_tv_diag/bt');

  final List<String> _log = [];
  StreamSubscription? _keySub;
  StreamSubscription? _btSub;

  @override
  void initState() {
    super.initState();
    _keySub = _keyChannel.receiveBroadcastStream().listen((event) {
      _addLine('⌨️ $event');
    });
    _btSub = _btChannel.receiveBroadcastStream().listen((event) {
      _addLine('📶 $event');
    });
    _addLine(
      'آماده — این صفحه را باز نگه دارید، سپس دکمه‌های ریموت (IR) یا '
      'دکمه‌های اپ گوشی (بلوتوث) را بزنید. هر چیزی که واقعاً به تلویزیون '
      'برسد همین‌جا نشان داده می‌شود.',
    );
  }

  void _addLine(String line) {
    setState(() {
      _log.insert(0, line);
      if (_log.length > 500) _log.removeLast();
    });
  }

  @override
  void dispose() {
    _keySub?.cancel();
    _btSub?.cancel();
    super.dispose();
  }

  Future<void> _shareLog() async {
    final text = _log.reversed.join('\n');
    await SharePlus.instance.share(ShareParams(text: text, subject: 'لاگ دیاگ ریموت دوو'));
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Scaffold(
        appBar: AppBar(
          title: const Text('دیاگ ریموت دوو — تلویزیون'),
          actions: [
            IconButton(
              icon: const Icon(Icons.ios_share),
              tooltip: 'ارسال لاگ',
              onPressed: _shareLog,
            ),
            IconButton(
              icon: const Icon(Icons.delete_outline),
              tooltip: 'پاک کردن',
              onPressed: () => setState(_log.clear),
            ),
          ],
        ),
        body: ListView.builder(
          padding: const EdgeInsets.all(12),
          itemCount: _log.length,
          itemBuilder: (context, i) => Padding(
            padding: const EdgeInsets.symmetric(vertical: 4),
            child: Text(
              _log[i],
              style: const TextStyle(fontFamily: 'monospace', fontSize: 16),
            ),
          ),
        ),
      ),
    );
  }
}
