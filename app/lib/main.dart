import 'package:flutter/material.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'ui/receiver_view.dart';
import 'ui/sender_view.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  try {
    await WebRTC.initialize(options: {
      'zeroPlayoutDelay': true,
    });
  } catch (_) {}
  runApp(const DoScreenApp());
}

class DoScreenApp extends StatelessWidget {
  const DoScreenApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'DoScreen',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        brightness: Brightness.dark,
        scaffoldBackgroundColor: const Color(0xFF0D1117),
        colorScheme: const ColorScheme.dark(
          primary: Colors.cyanAccent,
          secondary: Colors.blueAccent,
          surface: Color(0xFF161B22),
        ),
        useMaterial3: true,
      ),
      home: const HomeScreen(),
    );
  }
}

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> with SingleTickerProviderStateMixin {
  late TabController _tabController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(6),
              decoration: BoxDecoration(
                color: Colors.cyanAccent.withValues(alpha: 0.2),
                borderRadius: BorderRadius.circular(8),
              ),
              child: const Icon(Icons.cast_connected, color: Colors.cyanAccent, size: 20),
            ),
            const SizedBox(width: 10),
            const Text(
              'DoScreen',
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
            ),
          ],
        ),
        backgroundColor: const Color(0xFF161B22),
        bottom: TabBar(
          controller: _tabController,
          indicatorColor: Colors.cyanAccent,
          labelColor: Colors.cyanAccent,
          unselectedLabelColor: Colors.grey,
          tabs: const [
            Tab(icon: Icon(Icons.tv), text: 'Alıcı (TV / Ekran)'),
            Tab(icon: Icon(Icons.screen_share), text: 'Gönderici (Ekran Paylaş)'),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: const [
          ReceiverView(),
          SenderView(),
        ],
      ),
    );
  }
}
