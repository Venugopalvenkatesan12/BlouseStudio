import 'dart:io';
import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import 'db.dart';
import 'screens.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  DB.initPlatform();
  await Settings.load();
  runApp(const BlouseApp());
}

class BlouseApp extends StatelessWidget {
  const BlouseApp({super.key});
  @override
  Widget build(BuildContext context) => MaterialApp(
        title: 'Blouse Studio',
        debugShowCheckedModeBanner: false,
        theme: ThemeData(colorSchemeSeed: Colors.pink, useMaterial3: true),
        home: const Home(),
      );
}

class Home extends StatefulWidget {
  const Home({super.key});
  @override
  State<Home> createState() => _HomeState();
}

class _HomeState extends State<Home> {
  int tab = 0;
  static const titles = ['Print', 'Customers', 'Designs', 'Orders'];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text('Blouse Studio - ${titles[tab]}'), actions: [
        IconButton(
          icon: const Icon(Icons.settings),
          onPressed: () async {
            if (await askPin(context) && context.mounted) {
              Navigator.push(context, MaterialPageRoute(builder: (_) => const SettingsScreen()));
            }
          },
        ),
      ]),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 760),
          child: IndexedStack(index: tab, children: const [PrintScreen(), CustomersScreen(), DesignsScreen(), OrdersScreen()]),
        ),
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: tab,
        onDestinationSelected: (i) => setState(() => tab = i),
        destinations: const [
          NavigationDestination(icon: Icon(Icons.print), label: 'Print'),
          NavigationDestination(icon: Icon(Icons.people), label: 'Customers'),
          NavigationDestination(icon: Icon(Icons.checkroom), label: 'Designs'),
          NavigationDestination(icon: Icon(Icons.list_alt), label: 'Orders'),
        ],
      ),
    );
  }
}

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});
  @override
  State<SettingsScreen> createState() => _SettingsState();
}

class _SettingsState extends State<SettingsScreen> {
  final seam = TextEditingController(text: Settings.seam.toString());
  final hem = TextEditingController(text: Settings.hem.toString());
  final fab = TextEditingController(text: Settings.fabricW.toString());
  final pin = TextEditingController(text: Settings.pin);

  Widget field(TextEditingController c, String label, {bool number = true}) => Padding(
        padding: const EdgeInsets.only(bottom: 12),
        child: TextField(
          controller: c,
          keyboardType: number ? const TextInputType.numberWithOptions(decimal: true) : TextInputType.number,
          decoration: InputDecoration(labelText: label, border: const OutlineInputBorder()),
        ),
      );

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: ListView(padding: const EdgeInsets.all(16), children: [
        field(seam, 'Seam allowance (inches)'),
        field(hem, 'Extra hem length (inches)'),
        field(fab, 'Fabric width for layout (inches)'),
        field(pin, 'PIN (for settings and deleting)', number: false),
        FilledButton(
          onPressed: () async {
            Settings.seam = double.tryParse(seam.text) ?? Settings.seam;
            Settings.hem = double.tryParse(hem.text) ?? Settings.hem;
            Settings.fabricW = double.tryParse(fab.text) ?? Settings.fabricW;
            if (pin.text.length >= 4) Settings.pin = pin.text;
            await Settings.save();
            if (context.mounted) {
              toast(context, 'Saved');
              Navigator.pop(context);
            }
          },
          child: const Padding(padding: EdgeInsets.all(12), child: Text('Save settings')),
        ),
        const Divider(height: 40),
        OutlinedButton.icon(
          onPressed: () async {
            final src = await DB.path;
            if (Platform.isWindows) {
              final docs = await getApplicationDocumentsDirectory();
              final dest = p.join(docs.path, 'BlouseStudio_backup_${DateTime.now().millisecondsSinceEpoch}.db');
              await File(src).copy(dest);
              if (context.mounted) toast(context, 'Backup saved: $dest');
            } else {
              await Share.shareXFiles([XFile(src)], text: 'Blouse Studio backup');
            }
          },
          icon: const Icon(Icons.backup),
          label: const Padding(
              padding: EdgeInsets.all(12), child: Text('Backup database (share to Drive / WhatsApp)')),
        ),
        const SizedBox(height: 10),
        const Text('Backup saves customers, measurements, designs and orders (not design photos).'),
      ]),
    );
  }
}
