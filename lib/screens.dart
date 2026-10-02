import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:printing/printing.dart';
import 'package:pdf/pdf.dart';
import 'package:url_launcher/url_launcher.dart';

import 'db.dart';
import 'pattern.dart';

const statuses = ['Received', 'Cut', 'Stitching', 'Aari / Embroidery', 'Ready', 'Delivered'];

void toast(BuildContext c, String msg) =>
    ScaffoldMessenger.of(c).showSnackBar(SnackBar(content: Text(msg)));

String fmtDate(DateTime d) =>
    '${d.day.toString().padLeft(2, '0')}-${d.month.toString().padLeft(2, '0')}-${d.year}';

Future<bool> askPin(BuildContext context) async {
  final t = TextEditingController();
  final ok = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: const Text('Enter PIN'),
      content: TextField(controller: t, obscureText: true, keyboardType: TextInputType.number, autofocus: true),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
        FilledButton(onPressed: () => Navigator.pop(ctx, t.text == Settings.pin), child: const Text('OK')),
      ],
    ),
  );
  if (ok == false && t.text.isNotEmpty && context.mounted) toast(context, 'Wrong PIN');
  return ok == true;
}

Future<void> whatsapp(String phone, String msg) async {
  var d = phone.replaceAll(RegExp(r'\D'), '');
  if (d.length == 10) d = '91$d'; // India default country code
  await launchUrl(Uri.parse('https://wa.me/$d?text=${Uri.encodeComponent(msg)}'), mode: LaunchMode.externalApplication);
}

Future<void> callPhone(String phone) => launchUrl(Uri(scheme: 'tel', path: phone));

// =====================================================================
// PRINT (home) - quick print or new order
// =====================================================================
class PrintScreen extends StatefulWidget {
  const PrintScreen({super.key});
  @override
  State<PrintScreen> createState() => _PrintState();
}

class _PrintState extends State<PrintScreen> {
  int? custId, neckId, backId, sleeveId;
  final ctl = {for (final k in measureKeys) k: TextEditingController()};
  final fabric = TextEditingController();
  DateTime due = DateTime.now().add(const Duration(days: 7));
  List<Map<String, dynamic>> custs = [], designs = [];

  @override
  void initState() {
    super.initState();
    load();
    dataVersion.addListener(load);
  }

  @override
  void dispose() {
    dataVersion.removeListener(load);
    super.dispose();
  }

  Future<void> load() async {
    final c = await DB.customers(), d = await DB.designs();
    if (!mounted) return;
    setState(() {
      custs = c;
      designs = d;
      if (custId != null && !c.any((e) => e['id'] == custId)) custId = null;
      if (neckId != null && !d.any((e) => e['id'] == neckId)) neckId = null;
      if (backId != null && !d.any((e) => e['id'] == backId)) backId = null;
      if (sleeveId != null && !d.any((e) => e['id'] == sleeveId)) sleeveId = null;
    });
  }

  void pickCustomer(int? id) {
    setState(() => custId = id);
    final c = custs.firstWhere((e) => e['id'] == id);
    final m = parseM(c['m'] as String?);
    for (final k in measureKeys) {
      ctl[k]!.text = m[k] == null ? '' : m[k]!.toString();
    }
  }

  Map<String, double>? readM() {
    final m = <String, double>{};
    for (final k in measureKeys) {
      final v = double.tryParse(ctl[k]!.text.trim());
      if (v == null || v <= 0) {
        toast(context, 'Enter ${measureLabels[k]} (inches)');
        return null;
      }
      m[k] = v;
    }
    return m;
  }

  Map<String, dynamic>? des(int? id) => id == null ? null : designs.firstWhere((e) => e['id'] == id);

  Future<void> preview({bool saveOrder = false}) async {
    final m = readM();
    final neck = des(neckId), back = des(backId), sl = des(sleeveId);
    if (m == null) return;
    if (neck == null || back == null || sl == null) return toast(context, 'Choose front neck, back neck and sleeve');
    var orderNo = 0;
    var name = 'Quick Print', phone = '-';
    if (saveOrder) {
      if (custId == null) return toast(context, 'Select a customer to save an order');
      final c = custs.firstWhere((e) => e['id'] == custId);
      await DB.saveCustomer({'id': custId, 'name': c['name'], 'phone': c['phone'], 'm': jsonEncode(m)});
      orderNo = await DB.saveOrder({
        'cust_id': custId,
        'neck_id': neckId,
        'back_id': backId,
        'sleeve_id': sleeveId,
        'fabric': fabric.text.trim(),
        'due': fmtDate(due),
        'status': 'Received',
        'created': DateTime.now().toIso8601String(),
      });
      name = '${c['name']}';
      phone = '${c['phone']}';
    } else if (custId != null) {
      final c = custs.firstWhere((e) => e['id'] == custId);
      name = '${c['name']}';
      phone = '${c['phone']}';
    }
    if (!mounted) return;
    Navigator.push(
        context,
        MaterialPageRoute(
            builder: (_) => PatternScreen(
                orderNo: orderNo,
                name: name,
                phone: phone,
                due: fmtDate(due),
                fabric: fabric.text.trim(),
                m: m,
                neck: neck,
                back: back,
                sleeve: sl)));
    if (saveOrder && mounted) toast(context, 'Order #$orderNo saved');
  }

  Widget dd(String label, String cat, int? value, void Function(int?) onChanged) {
    final items = designs.where((d) => d['cat'] == cat).toList();
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: DropdownButtonFormField<int>(
        value: value,
        decoration: InputDecoration(labelText: label, border: const OutlineInputBorder()),
        items: [for (final d in items) DropdownMenuItem(value: d['id'] as int, child: Text('${d['name']}'))],
        onChanged: onChanged,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return ListView(padding: const EdgeInsets.all(16), children: [
      Text('Print pattern', style: Theme.of(context).textTheme.headlineSmall),
      const Text('Pick a saved customer or just type measurements for a quick print.'),
      const SizedBox(height: 14),
      DropdownButtonFormField<int>(
        value: custId,
        decoration: const InputDecoration(labelText: 'Customer (optional)', border: OutlineInputBorder()),
        items: [for (final c in custs) DropdownMenuItem(value: c['id'] as int, child: Text('${c['name']}  ${c['phone']}'))],
        onChanged: pickCustomer,
      ),
      const SizedBox(height: 12),
      Wrap(spacing: 10, runSpacing: 10, children: [
        for (final k in measureKeys)
          SizedBox(
            width: 160,
            child: TextField(
              controller: ctl[k],
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              decoration: InputDecoration(labelText: '${measureLabels[k]} (in)', border: const OutlineInputBorder()),
            ),
          ),
      ]),
      const SizedBox(height: 16),
      dd('Front neck design', 'Front Neck', neckId, (v) => setState(() => neckId = v)),
      dd('Back neck design', 'Back Neck', backId, (v) => setState(() => backId = v)),
      dd('Sleeve design', 'Sleeve', sleeveId, (v) => setState(() => sleeveId = v)),
      FilledButton.icon(
        onPressed: () => preview(),
        icon: const Icon(Icons.print),
        label: const Padding(padding: EdgeInsets.all(14), child: Text('Preview & Print pattern')),
      ),
      const Divider(height: 36),
      Text('Save as order (optional)', style: Theme.of(context).textTheme.titleMedium),
      const SizedBox(height: 10),
      TextField(controller: fabric, decoration: const InputDecoration(labelText: 'Fabric / colour', border: OutlineInputBorder())),
      const SizedBox(height: 10),
      OutlinedButton.icon(
        onPressed: () async {
          final d = await showDatePicker(
              context: context, initialDate: due, firstDate: DateTime(2024), lastDate: DateTime(2100));
          if (d != null) setState(() => due = d);
        },
        icon: const Icon(Icons.event),
        label: Text('Due date: ${fmtDate(due)}'),
      ),
      const SizedBox(height: 10),
      OutlinedButton.icon(
        onPressed: () => preview(saveOrder: true),
        icon: const Icon(Icons.save),
        label: const Padding(padding: EdgeInsets.all(12), child: Text('Save order + print')),
      ),
    ]);
  }
}

class PatternScreen extends StatelessWidget {
  final int orderNo;
  final String name, phone, due, fabric;
  final Map<String, double> m;
  final Map<String, dynamic> neck, back, sleeve;
  const PatternScreen(
      {super.key,
      required this.orderNo,
      required this.name,
      required this.phone,
      required this.due,
      required this.fabric,
      required this.m,
      required this.neck,
      required this.back,
      required this.sleeve});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text('Pattern - $name')),
      body: Column(children: [
        Container(
          width: double.infinity,
          color: Colors.amber.shade100,
          padding: const EdgeInsets.all(8),
          child: const Text('Printing tip: choose paper A4 and scale 100% (Actual size, not "Fit to page"). '
              'After printing, check the 2 x 2 inch box on page 1.'),
        ),
        Expanded(
          child: PdfPreview(
            build: (PdfPageFormat f) => buildPatternPdf(
              orderNo: orderNo,
              name: name,
              phone: phone,
              due: due,
              fabric: fabric,
              m: m,
              neck: neck,
              back: back,
              sleeve: sleeve,
              seam: Settings.seam,
              hem: Settings.hem,
              fabricW: Settings.fabricW,
            ),
            initialPageFormat: PdfPageFormat.a4,
            allowPrinting: true,
            allowSharing: true,
            canChangePageFormat: false,
            canChangeOrientation: false,
            canDebug: false,
            pdfFileName: 'blouse_pattern_${orderNo == 0 ? 'quick' : orderNo}.pdf',
          ),
        ),
      ]),
    );
  }
}

// =====================================================================
// CUSTOMERS
// =====================================================================
class CustomersScreen extends StatelessWidget {
  const CustomersScreen({super.key});
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: ValueListenableBuilder<int>(
        valueListenable: dataVersion,
        builder: (_, __, ___) => FutureBuilder<List<Map<String, dynamic>>>(
          future: DB.customers(),
          builder: (ctx, snap) {
            final list = snap.data ?? [];
            if (list.isEmpty) return const Center(child: Text('No customers yet. Tap + to add.'));
            return ListView.separated(
              itemCount: list.length,
              separatorBuilder: (_, __) => const Divider(height: 1),
              itemBuilder: (_, i) => ListTile(
                leading: const CircleAvatar(child: Icon(Icons.person)),
                title: Text('${list[i]['name']}'),
                subtitle: Text('${list[i]['phone']}'),
                onTap: () => Navigator.push(
                    ctx, MaterialPageRoute(builder: (_) => CustomerEdit(customer: Map.of(list[i])))),
              ),
            );
          },
        ),
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const CustomerEdit())),
        child: const Icon(Icons.add),
      ),
    );
  }
}

class CustomerEdit extends StatefulWidget {
  final Map<String, dynamic>? customer;
  const CustomerEdit({super.key, this.customer});
  @override
  State<CustomerEdit> createState() => _CustomerEditState();
}

class _CustomerEditState extends State<CustomerEdit> {
  final name = TextEditingController(), phone = TextEditingController();
  final ctl = {for (final k in measureKeys) k: TextEditingController()};

  @override
  void initState() {
    super.initState();
    final c = widget.customer;
    if (c != null) {
      name.text = '${c['name']}';
      phone.text = '${c['phone']}';
      final m = parseM(c['m'] as String?);
      for (final k in measureKeys) {
        if (m[k] != null) ctl[k]!.text = m[k]!.toString();
      }
    }
  }

  Future<void> save() async {
    if (name.text.trim().isEmpty) return toast(context, 'Enter name');
    final m = <String, double>{};
    for (final k in measureKeys) {
      final t = ctl[k]!.text.trim();
      if (t.isEmpty) continue;
      final v = double.tryParse(t);
      if (v == null) return toast(context, '${measureLabels[k]} must be a number');
      m[k] = v;
    }
    await DB.saveCustomer({
      'id': widget.customer?['id'],
      'name': name.text.trim(),
      'phone': phone.text.trim(),
      'm': jsonEncode(m),
    });
    if (mounted) Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    final isNew = widget.customer == null;
    return Scaffold(
      appBar: AppBar(title: Text(isNew ? 'New customer' : 'Customer'), actions: [
        if (!isNew)
          IconButton(
              icon: const Icon(Icons.delete),
              onPressed: () async {
                if (!await askPin(context)) return;
                await DB.deleteCustomer(widget.customer!['id'] as int);
                if (mounted) Navigator.pop(context);
              }),
      ]),
      body: ListView(padding: const EdgeInsets.all(16), children: [
        TextField(controller: name, decoration: const InputDecoration(labelText: 'Name', border: OutlineInputBorder())),
        const SizedBox(height: 10),
        TextField(
            controller: phone,
            keyboardType: TextInputType.phone,
            decoration: const InputDecoration(labelText: 'Phone', border: OutlineInputBorder())),
        if (!isNew)
          Row(children: [
            TextButton.icon(onPressed: () => callPhone(phone.text), icon: const Icon(Icons.call), label: const Text('Call')),
            TextButton.icon(
                onPressed: () => whatsapp(phone.text, 'Hello ${name.text}'),
                icon: const Icon(Icons.chat),
                label: const Text('WhatsApp')),
          ]),
        const SizedBox(height: 10),
        Wrap(spacing: 10, runSpacing: 10, children: [
          for (final k in measureKeys)
            SizedBox(
              width: 160,
              child: TextField(
                controller: ctl[k],
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                decoration: InputDecoration(labelText: '${measureLabels[k]} (in)', border: const OutlineInputBorder()),
              ),
            ),
        ]),
        const SizedBox(height: 20),
        FilledButton(onPressed: save, child: const Padding(padding: EdgeInsets.all(12), child: Text('Save'))),
      ]),
    );
  }
}

// =====================================================================
// DESIGNS
// =====================================================================
const designCats = ['Front Neck', 'Back Neck', 'Sleeve'];

class DesignsScreen extends StatelessWidget {
  const DesignsScreen({super.key});
  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: designCats.length,
      child: Scaffold(
        appBar: TabBar(tabs: [for (final c in designCats) Tab(text: c)]),
        body: ValueListenableBuilder<int>(
          valueListenable: dataVersion,
          builder: (_, __, ___) => FutureBuilder<List<Map<String, dynamic>>>(
            future: DB.designs(),
            builder: (ctx, snap) {
              final all = snap.data ?? [];
              return TabBarView(children: [
                for (final cat in designCats)
                  GridView.count(
                    crossAxisCount: 2,
                    padding: const EdgeInsets.all(10),
                    mainAxisSpacing: 10,
                    crossAxisSpacing: 10,
                    children: [
                      for (final d in all.where((e) => e['cat'] == cat))
                        InkWell(
                          onTap: () => Navigator.push(
                              ctx, MaterialPageRoute(builder: (_) => DesignEdit(cat: cat, design: Map.of(d)))),
                          child: Card(
                            clipBehavior: Clip.antiAlias,
                            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                              Expanded(
                                child: (d['image'] != null && File('${d['image']}').existsSync())
                                    ? Image.file(File('${d['image']}'), fit: BoxFit.cover)
                                    : const Icon(Icons.checkroom, size: 56, color: Colors.grey),
                              ),
                              Padding(
                                padding: const EdgeInsets.all(8),
                                child: Text('${d['name']}', style: const TextStyle(fontWeight: FontWeight.bold)),
                              ),
                            ]),
                          ),
                        ),
                    ],
                  ),
              ]);
            },
          ),
        ),
        floatingActionButton: Builder(
          builder: (ctx) => FloatingActionButton(
            onPressed: () {
              final cat = designCats[DefaultTabController.of(ctx).index];
              Navigator.push(ctx, MaterialPageRoute(builder: (_) => DesignEdit(cat: cat)));
            },
            child: const Icon(Icons.add),
          ),
        ),
      ),
    );
  }
}

class DesignEdit extends StatefulWidget {
  final String cat;
  final Map<String, dynamic>? design;
  const DesignEdit({super.key, required this.cat, this.design});
  @override
  State<DesignEdit> createState() => _DesignEditState();
}

class _DesignEditState extends State<DesignEdit> {
  final name = TextEditingController(), depth = TextEditingController(), width = TextEditingController(), length = TextEditingController();
  String style = 'round';
  String? image;
  bool get isSleeve => widget.cat == 'Sleeve';

  @override
  void initState() {
    super.initState();
    style = isSleeve ? 'flat' : 'round';
    final d = widget.design;
    if (d != null) {
      name.text = '${d['name']}';
      depth.text = '${d['depth']}';
      width.text = '${d['width']}';
      length.text = '${d['length']}';
      style = '${d['style']}';
      image = d['image'] as String?;
    }
  }

  Future<void> pick(ImageSource src) async {
    final x = await ImagePicker().pickImage(source: src, maxWidth: 1200, imageQuality: 85);
    if (x == null) return;
    final dir = Directory(p.join((await getApplicationDocumentsDirectory()).path, 'designs'));
    await dir.create(recursive: true);
    final dest = p.join(dir.path, '${DateTime.now().millisecondsSinceEpoch}.jpg');
    await File(x.path).copy(dest);
    setState(() => image = dest);
  }

  Future<void> save() async {
    if (name.text.trim().isEmpty) return toast(context, 'Enter design name');
    await DB.saveDesign({
      'id': widget.design?['id'],
      'cat': widget.cat,
      'name': name.text.trim(),
      'depth': double.tryParse(depth.text) ?? 0,
      'width': double.tryParse(width.text) ?? 0,
      'length': double.tryParse(length.text) ?? 0,
      'style': style,
      'image': image,
    });
    if (mounted) Navigator.pop(context);
  }

  Widget num_(TextEditingController c, String label) => Padding(
        padding: const EdgeInsets.only(bottom: 10),
        child: TextField(
            controller: c,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration: InputDecoration(labelText: label, border: const OutlineInputBorder())),
      );

  @override
  Widget build(BuildContext context) {
    final styles = isSleeve ? ['flat', 'none'] : ['round', 'v', 'square'];
    if (!styles.contains(style)) style = styles.first;
    return Scaffold(
      appBar: AppBar(title: Text('${widget.cat} design'), actions: [
        if (widget.design != null)
          IconButton(
              icon: const Icon(Icons.delete),
              onPressed: () async {
                if (!await askPin(context)) return;
                await DB.deleteDesign(widget.design!['id'] as int);
                if (mounted) Navigator.pop(context);
              }),
      ]),
      body: ListView(padding: const EdgeInsets.all(16), children: [
        if (image != null && File(image!).existsSync())
          SizedBox(height: 220, child: Image.file(File(image!), fit: BoxFit.contain)),
        Row(mainAxisAlignment: MainAxisAlignment.center, children: [
          if (!Platform.isWindows)
            TextButton.icon(onPressed: () => pick(ImageSource.camera), icon: const Icon(Icons.camera_alt), label: const Text('Camera')),
          TextButton.icon(onPressed: () => pick(ImageSource.gallery), icon: const Icon(Icons.photo), label: Text(Platform.isWindows ? 'Choose photo' : 'Gallery')),
        ]),
        TextField(controller: name, decoration: const InputDecoration(labelText: 'Design name', border: OutlineInputBorder())),
        const SizedBox(height: 10),
        if (!isSleeve) num_(depth, 'Neck depth (in)'),
        if (!isSleeve) num_(width, 'Neck width (in)'),
        if (isSleeve) num_(length, 'Sleeve length (in)'),
        DropdownButtonFormField<String>(
          value: style,
          decoration: const InputDecoration(labelText: 'Neck / sleeve shape', border: OutlineInputBorder()),
          items: [for (final s in styles) DropdownMenuItem(value: s, child: Text(s))],
          onChanged: (v) => setState(() => style = v!),
        ),
        const SizedBox(height: 20),
        FilledButton(onPressed: save, child: const Padding(padding: EdgeInsets.all(12), child: Text('Save'))),
      ]),
    );
  }
}

// =====================================================================
// ORDERS
// =====================================================================
class OrdersScreen extends StatelessWidget {
  const OrdersScreen({super.key});

  Future<void> openPattern(BuildContext context, Map<String, dynamic> o) async {
    final c = await DB.customer(o['cust_id'] as int);
    final neck = await DB.design(o['neck_id'] as int), back = await DB.design(o['back_id'] as int), sl = await DB.design(o['sleeve_id'] as int);
    if (c == null || neck == null || back == null || sl == null) {
      if (context.mounted) toast(context, 'Customer or design was deleted');
      return;
    }
    final m = parseM(c['m'] as String?);
    if (!measureKeys.every(m.containsKey)) {
      if (context.mounted) toast(context, 'Customer measurements incomplete');
      return;
    }
    if (!context.mounted) return;
    Navigator.push(
        context,
        MaterialPageRoute(
            builder: (_) => PatternScreen(
                orderNo: o['id'] as int,
                name: '${c['name']}',
                phone: '${c['phone']}',
                due: '${o['due']}',
                fabric: '${o['fabric']}',
                m: m,
                neck: neck,
                back: back,
                sleeve: sl)));
  }

  void sheet(BuildContext context, Map<String, dynamic> o) {
    showModalBottomSheet(
      context: context,
      builder: (ctx) => Padding(
        padding: const EdgeInsets.all(16),
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('Order #${o['id']} - ${o['cname']}', style: Theme.of(ctx).textTheme.titleMedium),
          const SizedBox(height: 10),
          Wrap(spacing: 8, children: [
            for (final s in statuses)
              ChoiceChip(
                label: Text(s),
                selected: o['status'] == s,
                onSelected: (_) async {
                  await DB.setStatus(o['id'] as int, s);
                  if (ctx.mounted) Navigator.pop(ctx);
                },
              ),
          ]),
          const SizedBox(height: 10),
          Row(children: [
            TextButton.icon(
                onPressed: () {
                  Navigator.pop(ctx);
                  openPattern(context, o);
                },
                icon: const Icon(Icons.print),
                label: const Text('Pattern / Print')),
            TextButton.icon(
                onPressed: () => whatsapp('${o['cphone']}',
                    'Hello ${o['cname']}, your blouse order #${o['id']} status: ${o['status']}. Due: ${o['due']}.'),
                icon: const Icon(Icons.chat),
                label: const Text('WhatsApp')),
          ]),
        ]),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<int>(
      valueListenable: dataVersion,
      builder: (_, __, ___) => FutureBuilder<List<Map<String, dynamic>>>(
        future: DB.orders(),
        builder: (ctx, snap) {
          final list = snap.data ?? [];
          if (list.isEmpty) return const Center(child: Text('No orders yet. Use "Save as order" on the Print tab.'));
          return ListView.separated(
            itemCount: list.length,
            separatorBuilder: (_, __) => const Divider(height: 1),
            itemBuilder: (_, i) {
              final o = list[i];
              final done = o['status'] == 'Delivered' || o['status'] == 'Ready';
              return ListTile(
                title: Text('#${o['id']}  ${o['cname'] ?? '(deleted customer)'}'),
                subtitle: Text('Due ${o['due']}  |  ${o['fabric'] ?? ''}'),
                trailing: Chip(
                  label: Text('${o['status']}'),
                  backgroundColor: done ? Colors.green.shade100 : Colors.orange.shade100,
                ),
                onTap: () => sheet(ctx, o),
              );
            },
          );
        },
      ),
    );
  }
}
