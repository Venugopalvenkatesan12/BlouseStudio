import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite/sqflite.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

/// Bumped after every write so screens reload.
final ValueNotifier<int> dataVersion = ValueNotifier<int>(0);

class Settings {
  static double seam = 0.5, hem = 0.5, fabricW = 40;
  static String pin = '1234';
  static late SharedPreferences _p;
  static Future<void> load() async {
    _p = await SharedPreferences.getInstance();
    seam = _p.getDouble('seam') ?? 0.5;
    hem = _p.getDouble('hem') ?? 0.5;
    fabricW = _p.getDouble('fabricW') ?? 40;
    pin = _p.getString('pin') ?? '1234';
  }

  static Future<void> save() async {
    await _p.setDouble('seam', seam);
    await _p.setDouble('hem', hem);
    await _p.setDouble('fabricW', fabricW);
    await _p.setString('pin', pin);
  }
}

class DB {
  static Database? _db;
  /// Call once at start-up: desktop needs the FFI sqlite implementation.
  static void initPlatform() {
    if (Platform.isWindows || Platform.isLinux) {
      sqfliteFfiInit();
      databaseFactory = databaseFactoryFfi;
    }
  }

  static Future<String> get path async {
    final dir = await getApplicationSupportDirectory();
    await dir.create(recursive: true);
    return p.join(dir.path, 'studio.db');
  }

  static Future<Database> get db async => _db ??= await _open();

  static Future<Database> _open() async {
    return openDatabase(await path, version: 1, onCreate: (d, v) async {
      await d.execute('CREATE TABLE customers(id INTEGER PRIMARY KEY AUTOINCREMENT, name TEXT, phone TEXT, m TEXT)');
      await d.execute('CREATE TABLE designs(id INTEGER PRIMARY KEY AUTOINCREMENT, cat TEXT, name TEXT, depth REAL, width REAL, length REAL, style TEXT, image TEXT)');
      await d.execute('CREATE TABLE orders(id INTEGER PRIMARY KEY AUTOINCREMENT, cust_id INTEGER, neck_id INTEGER, back_id INTEGER, sleeve_id INTEGER, fabric TEXT, due TEXT, status TEXT, created TEXT)');
      const seed = [
        ['Front Neck', 'Round Neck', 3.5, 3.0, 0.0, 'round'],
        ['Front Neck', 'Deep Round', 5.5, 3.2, 0.0, 'round'],
        ['Front Neck', 'V Neck', 6.0, 3.2, 0.0, 'v'],
        ['Front Neck', 'Square Neck', 4.5, 3.2, 0.0, 'square'],
        ['Front Neck', 'Boat Neck', 2.0, 4.5, 0.0, 'round'],
        ['Back Neck', 'Round Back', 4.0, 3.0, 0.0, 'round'],
        ['Back Neck', 'Deep U Back', 8.0, 3.2, 0.0, 'round'],
        ['Back Neck', 'V Back', 8.0, 3.2, 0.0, 'v'],
        ['Back Neck', 'Square Back', 6.0, 3.2, 0.0, 'square'],
        ['Back Neck', 'Deep Square Back', 9.0, 3.2, 0.0, 'square'],
        ['Sleeve', 'Sleeveless', 0.0, 0.0, 0.0, 'none'],
        ['Sleeve', 'Short Sleeve', 0.0, 0.0, 5.0, 'flat'],
        ['Sleeve', 'Elbow Sleeve', 0.0, 0.0, 9.0, 'flat'],
        ['Sleeve', '3/4 Sleeve', 0.0, 0.0, 14.0, 'flat'],
      ];
      for (final s in seed) {
        await d.insert('designs', {'cat': s[0], 'name': s[1], 'depth': s[2], 'width': s[3], 'length': s[4], 'style': s[5]});
      }
    });
  }

  // ---- customers
  static Future<List<Map<String, dynamic>>> customers() async =>
      (await db).query('customers', orderBy: 'name COLLATE NOCASE');

  static Future<Map<String, dynamic>?> customer(int id) async {
    final r = await (await db).query('customers', where: 'id=?', whereArgs: [id]);
    return r.isEmpty ? null : r.first;
  }

  static Future<int> saveCustomer(Map<String, dynamic> c) async {
    final d = await db;
    int id;
    if (c['id'] == null) {
      id = await d.insert('customers', c);
    } else {
      await d.update('customers', c, where: 'id=?', whereArgs: [c['id']]);
      id = c['id'] as int;
    }
    dataVersion.value++;
    return id;
  }

  static Future<void> deleteCustomer(int id) async {
    await (await db).delete('customers', where: 'id=?', whereArgs: [id]);
    dataVersion.value++;
  }

  // ---- designs
  static Future<List<Map<String, dynamic>>> designs() async =>
      (await db).query('designs', orderBy: 'cat, name COLLATE NOCASE');

  static Future<Map<String, dynamic>?> design(int id) async {
    final r = await (await db).query('designs', where: 'id=?', whereArgs: [id]);
    return r.isEmpty ? null : r.first;
  }

  static Future<void> saveDesign(Map<String, dynamic> x) async {
    final d = await db;
    if (x['id'] == null) {
      await d.insert('designs', x);
    } else {
      await d.update('designs', x, where: 'id=?', whereArgs: [x['id']]);
    }
    dataVersion.value++;
  }

  static Future<void> deleteDesign(int id) async {
    await (await db).delete('designs', where: 'id=?', whereArgs: [id]);
    dataVersion.value++;
  }

  // ---- orders
  static Future<List<Map<String, dynamic>>> orders() async => (await db).rawQuery(
      'SELECT o.*, c.name AS cname, c.phone AS cphone FROM orders o LEFT JOIN customers c ON c.id=o.cust_id ORDER BY o.id DESC');

  static Future<int> saveOrder(Map<String, dynamic> o) async {
    final id = await (await db).insert('orders', o);
    dataVersion.value++;
    return id;
  }

  static Future<void> setStatus(int id, String status) async {
    await (await db).update('orders', {'status': status}, where: 'id=?', whereArgs: [id]);
    dataVersion.value++;
  }
}

Map<String, double> parseM(String? json) {
  if (json == null || json.isEmpty) return {};
  final raw = jsonDecode(json) as Map<String, dynamic>;
  return raw.map((k, v) => MapEntry(k, (v as num).toDouble()));
}
