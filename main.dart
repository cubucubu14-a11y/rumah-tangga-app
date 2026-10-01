import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:intl/intl.dart';
import 'package:intl/date_symbol_data_local.dart';

const String SCRIPT_URL =
    'https://script.google.com/macros/s/AKfycbxcJu1lR7UhCmw1IzAjW9Dl-sU8aQb6kEyWP1RbNXnOWfm7-vRyPaRrL4bGDnbjM9s/exec';

const Color BG = Color(0xFF1E1E2E);
const Color CARD = Color(0xFF313244);
const Color CARD2 = Color(0xFF45475A);
const Color ACCENT = Color(0xFF89B4FA);
const Color GREEN = Color(0xFFA6E3A1);
const Color RED = Color(0xFFF38BA8);
const Color YELLOW = Color(0xFFF9E2AF);
const Color PURPLE = Color(0xFFCBA6F7);

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await initializeDateFormatting('id_ID', null);
  runApp(const RTApp());
}

class RTApp extends StatelessWidget {
  const RTApp({super.key});
  @override
  Widget build(BuildContext context) => MaterialApp(
    title: 'Kas Rumah',
    debugShowCheckedModeBanner: false,
    theme: ThemeData.dark().copyWith(
      scaffoldBackgroundColor: BG,
      colorScheme: const ColorScheme.dark(primary: ACCENT),
    ),
    home: const HomePage(),
  );
}

// ===== HELPERS =====
String tglStr(DateTime d) =>
    '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
String jamStr(DateTime d) =>
    '${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';
String rp(int n) {
  final neg = n < 0;
  final s = n.abs().toString().replaceAllMapped(
    RegExp(r'(\d)(?=(\d{3})+(?!\d))'), (m) => '${m[1]}.');
  return neg ? '-$s' : s;
}
int nowStamp() => DateTime.now().millisecondsSinceEpoch;

String fmtTgl(String t) {
  if (t.length < 10) return t;
  final p = t.split('-');
  const b = ['Jan','Feb','Mar','Apr','Mei','Jun','Jul','Agu','Sep','Okt','Nov','Des'];
  return '${p[2]} ${b[int.parse(p[1]) - 1]} ${p[0]}';
}

Future<Map<String, dynamic>> apiGet(Map<String, String> p) async {
  try {
    final uri = Uri.parse(SCRIPT_URL).replace(queryParameters: p);
    final r = await http.get(uri).timeout(const Duration(seconds: 30));
    if (r.statusCode == 200) return jsonDecode(r.body);
    return {'status': 'error', 'message': 'HTTP ${r.statusCode}'};
  } catch (e) {
    return {'status': 'error', 'message': e.toString()};
  }
}

// ===== MODELS =====
class PengRT {
  final int id;
  String tanggal, jam, kategori, keterangan;
  int nominal;
  bool synced;
  PengRT({
    required this.id, required this.tanggal, required this.jam,
    required this.kategori, required this.keterangan,
    required this.nominal, this.synced = false,
  });
  Map<String, dynamic> toJson() => {
    'id': id, 'tanggal': tanggal, 'jam': jam, 'kategori': kategori,
    'keterangan': keterangan, 'nominal': nominal, 'synced': synced,
  };
  factory PengRT.fromJson(Map m) => PengRT(
    id: (m['id'] as num).toInt(), tanggal: m['tanggal'].toString(),
    jam: m['jam'] ?? '', kategori: m['kategori'] ?? 'Lainnya',
    keterangan: m['keterangan'] ?? '', nominal: (m['nominal'] as num).toInt(),
    synced: m['synced'] ?? false,
  );
}

class Gaji {
  final int id;
  String tanggal, jam, keterangan;
  int nominal;
  bool synced;
  Gaji({
    required this.id, required this.tanggal, required this.jam,
    required this.keterangan, required this.nominal, this.synced = false,
  });
  Map<String, dynamic> toJson() => {
    'id': id, 'tanggal': tanggal, 'jam': jam,
    'keterangan': keterangan, 'nominal': nominal, 'synced': synced,
  };
  factory Gaji.fromJson(Map m) => Gaji(
    id: (m['id'] as num).toInt(), tanggal: m['tanggal'].toString(),
    jam: m['jam'] ?? '', keterangan: m['keterangan'] ?? '',
    nominal: (m['nominal'] as num).toInt(), synced: m['synced'] ?? false,
  );
}

// ===== FILTER =====
enum FilterType { bulanIni, bulan, tahun, custom }

class PeriodeFilter {
  FilterType type;
  DateTime? bulanDipilih;
  int? tahunDipilih;
  DateTime? customMulai, customAkhir;

  PeriodeFilter({
    this.type = FilterType.bulanIni,
    this.bulanDipilih,
    this.tahunDipilih,
    this.customMulai,
    this.customAkhir,
  });

  DateTime get mulai {
    final now = DateTime.now();
    switch (type) {
      case FilterType.bulanIni:
        return DateTime(now.year, now.month, 1);
      case FilterType.bulan:
        return DateTime(bulanDipilih!.year, bulanDipilih!.month, 1);
      case FilterType.tahun:
        return DateTime(tahunDipilih!, 1, 1);
      case FilterType.custom:
        return customMulai!;
    }
  }

  DateTime get akhir {
    final now = DateTime.now();
    switch (type) {
      case FilterType.bulanIni:
        return DateTime(now.year, now.month + 1, 0);
      case FilterType.bulan:
        return DateTime(bulanDipilih!.year, bulanDipilih!.month + 1, 0);
      case FilterType.tahun:
        return DateTime(tahunDipilih!, 12, 31);
      case FilterType.custom:
        return customAkhir!;
    }
  }

  String get label {
    final b = ['Jan','Feb','Mar','Apr','Mei','Jun','Jul','Agu','Sep','Okt','Nov','Des'];
    switch (type) {
      case FilterType.bulanIni:
        final n = DateTime.now();
        return 'Bulan Ini • ${b[n.month - 1]} ${n.year}';
      case FilterType.bulan:
        return '${b[bulanDipilih!.month - 1]} ${bulanDipilih!.year}';
      case FilterType.tahun:
        return 'Tahun $tahunDipilih';
      case FilterType.custom:
        return '${fmtTgl(tglStr(customMulai!))} - ${fmtTgl(tglStr(customAkhir!))}';
    }
  }
}

// ===== HOME =====
class HomePage extends StatefulWidget {
  const HomePage({super.key});
  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> with WidgetsBindingObserver {
  List<PengRT> peng = [];
  List<Gaji> gaji = [];
  List<int> pengDel = [];
  List<int> gajiDel = [];
  Map<String, Map<String, int>> cache = {};
  Map<int, int> saldoAwal = {};

  PeriodeFilter filter = PeriodeFilter();
  bool syncing = false;
  String progress = '';
  bool offline = false;
  bool firstRun = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _init();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState s) {
    if (s == AppLifecycleState.resumed && !firstRun) _sync(silent: true);
  }

  Future<void> _init() async {
    final p = await SharedPreferences.getInstance();
    final pj = p.getString('pengRT');
    if (pj != null) peng = (jsonDecode(pj) as List).map((e) => PengRT.fromJson(e)).toList();
    final gj = p.getString('gaji');
    if (gj != null) gaji = (jsonDecode(gj) as List).map((e) => Gaji.fromJson(e)).toList();
    final pd = p.getString('pengRTDel');
    if (pd != null) pengDel = (jsonDecode(pd) as List).map((e) => (e as num).toInt()).toList();
    final gd = p.getString('gajiDel');
    if (gd != null) gajiDel = (jsonDecode(gd) as List).map((e) => (e as num).toInt()).toList();
    final cj = p.getString('cache');
    if (cj != null) {
      final Map m = jsonDecode(cj);
      cache = m.map((k, v) => MapEntry(k.toString(),
        (v as Map).map((k2, v2) => MapEntry(k2.toString(), (v2 as num).toInt()))));
    }
    final sa = p.getString('saldoAwal');
    if (sa != null) {
      final Map m = jsonDecode(sa);
      saldoAwal = m.map((k, v) => MapEntry(int.parse(k.toString()), (v as num).toInt()));
    }

    firstRun = (pj == null && gj == null && cj == null);
    setState(() {});
    if (firstRun) await _pullAll(initial: true);
  }

  Future<void> _saveAll() async {
    final p = await SharedPreferences.getInstance();
    await p.setString('pengRT', jsonEncode(peng.map((t) => t.toJson()).toList()));
    await p.setString('gaji', jsonEncode(gaji.map((t) => t.toJson()).toList()));
    await p.setString('pengRTDel', jsonEncode(pengDel));
    await p.setString('gajiDel', jsonEncode(gajiDel));
    await p.setString('cache', jsonEncode(cache));
    await p.setString('saldoAwal', jsonEncode(saldoAwal.map((k, v) => MapEntry(k.toString(), v))));
  }

  // ===== HITUNGAN =====
  int get pemasukanPeriode {
    int total = 0;
    cache.forEach((tgl, v) {
      final t = DateTime.parse(tgl);
      if (t.isBefore(filter.mulai) || t.isAfter(filter.akhir)) return;
      total += (v['toko'] ?? 0) + (v['lain'] ?? 0);
    });
    for (final g in gaji) {
      final t = DateTime.parse(g.tanggal);
      if (t.isBefore(filter.mulai) || t.isAfter(filter.akhir)) continue;
      total += g.nominal;
    }
    return total;
  }

  int get pengeluaranPeriode {
    int total = 0;
    for (final p in peng) {
      final t = DateTime.parse(p.tanggal);
      if (t.isBefore(filter.mulai) || t.isAfter(filter.akhir)) continue;
      total += p.nominal;
    }
    return total;
  }

  int get sisa {
    final thn = filter.akhir.year;
    final saldo = saldoAwal[thn] ?? 0;
    int masukKum = 0;
    cache.forEach((tgl, v) {
      final t = DateTime.parse(tgl);
      if (t.year != thn || t.isAfter(filter.akhir)) return;
      masukKum += (v['toko'] ?? 0) + (v['lain'] ?? 0);
    });
    for (final g in gaji) {
      final t = DateTime.parse(g.tanggal);
      if (t.year != thn || t.isAfter(filter.akhir)) continue;
      masukKum += g.nominal;
    }
    int keluarKum = 0;
    for (final p in peng) {
      final t = DateTime.parse(p.tanggal);
      if (t.year != thn || t.isAfter(filter.akhir)) continue;
      keluarKum += p.nominal;
    }
    return saldo + masukKum - keluarKum;
  }

  int get belumSync =>
    peng.where((t) => !t.synced).length + gaji.where((t) => !t.synced).length +
    pengDel.length + gajiDel.length;

  List<dynamic> get riwayat {
    final list = <dynamic>[];
    for (final p in peng) {
      final t = DateTime.parse(p.tanggal);
      if (t.isBefore(filter.mulai) || t.isAfter(filter.akhir)) continue;
      list.add(p);
    }
    for (final g in gaji) {
      final t = DateTime.parse(g.tanggal);
      if (t.isBefore(filter.mulai) || t.isAfter(filter.akhir)) continue;
      list.add(g);
    }
    list.sort((a, b) {
      final tglA = a is PengRT ? a.tanggal : (a as Gaji).tanggal;
      final tglB = b is PengRT ? b.tanggal : (b as Gaji).tanggal;
      final cmp = tglB.compareTo(tglA);
      if (cmp != 0) return cmp;
      final idA = a is PengRT ? a.id : (a as Gaji).id;
      final idB = b is PengRT ? b.id : (b as Gaji).id;
      return idB.compareTo(idA);
    });
    return list;
  }

  // ===== SYNC =====
  Future<Map<String, dynamic>> _upPeng(PengRT t) => apiGet({
    'action': 'upsert-pengeluaran-rt', 'id': t.id.toString(),
    'tanggal': t.tanggal, 'jam': t.jam, 'kategori': t.kategori,
    'keterangan': t.keterangan, 'nominal': t.nominal.toString(),
  });
  Future<Map<String, dynamic>> _delPeng(int id) =>
    apiGet({'action': 'delete-pengeluaran-rt', 'id': id.toString()});
  Future<Map<String, dynamic>> _upGaji(Gaji t) => apiGet({
    'action': 'upsert-gaji', 'id': t.id.toString(),
    'tanggal': t.tanggal, 'jam': t.jam,
    'keterangan': t.keterangan, 'nominal': t.nominal.toString(),
  });
  Future<Map<String, dynamic>> _delGaji(int id) =>
    apiGet({'action': 'delete-gaji', 'id': id.toString()});

  Future<void> _sync({bool silent = false}) async {
    if (syncing) return;
    setState(() { syncing = true; offline = false; });

    final pn = peng.where((t) => !t.synced).toList();
    final gn = gaji.where((t) => !t.synced).toList();
    final pd = List<int>.from(pengDel);
    final gd = List<int>.from(gajiDel);

    final total = pn.length + gn.length + pd.length + gd.length;
    int ke = 0, gagal = 0;
    final sisaP = <int>[];
    final sisaG = <int>[];

    for (final id in pd) {
      ke++; if (mounted) setState(() => progress = 'Hapus RT $ke/$total');
      final r = await _delPeng(id);
      if (r['status'] != 'ok') sisaP.add(id);
      await Future.delayed(const Duration(milliseconds: 60));
    }
    for (final id in gd) {
      ke++; if (mounted) setState(() => progress = 'Hapus Gaji $ke/$total');
      final r = await _delGaji(id);
      if (r['status'] != 'ok') sisaG.add(id);
      await Future.delayed(const Duration(milliseconds: 60));
    }
    for (final t in pn) {
      ke++; if (mounted) setState(() => progress = 'Kirim RT $ke/$total');
      final r = await _upPeng(t);
      if (r['status'] == 'ok') t.synced = true; else gagal++;
      await Future.delayed(const Duration(milliseconds: 60));
    }
    for (final t in gn) {
      ke++; if (mounted) setState(() => progress = 'Kirim Gaji $ke/$total');
      final r = await _upGaji(t);
      if (r['status'] == 'ok') t.synced = true; else gagal++;
      await Future.delayed(const Duration(milliseconds: 60));
    }
    pengDel = sisaP;
    gajiDel = sisaG;
    await _saveAll();

    if (mounted) setState(() => progress = 'Cek hantu...');
    final rh = await apiGet({'action': 'cek-hantu', 'hari': '7'});
    int hantuDihapus = 0;
    if (rh['status'] == 'ok') {
      final lokalRT = peng.map((p) => p.id).toSet();
      final lokalGJ = gaji.map((g) => g.id).toSet();
      final sheetRT = (rh['idsRT'] as List).cast<Map>();
      final sheetGJ = (rh['idsGJ'] as List).cast<Map>();
      final hRT = sheetRT.where((m) => !lokalRT.contains(int.tryParse(m['id'].toString()))).toList();
      final hGJ = sheetGJ.where((m) => !lokalGJ.contains(int.tryParse(m['id'].toString()))).toList();

      if ((hRT.isNotEmpty || hGJ.isNotEmpty) && mounted) {
        final ok = await showDialog<bool>(context: context, builder: (c) => AlertDialog(
          title: const Text('⚠ Ada Data Hantu'),
          content: SingleChildScrollView(child: Column(
            mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('Data di Sheets yang tidak ada di HP (7 hari terakhir):'),
              const SizedBox(height: 8),
              if (hRT.isNotEmpty) ...[
                const Text('Pengeluaran RT:', style: TextStyle(fontWeight: FontWeight.bold, color: RED)),
                ...hRT.take(10).map((m) => Text('  • ${m['tanggal']} - Rp ${rp((m['nominal'] as num).toInt())}',
                  style: const TextStyle(fontSize: 12))),
                if (hRT.length > 10) Text('  ... +${hRT.length - 10} lagi'),
              ],
              if (hGJ.isNotEmpty) ...[
                const SizedBox(height: 8),
                const Text('Gaji:', style: TextStyle(fontWeight: FontWeight.bold, color: GREEN)),
                ...hGJ.take(10).map((m) => Text('  • ${m['tanggal']} - Rp ${rp((m['nominal'] as num).toInt())}',
                  style: const TextStyle(fontSize: 12))),
              ],
              const SizedBox(height: 12),
              const Text('Hapus data ini dari Sheets?'),
            ])),
          actions: [
            TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('BATAL')),
            ElevatedButton(style: ElevatedButton.styleFrom(backgroundColor: RED),
              onPressed: () => Navigator.pop(c, true),
              child: const Text('HAPUS', style: TextStyle(color: Colors.black))),
          ]));
        if (ok == true) {
          for (final m in hRT) {
            final id = int.tryParse(m['id'].toString());
            if (id == null) continue;
            await _delPeng(id);
            hantuDihapus++;
          }
          for (final m in hGJ) {
            final id = int.tryParse(m['id'].toString());
            if (id == null) continue;
            await _delGaji(id);
            hantuDihapus++;
          }
        }
      }
    }

    if (mounted) {
      setState(() { syncing = false; progress = ''; });
      if (!silent) {
        String msg = '✓ Sync selesai';
        if (hantuDihapus > 0) msg += ' ($hantuDihapus hantu dihapus)';
        if (gagal > 0) msg = '$gagal data gagal terkirim';
        _snack(msg, ok: gagal == 0, err: gagal > 0);
      }
    }
  }

  Future<void> _pullAll({bool initial = false}) async {
    setState(() { syncing = true; progress = initial ? 'Tarik data awal...' : 'Tarik dari Sheets...'; });

    if (!initial) {
      final pn = peng.where((t) => !t.synced).toList();
      final gn = gaji.where((t) => !t.synced).toList();
      for (final t in pn) { await _upPeng(t); t.synced = true; }
      for (final t in gn) { await _upGaji(t); t.synced = true; }
      for (final id in pengDel) { await _delPeng(id); }
      for (final id in gajiDel) { await _delGaji(id); }
      pengDel.clear(); gajiDel.clear();
      await _saveAll();
    }

    setState(() => progress = 'Tarik dari Sheets...');
    final r = await apiGet({'action': 'pull-all-data'});
    if (!mounted) return;
    if (r['status'] != 'ok') {
      setState(() { syncing = false; progress = ''; offline = true; });
      _snack('Gagal tarik: ${r['message']}', err: true);
      return;
    }

    final lokalRT = peng.map((p) => p.id).toSet();
    int tambahRT = 0;
    for (final m in (r['pengRT'] as List).cast<Map>()) {
      final id = int.tryParse(m['id'].toString()) ?? 0;
      if (id == 0 || lokalRT.contains(id)) continue;
      peng.add(PengRT(
        id: id, tanggal: m['tanggal'].toString(), jam: m['jam'] ?? '',
        kategori: m['kategori'] ?? 'Lainnya', keterangan: m['keterangan'] ?? '',
        nominal: (m['nominal'] as num).toInt(), synced: true,
      ));
      tambahRT++;
    }

    final lokalGJ = gaji.map((g) => g.id).toSet();
    int tambahGJ = 0;
    for (final m in (r['gaji'] as List).cast<Map>()) {
      final id = int.tryParse(m['id'].toString()) ?? 0;
      if (id == 0 || lokalGJ.contains(id)) continue;
      gaji.add(Gaji(
        id: id, tanggal: m['tanggal'].toString(), jam: m['jam'] ?? '',
        keterangan: m['keterangan'] ?? '',
        nominal: (m['nominal'] as num).toInt(), synced: true,
      ));
      tambahGJ++;
    }

    final c = (r['cache'] as Map);
    c.forEach((k, v) {
      final vm = v as Map;
      cache[k.toString()] = {
        'toko': (vm['toko'] as num?)?.toInt() ?? 0,
        'lain': (vm['lain'] as num?)?.toInt() ?? 0,
      };
    });

    await _saveAll();
    if (!mounted) return;
    setState(() { syncing = false; progress = ''; offline = false; });

    if (initial) {
      _snack('✓ Data awal ditarik: $tambahRT RT, $tambahGJ Gaji', ok: true);
    } else {
      _snack('✓ Sync lengkap: +$tambahRT RT, +$tambahGJ Gaji', ok: true);
    }
  }

  void _snack(String m, {bool ok = false, bool err = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(m), duration: const Duration(seconds: 4),
      backgroundColor: ok ? const Color(0xFF2D4F2D) : err ? const Color(0xFF7F3F3F) : null));
  }

  // ===== AKSI =====
  Future<void> _tambahPeng() async {
    final r = await Navigator.push<bool>(context,
      MaterialPageRoute(builder: (_) => const TambahPengPage()));
    if (r == true) { setState(() {}); _sync(silent: true); }
  }

  Future<void> _tambahGaji() async {
    final r = await Navigator.push<bool>(context,
      MaterialPageRoute(builder: (_) => const TambahGajiPage()));
    if (r == true) { setState(() {}); _sync(silent: true); }
  }

  Future<void> _editPeng(PengRT t) async {
    final r = await Navigator.push<bool>(context,
      MaterialPageRoute(builder: (_) => TambahPengPage(existing: t)));
    if (r == true) { setState(() {}); _sync(silent: true); }
  }

  Future<void> _hapusPeng(PengRT t) async {
    final ok = await showDialog<bool>(context: context, builder: (c) => AlertDialog(
      title: const Text('Hapus?'),
      content: Text('Hapus "${t.keterangan}" Rp ${rp(t.nominal)}?'),
      actions: [
        TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('BATAL')),
        ElevatedButton(style: ElevatedButton.styleFrom(backgroundColor: RED),
          onPressed: () => Navigator.pop(c, true),
          child: const Text('HAPUS', style: TextStyle(color: Colors.black)))]));
    if (ok == true) {
      setState(() {
        peng.removeWhere((x) => x.id == t.id);
        if (t.synced) pengDel.add(t.id);
      });
      await _saveAll();
      _sync(silent: true);
    }
  }

  Future<void> _hapusGaji(Gaji g) async {
    final ok = await showDialog<bool>(context: context, builder: (c) => AlertDialog(
      title: const Text('Hapus Gaji?'),
      content: Text('Hapus "${g.keterangan}" Rp ${rp(g.nominal)}?'),
      actions: [
        TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('BATAL')),
        ElevatedButton(style: ElevatedButton.styleFrom(backgroundColor: RED),
          onPressed: () => Navigator.pop(c, true),
          child: const Text('HAPUS', style: TextStyle(color: Colors.black)))]));
    if (ok == true) {
      setState(() {
        gaji.removeWhere((x) => x.id == g.id);
        if (g.synced) gajiDel.add(g.id);
      });
      await _saveAll();
      _sync(silent: true);
    }
  }

  Future<void> _openFilter() async {
    final r = await showModalBottomSheet<PeriodeFilter>(
      context: context, backgroundColor: CARD,
      builder: (c) => SafeArea(child: Column(mainAxisSize: MainAxisSize.min, children: [
        ListTile(
          leading: const Icon(Icons.today, color: ACCENT),
          title: const Text('Bulan Ini'),
          onTap: () => Navigator.pop(c, PeriodeFilter(type: FilterType.bulanIni)),
        ),
        ListTile(
          leading: const Icon(Icons.calendar_month, color: ACCENT),
          title: const Text('Pilih Bulan...'),
          onTap: () async {
            Navigator.pop(c);
            await _pilihBulan();
          },
        ),
        ListTile(
          leading: const Icon(Icons.calendar_today, color: ACCENT),
          title: const Text('Pilih Tahun...'),
          onTap: () async {
            Navigator.pop(c);
            await _pilihTahun();
          },
        ),
        ListTile(
          leading: const Icon(Icons.date_range, color: ACCENT),
          title: const Text('Custom...'),
          onTap: () async {
            Navigator.pop(c);
            await _pilihCustom();
          },
        ),
      ])),
    );
    if (r != null) setState(() => filter = r);
  }

  Future<void> _pilihBulan() async {
    final now = DateTime.now();
    final r = await showDatePicker(
      context: context,
      initialDate: now,
      firstDate: DateTime(2020),
      lastDate: DateTime(2100),
      helpText: 'PILIH BULAN',
      initialDatePickerMode: DatePickerMode.year,
      builder: (c, ch) => Theme(data: ThemeData.dark().copyWith(
        colorScheme: const ColorScheme.dark(primary: ACCENT, onPrimary: Colors.black,
          surface: BG, onSurface: Colors.white)), child: ch!),
    );
    if (r == null) return;
    setState(() => filter = PeriodeFilter(
      type: FilterType.bulan,
      bulanDipilih: DateTime(r.year, r.month, 1),
    ));
  }

  Future<void> _pilihTahun() async {
    final now = DateTime.now();
    final r = await showDialog<int>(context: context, builder: (c) => SimpleDialog(
      title: const Text('Pilih Tahun'),
      children: List.generate(10, (i) {
        final th = now.year - 5 + i;
        return SimpleDialogOption(
          onPressed: () => Navigator.pop(c, th),
          child: Text('$th'),
        );
      }),
    ));
    if (r == null) return;
    setState(() => filter = PeriodeFilter(type: FilterType.tahun, tahunDipilih: r));
  }

  Future<void> _pilihCustom() async {
    final r = await showDateRangePicker(
      context: context,
      firstDate: DateTime(2020),
      lastDate: DateTime(2100),
      helpText: 'PILIH RENTANG',
      saveText: 'PILIH', cancelText: 'BATAL',
      builder: (c, ch) => Theme(data: ThemeData.dark().copyWith(
        colorScheme: const ColorScheme.dark(primary: ACCENT, onPrimary: Colors.black,
          surface: BG, onSurface: Colors.white)), child: ch!),
    );
    if (r == null) return;
    setState(() => filter = PeriodeFilter(
      type: FilterType.custom,
      customMulai: r.start, customAkhir: r.end,
    ));
  }

  Future<void> _openDetail() async {
    await Navigator.push(context, MaterialPageRoute(
      builder: (_) => DetailPage(
        filter: filter, cache: cache, gaji: gaji, peng: peng,
        saldoAwal: saldoAwal, sisa: sisa,
      )));
  }

  Future<void> _openSaldoAwal() async {
    final r = await Navigator.push<bool>(context, MaterialPageRoute(
      builder: (_) => SaldoAwalPage(saldoAwal: saldoAwal, sisaSekarang: sisa)));
    if (r == true) {
      final p = await SharedPreferences.getInstance();
      final sa = p.getString('saldoAwal');
      if (sa != null) {
        final Map m = jsonDecode(sa);
        saldoAwal = m.map((k, v) => MapEntry(int.parse(k.toString()), (v as num).toInt()));
      }
      setState(() {});
    }
  }

  Future<void> _openLihatSheet() async {
    await Navigator.push(context, MaterialPageRoute(builder: (_) => const LihatSheetPage()));
    _pullAll();
  }

  Color get _syncColor {
    if (syncing) return ACCENT;
    if (offline) return Colors.grey;
    if (belumSync > 0) return YELLOW;
    return GREEN;
  }

  @override
  Widget build(BuildContext context) {
    final rw = riwayat;
    final sk = sisa;
    final cukup = sk >= 0;

    return Scaffold(
      body: SafeArea(child: SingleChildScrollView(
        padding: const EdgeInsets.all(12),
        child: Column(children: [
          Row(children: [
            const Spacer(),
            GestureDetector(
              onTap: syncing ? null : () => _pullAll(),
              child: Container(
                padding: const EdgeInsets.all(6),
                child: syncing
                  ? SizedBox(width: 24, height: 24,
                      child: CircularProgressIndicator(strokeWidth: 2, color: _syncColor))
                  : Icon(Icons.sync, color: _syncColor, size: 26),
              ),
            ),
            PopupMenuButton<String>(
              icon: const Icon(Icons.more_vert, color: Colors.white70, size: 22),
              onSelected: (v) {
                if (v == 'sheet') _openLihatSheet();
                else if (v == 'pull') _pullAll();
                else if (v == 'saldo') _openSaldoAwal();
                else if (v == 'url') _showUrlDialog();
              },
              itemBuilder: (c) => const [
                PopupMenuItem(value: 'sheet', child: Row(children: [
                  Icon(Icons.table_chart, color: GREEN, size: 18),
                  SizedBox(width: 8), Text('Lihat Sheet')])),
                PopupMenuItem(value: 'pull', child: Row(children: [
                  Icon(Icons.cloud_download, color: ACCENT, size: 18),
                  SizedBox(width: 8), Text('Tarik Ulang')])),
                PopupMenuItem(value: 'saldo', child: Row(children: [
                  Icon(Icons.account_balance_wallet, color: YELLOW, size: 18),
                  SizedBox(width: 8), Text('Atur Saldo Awal')])),
                PopupMenuItem(value: 'url', child: Row(children: [
                  Icon(Icons.link, color: PURPLE, size: 18),
                  SizedBox(width: 8), Text('Atur URL')])),
              ],
            ),
          ]),
          const SizedBox(height: 4),

          GestureDetector(
            onTap: _openDetail,
            child: Container(
              padding: const EdgeInsets.all(16), width: double.infinity,
              decoration: BoxDecoration(color: CARD, borderRadius: BorderRadius.circular(14)),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                  Flexible(child: Text(filter.label,
                    style: const TextStyle(fontSize: 13, color: ACCENT))),
                  GestureDetector(onTap: _openFilter,
                    child: const Icon(Icons.arrow_drop_down, color: ACCENT, size: 26)),
                ]),
                const SizedBox(height: 12),
                const Text('SISA', style: TextStyle(color: Colors.white70, fontSize: 13)),
                Text('Rp ${rp(sk)}',
                  style: TextStyle(fontSize: 26, fontWeight: FontWeight.bold,
                    color: cukup ? Colors.white : RED)),
                if (cukup)
                  const Row(children: [
                    Icon(Icons.check_circle, color: GREEN, size: 16),
                    SizedBox(width: 4),
                    Text('Cukup', style: TextStyle(color: GREEN, fontSize: 12)),
                  ])
                else
                  const Row(children: [
                    Icon(Icons.warning, color: RED, size: 16),
                    SizedBox(width: 4),
                    Text('Tidak cukup', style: TextStyle(color: RED, fontSize: 12)),
                  ]),
                const SizedBox(height: 14),
                Row(children: [
                  Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    const Text('Masuk', style: TextStyle(fontSize: 11, color: Colors.white54)),
                    Text('Rp ${rp(pemasukanPeriode)}',
                      style: const TextStyle(color: GREEN, fontWeight: FontWeight.bold, fontSize: 14)),
                  ])),
                  Container(width: 1, height: 30, color: Colors.white24),
                  const SizedBox(width: 12),
                  Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    const Text('Keluar', style: TextStyle(fontSize: 11, color: Colors.white54)),
                    Text('Rp ${rp(pengeluaranPeriode)}',
                      style: const TextStyle(color: RED, fontWeight: FontWeight.bold, fontSize: 14)),
                  ])),
                ]),
              ]),
            ),
          ),
          const SizedBox(height: 12),

          Row(children: [
            Expanded(child: ElevatedButton.icon(
              style: ElevatedButton.styleFrom(backgroundColor: RED, padding: const EdgeInsets.symmetric(vertical: 14)),
              onPressed: _tambahPeng,
              icon: const Icon(Icons.add, color: Colors.black),
              label: const Text('Pengeluaran',
                style: TextStyle(color: Colors.black, fontWeight: FontWeight.bold)))),
            const SizedBox(width: 8),
            Expanded(child: ElevatedButton.icon(
              style: ElevatedButton.styleFrom(backgroundColor: ACCENT, padding: const EdgeInsets.symmetric(vertical: 14)),
              onPressed: _tambahGaji,
              icon: const Icon(Icons.attach_money, color: Colors.black),
              label: const Text('Gaji',
                style: TextStyle(color: Colors.black, fontWeight: FontWeight.bold)))),
          ]),
          const SizedBox(height: 16),

          Align(alignment: Alignment.centerLeft, child: Text('Riwayat (${rw.length})',
            style: const TextStyle(fontSize: 13, color: ACCENT))),
          const SizedBox(height: 8),

          if (rw.isEmpty)
            const Padding(padding: EdgeInsets.all(24),
              child: Text('Belum ada transaksi', style: TextStyle(color: Colors.grey)))
          else ...rw.map((it) => it is PengRT ? _itemPeng(it) : _itemGaji(it as Gaji)),

          const SizedBox(height: 20),
        ]),
      )),
    );
  }

  Widget _itemPeng(PengRT t) {
    return Container(
      margin: const EdgeInsets.only(bottom: 6),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(color: CARD, borderRadius: BorderRadius.circular(10)),
      child: Row(children: [
        Icon(t.synced ? Icons.cloud_done : Icons.cloud_off,
          color: t.synced ? GREEN : YELLOW, size: 14),
        const SizedBox(width: 8),
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('${fmtTgl(t.tanggal)} • ${t.keterangan.isNotEmpty ? t.keterangan : t.kategori}',
            style: const TextStyle(color: Colors.white, fontSize: 13)),
          Text('${t.kategori} • Rp ${rp(t.nominal)}',
            style: const TextStyle(color: RED, fontSize: 12, fontWeight: FontWeight.bold)),
        ])),
        IconButton(icon: const Icon(Icons.edit, size: 18, color: ACCENT), onPressed: () => _editPeng(t)),
        IconButton(icon: const Icon(Icons.delete, size: 18, color: RED), onPressed: () => _hapusPeng(t)),
      ]),
    );
  }

  Widget _itemGaji(Gaji g) {
    return Container(
      margin: const EdgeInsets.only(bottom: 6),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(color: CARD, borderRadius: BorderRadius.circular(10)),
      child: Row(children: [
        Icon(g.synced ? Icons.cloud_done : Icons.cloud_off,
          color: g.synced ? GREEN : YELLOW, size: 14),
        const SizedBox(width: 8),
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('${fmtTgl(g.tanggal)} • ${g.keterangan.isNotEmpty ? g.keterangan : "Gaji"}',
            style: const TextStyle(color: Colors.white, fontSize: 13)),
          Text('Gaji • Rp ${rp(g.nominal)}',
            style: const TextStyle(color: GREEN, fontSize: 12, fontWeight: FontWeight.bold)),
        ])),
        IconButton(icon: const Icon(Icons.delete, size: 18, color: RED), onPressed: () => _hapusGaji(g)),
      ]),
    );
  }

  Future<void> _showUrlDialog() async {
    if (!mounted) return;
    await showDialog(context: context, builder: (c) => AlertDialog(
      title: const Text('URL Apps Script'),
      content: SingleChildScrollView(child: Text(SCRIPT_URL,
        style: const TextStyle(fontSize: 11))),
      actions: [
        TextButton(onPressed: () => Navigator.pop(c), child: const Text('TUTUP')),
      ]));
  }
}

// ===== DETAIL =====
class DetailPage extends StatelessWidget {
  final PeriodeFilter filter;
  final Map<String, Map<String, int>> cache;
  final List<Gaji> gaji;
  final List<PengRT> peng;
  final Map<int, int> saldoAwal;
  final int sisa;

  const DetailPage({
    super.key, required this.filter, required this.cache,
    required this.gaji, required this.peng, required this.saldoAwal, required this.sisa,
  });

  @override
  Widget build(BuildContext context) {
    int omsetToko = 0, lainLain = 0, gajiPeriode = 0;
    cache.forEach((tgl, v) {
      final t = DateTime.parse(tgl);
      if (t.isBefore(filter.mulai) || t.isAfter(filter.akhir)) return;
      omsetToko += v['toko'] ?? 0;
      lainLain += v['lain'] ?? 0;
    });
    for (final g in gaji) {
      final t = DateTime.parse(g.tanggal);
      if (t.isBefore(filter.mulai) || t.isAfter(filter.akhir)) continue;
      gajiPeriode += g.nominal;
    }
    final totalMasuk = omsetToko + lainLain + gajiPeriode;

    final perKat = <String, int>{};
    int totalKeluar = 0;
    for (final p in peng) {
      final t = DateTime.parse(p.tanggal);
      if (t.isBefore(filter.mulai) || t.isAfter(filter.akhir)) continue;
      perKat[p.kategori] = (perKat[p.kategori] ?? 0) + p.nominal;
      totalKeluar += p.nominal;
    }

    final cukup = sisa >= 0;

    return Scaffold(
      appBar: AppBar(title: const Text('Detail'), backgroundColor: BG),
      body: SafeArea(child: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Text(filter.label, style: const TextStyle(fontSize: 15, color: ACCENT)),
          const SizedBox(height: 16),

          Container(padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(color: CARD, borderRadius: BorderRadius.circular(12)),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              const Text('PEMASUKAN', style: TextStyle(color: GREEN, fontWeight: FontWeight.bold, fontSize: 12)),
              const SizedBox(height: 10),
              _row('Omset Toko', omsetToko),
              _row('Gaji', gajiPeriode),
              _row('Lain-lain', lainLain),
              const Divider(color: Colors.white24, height: 20),
              _row('Total Masuk', totalMasuk, bold: true, color: GREEN),
            ])),
          const SizedBox(height: 12),

          Container(padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(color: CARD, borderRadius: BorderRadius.circular(12)),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              const Text('PENGELUARAN', style: TextStyle(color: RED, fontWeight: FontWeight.bold, fontSize: 12)),
              const SizedBox(height: 10),
              if (perKat.isEmpty)
                const Text('Belum ada pengeluaran',
                  style: TextStyle(color: Colors.grey, fontSize: 12))
              else ...perKat.entries.map((e) => _row(e.key, e.value)),
              const Divider(color: Colors.white24, height: 20),
              _row('Total Keluar', totalKeluar, bold: true, color: RED),
            ])),
          const SizedBox(height: 12),

          Container(padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: (cukup ? GREEN : RED).withOpacity(0.1),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: cukup ? GREEN : RED),
            ),
            child: Column(children: [
              const Text('SISA', style: TextStyle(color: Colors.white70, fontSize: 12)),
              const SizedBox(height: 4),
              Text('Rp ${rp(sisa)}',
                style: TextStyle(color: cukup ? GREEN : RED,
                  fontWeight: FontWeight.bold, fontSize: 22)),
              if (!cukup) const Padding(
                padding: EdgeInsets.only(top: 6),
                child: Text('Tidak cukup', style: TextStyle(color: RED, fontSize: 12)),
              ),
            ])),
        ]),
      )),
    );
  }

  Widget _row(String label, int val, {bool bold = false, Color? color}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
        Text(label, style: const TextStyle(fontSize: 13, color: Colors.white70)),
        Text('Rp ${rp(val)}',
          style: TextStyle(fontSize: 13,
            color: color ?? Colors.white, fontWeight: bold ? FontWeight.bold : FontWeight.normal)),
      ]));
  }
}

// ===== TAMBAH/EDIT PENGELUARAN =====
class TambahPengPage extends StatefulWidget {
  final PengRT? existing;
  const TambahPengPage({super.key, this.existing});
  @override
  State<TambahPengPage> createState() => _TambahPengPageState();
}

class _TambahPengPageState extends State<TambahPengPage> {
  final _ket = TextEditingController();
  final _nom = TextEditingController();
  DateTime _tgl = DateTime.now();
  String _kat = 'Makanan';
  final _kats = ['Makanan', 'Non Makanan', 'Bahan Baku'];

  @override
  void initState() {
    super.initState();
    if (widget.existing != null) {
      _ket.text = widget.existing!.keterangan;
      _nom.text = widget.existing!.nominal.toString();
      _kat = _kats.contains(widget.existing!.kategori) ? widget.existing!.kategori : 'Makanan';
      try { _tgl = DateTime.parse(widget.existing!.tanggal); } catch (_) {}
    }
  }

  Future<void> _save() async {
    if (_nom.text.isEmpty || _ket.text.trim().isEmpty) {
      _snack('Keterangan & Nominal wajib'); return;
    }
    final n = int.tryParse(_nom.text);
    if (n == null || n <= 0) { _snack('Nominal tidak valid'); return; }

    final prefs = await SharedPreferences.getInstance();
    final list = prefs.getString('pengRT');
    final arr = list != null
      ? (jsonDecode(list) as List).map((e) => PengRT.fromJson(e)).toList()
      : <PengRT>[];

    if (widget.existing != null) {
      final i = arr.indexWhere((x) => x.id == widget.existing!.id);
      if (i >= 0) {
        arr[i]
          ..tanggal = tglStr(_tgl)..kategori = _kat
          ..keterangan = _ket.text.trim()..nominal = n..synced = false;
      }
    } else {
      arr.add(PengRT(
        id: nowStamp(), tanggal: tglStr(_tgl), jam: jamStr(DateTime.now()),
        kategori: _kat, keterangan: _ket.text.trim(), nominal: n,
      ));
    }
    await prefs.setString('pengRT', jsonEncode(arr.map((t) => t.toJson()).toList()));
    if (!mounted) return;
    Navigator.pop(context, true);
  }

  void _snack(String m) => ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(m)));

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.existing != null ? 'Edit Pengeluaran' : 'Tambah Pengeluaran'),
        backgroundColor: BG),
      body: SafeArea(child: ListView(padding: const EdgeInsets.all(16), children: [
        ListTile(
          title: const Text('Tanggal'),
          subtitle: Text(fmtTgl(tglStr(_tgl))),
          trailing: const Icon(Icons.calendar_today),
          onTap: () async {
            final p = await showDatePicker(context: context, initialDate: _tgl,
              firstDate: DateTime(2020), lastDate: DateTime(2100));
            if (p != null) setState(() => _tgl = p);
          }),
        const SizedBox(height: 8),
        DropdownButtonFormField<String>(
          value: _kat,
          decoration: const InputDecoration(labelText: 'Kategori', border: OutlineInputBorder()),
          items: _kats.map((e) => DropdownMenuItem(value: e, child: Text(e))).toList(),
          onChanged: (v) => setState(() => _kat = v!)),
        const SizedBox(height: 12),
        TextField(controller: _ket,
          decoration: const InputDecoration(labelText: 'Keterangan', border: OutlineInputBorder())),
        const SizedBox(height: 12),
        TextField(controller: _nom, keyboardType: TextInputType.number,
          decoration: const InputDecoration(labelText: 'Nominal', prefixText: 'Rp ',
            border: OutlineInputBorder())),
        const SizedBox(height: 24),
        FilledButton.icon(
          style: FilledButton.styleFrom(backgroundColor: GREEN, padding: const EdgeInsets.all(14)),
          onPressed: _save,
          icon: const Icon(Icons.save, color: Colors.black),
          label: const Text('SIMPAN', style: TextStyle(color: Colors.black, fontWeight: FontWeight.bold))),
      ])),
    );
  }
}

// ===== TAMBAH GAJI =====
class TambahGajiPage extends StatefulWidget {
  const TambahGajiPage({super.key});
  @override
  State<TambahGajiPage> createState() => _TambahGajiPageState();
}

class _TambahGajiPageState extends State<TambahGajiPage> {
  final _ket = TextEditingController();
  final _nom = TextEditingController();
  DateTime _tgl = DateTime.now();

  Future<void> _save() async {
    if (_nom.text.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Nominal wajib')));
      return;
    }
    final n = int.tryParse(_nom.text);
    if (n == null || n <= 0) return;
    final prefs = await SharedPreferences.getInstance();
    final list = prefs.getString('gaji');
    final arr = list != null
      ? (jsonDecode(list) as List).map((e) => Gaji.fromJson(e)).toList()
      : <Gaji>[];
    arr.add(Gaji(
      id: nowStamp(), tanggal: tglStr(_tgl), jam: jamStr(DateTime.now()),
      keterangan: _ket.text.trim(), nominal: n,
    ));
    await prefs.setString('gaji', jsonEncode(arr.map((t) => t.toJson()).toList()));
    if (!mounted) return;
    Navigator.pop(context, true);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Tambah Gaji'), backgroundColor: BG),
      body: SafeArea(child: ListView(padding: const EdgeInsets.all(16), children: [
        ListTile(
          title: const Text('Tanggal'),
          subtitle: Text(fmtTgl(tglStr(_tgl))),
          trailing: const Icon(Icons.calendar_today),
          onTap: () async {
            final p = await showDatePicker(context: context, initialDate: _tgl,
              firstDate: DateTime(2020), lastDate: DateTime(2100));
            if (p != null) setState(() => _tgl = p);
          }),
        const SizedBox(height: 12),
        TextField(controller: _ket,
          decoration: const InputDecoration(labelText: 'Keterangan', border: OutlineInputBorder())),
        const SizedBox(height: 12),
        TextField(controller: _nom, keyboardType: TextInputType.number,
          decoration: const InputDecoration(labelText: 'Nominal', prefixText: 'Rp ',
            border: OutlineInputBorder())),
        const SizedBox(height: 24),
        FilledButton.icon(
          style: FilledButton.styleFrom(backgroundColor: GREEN, padding: const EdgeInsets.all(14)),
          onPressed: _save,
          icon: const Icon(Icons.save, color: Colors.black),
          label: const Text('SIMPAN', style: TextStyle(color: Colors.black, fontWeight: FontWeight.bold))),
      ])),
    );
  }
}

// ===== SALDO AWAL =====
class SaldoAwalPage extends StatefulWidget {
  final Map<int, int> saldoAwal;
  final int sisaSekarang;
  const SaldoAwalPage({super.key, required this.saldoAwal, required this.sisaSekarang});
  @override
  State<SaldoAwalPage> createState() => _SaldoAwalPageState();
}

class _SaldoAwalPageState extends State<SaldoAwalPage> {
  late int _tahun;
  late TextEditingController _ctrl;

  @override
  void initState() {
    super.initState();
    _tahun = DateTime.now().year;
    _ctrl = TextEditingController(text: (widget.saldoAwal[_tahun] ?? 0).toString());
  }

  void _pilihTahun(int th) {
    setState(() {
      _tahun = th;
      _ctrl.text = (widget.saldoAwal[th] ?? 0).toString();
    });
  }

  Future<void> _simpan() async {
    final v = int.tryParse(_ctrl.text.trim());
    if (v == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Nominal tidak valid')));
      return;
    }
    final prefs = await SharedPreferences.getInstance();
    final sa = Map<int, int>.from(widget.saldoAwal);
    sa[_tahun] = v;
    await prefs.setString('saldoAwal',
      jsonEncode(sa.map((k, val) => MapEntry(k.toString(), val))));
    if (!mounted) return;
    Navigator.pop(context, true);
  }

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    final tahunList = List.generate(6, (i) => now.year - 3 + i);

    return Scaffold(
      appBar: AppBar(title: const Text('Atur Saldo Awal'), backgroundColor: BG),
      body: SafeArea(child: ListView(padding: const EdgeInsets.all(16), children: [
        const Text('Pilih Tahun:', style: TextStyle(fontSize: 13, color: Colors.white70)),
        const SizedBox(height: 8),
        Wrap(spacing: 8, runSpacing: 8, children: tahunList.map((th) {
          final sel = th == _tahun;
          return GestureDetector(
            onTap: () => _pilihTahun(th),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              decoration: BoxDecoration(
                color: sel ? ACCENT : CARD2,
                borderRadius: BorderRadius.circular(8)),
              child: Text('$th',
                style: TextStyle(color: sel ? Colors.black : Colors.white,
                  fontWeight: sel ? FontWeight.bold : FontWeight.normal))));
        }).toList()),
        const SizedBox(height: 20),
        Text('Saldo Awal $_tahun', style: const TextStyle(fontSize: 13, color: Colors.white70)),
        const SizedBox(height: 8),
        TextField(
          controller: _ctrl,
          keyboardType: const TextInputType.numberWithOptions(signed: true),
          decoration: const InputDecoration(
            prefixText: 'Rp ', border: OutlineInputBorder(),
            hintText: 'Bisa minus, misal -1000000')),
        const SizedBox(height: 8),
        const Text('Contoh: -1000000 (minus) atau 1000000 (plus)',
          style: TextStyle(fontSize: 11, color: Colors.white54)),
        const SizedBox(height: 20),
        FilledButton.icon(
          style: FilledButton.styleFrom(backgroundColor: GREEN, padding: const EdgeInsets.all(14)),
          onPressed: _simpan,
          icon: const Icon(Icons.save, color: Colors.black),
          label: const Text('SIMPAN', style: TextStyle(color: Colors.black, fontWeight: FontWeight.bold))),
      ])),
    );
  }
}

// ===== LIHAT SHEET =====
class LihatSheetPage extends StatefulWidget {
  const LihatSheetPage({super.key});
  @override
  State<LihatSheetPage> createState() => _LihatSheetPageState();
}

class _LihatSheetPageState extends State<LihatSheetPage> {
  bool loading = true;
  String? error;
  Map<String, List<Map<String, dynamic>>> dataPerTab = {};
  List<String> urutanTab = [];
  Set<String> expanded = {};

  @override
  void initState() { super.initState(); _load(); }

  Future<void> _load() async {
    setState(() { loading = true; error = null; });
    final rTabs = await apiGet({'action': 'list-tabs'});
    if (!mounted) return;
    if (rTabs['status'] != 'ok') {
      setState(() { loading = false; error = rTabs['message'] ?? 'Gagal'; }); return;
    }
    final tabs = (rTabs['tabs'] as List).map((e) => e.toString()).toList();
    final hasil = <String, List<Map<String, dynamic>>>{};
    for (final tab in tabs) {
      final r = await apiGet({'action': 'get-data-tab', 'tab': tab});
      hasil[tab] = r['status'] == 'ok'
        ? (r['data'] as List).cast<Map<String, dynamic>>() : [];
    }
    if (!mounted) return;
    setState(() { loading = false; urutanTab = tabs; dataPerTab = hasil; });
  }

  Future<void> _hapusRentang(String tab, List<Map<String, dynamic>> dataTab) async {
    if (dataTab.isEmpty) { _snack('Tidak ada data'); return; }
    final now = DateTime.now();
    final range = await showDateRangePicker(context: context,
      firstDate: DateTime(2020), lastDate: DateTime(2100),
      initialDateRange: DateTimeRange(start: now.subtract(const Duration(days: 7)), end: now),
      helpText: 'PILIH RENTANG HAPUS', saveText: 'PILIH', cancelText: 'BATAL',
      builder: (c, ch) => Theme(data: ThemeData.dark().copyWith(
        colorScheme: const ColorScheme.dark(primary: RED, onPrimary: Colors.black,
          surface: BG, onSurface: Colors.white)), child: ch!));
    if (range == null) return;
    final t1 = tglStr(range.start), t2 = tglStr(range.end);
    final akanHapus = dataTab.where((t) {
      final tgl = (t['tanggal'] ?? '').toString();
      return tgl.compareTo(t1) >= 0 && tgl.compareTo(t2) <= 0;
    }).toList();
    if (akanHapus.isEmpty) { _snack('Kosong di rentang ini'); return; }
    final konf = await showDialog<bool>(context: context, builder: (c) => AlertDialog(
      title: const Text('⚠ Konfirmasi Hapus'),
      content: Text('Tab: $tab\nPeriode: ${fmtTgl(t1)} s/d ${fmtTgl(t2)}\nJumlah: ${akanHapus.length}'),
      actions: [
        TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('BATAL')),
        ElevatedButton(style: ElevatedButton.styleFrom(backgroundColor: RED),
          onPressed: () => Navigator.pop(c, true),
          child: const Text('HAPUS', style: TextStyle(color: Colors.black)))]));
    if (konf != true) return;
    final r = await apiGet({'action': 'delete-range-tab', 'tab': tab, 'tgl1': t1, 'tgl2': t2});
    if (r['status'] == 'ok') { _snack('✓ ${r['hapus']} dihapus', ok: true); _load(); }
    else { _snack('Gagal: ${r['message']}', err: true); }
  }

  void _snack(String m, {bool ok = false, bool err = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(m),
      backgroundColor: ok ? const Color(0xFF2D4F2D) : err ? const Color(0xFF7F3F3F) : null));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Lihat Sheet'), backgroundColor: BG,
        actions: [IconButton(icon: const Icon(Icons.refresh), onPressed: loading ? null : _load)]),
      body: SafeArea(child: loading
        ? const Center(child: CircularProgressIndicator())
        : error != null
          ? Center(child: Padding(padding: const EdgeInsets.all(24), child: Column(
              mainAxisAlignment: MainAxisAlignment.center, children: [
                const Icon(Icons.error, color: RED, size: 64), const SizedBox(height: 16),
                Text(error!, textAlign: TextAlign.center), const SizedBox(height: 16),
                ElevatedButton(onPressed: _load, child: const Text('COBA LAGI'))])))
          : SingleChildScrollView(padding: const EdgeInsets.all(12), child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                if (urutanTab.isEmpty) const Padding(padding: EdgeInsets.all(24),
                  child: Text('Tidak ada tab', textAlign: TextAlign.center))
                else ...urutanTab.map((t) => _card(t, dataPerTab[t] ?? [])),
              ]))),
    );
  }

  Widget _card(String tab, List<Map<String, dynamic>> dataTab) {
    final total = dataTab.fold<int>(0, (s, t) => s + ((t['nominal'] ?? 0) as int));
    final kosong = dataTab.isEmpty;
    final isExp = expanded.contains(tab);
    final show = isExp ? dataTab : dataTab.take(10).toList();

    return Container(margin: const EdgeInsets.only(bottom: 16),
      decoration: BoxDecoration(color: CARD, borderRadius: BorderRadius.circular(12),
        border: Border.all(color: CARD2)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Container(padding: const EdgeInsets.all(12),
          decoration: const BoxDecoration(color: CARD2,
            borderRadius: BorderRadius.vertical(top: Radius.circular(12))),
          child: Row(children: [
            const Icon(Icons.table_chart, color: ACCENT, size: 20), const SizedBox(width: 8),
            Expanded(child: Text(tab, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold))),
            Text(kosong ? 'Kosong' : '${dataTab.length} data',
              style: TextStyle(fontSize: 12, color: kosong ? Colors.white38 : Colors.white70))])),
        Padding(padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
            const Text('Total:', style: TextStyle(fontSize: 12, color: Colors.white70)),
            Text('Rp ${rp(total)}', style: TextStyle(fontSize: 13,
              color: kosong ? Colors.white38 : GREEN, fontWeight: FontWeight.bold))])),
        if (!kosong) Padding(padding: const EdgeInsets.symmetric(horizontal: 12),
          child: Column(children: [
            ...show.map((t) => Padding(padding: const EdgeInsets.symmetric(vertical: 2),
              child: Row(children: [
                Text('#${t['id']}', style: const TextStyle(fontSize: 10, color: Colors.white38)),
                const SizedBox(width: 8),
                Expanded(child: Text('${t['tanggal']} ${t['jam']}',
                  style: const TextStyle(fontSize: 11, color: Colors.white70))),
                Text('Rp ${rp((t['nominal'] ?? 0) as int)}', style: const TextStyle(fontSize: 11))]))),
            if (dataTab.length > 10) TextButton(
              onPressed: () => setState(() {
                if (isExp) expanded.remove(tab); else expanded.add(tab);
              }),
              child: Text(isExp ? '▲ Sembunyikan' : '▼ Lihat semua (${dataTab.length})',
                style: const TextStyle(fontSize: 12, color: ACCENT))),
          ])),
        Padding(padding: const EdgeInsets.all(12), child: ElevatedButton.icon(
          style: ElevatedButton.styleFrom(
            backgroundColor: kosong ? CARD2 : RED, padding: const EdgeInsets.symmetric(vertical: 12)),
          onPressed: kosong ? null : () => _hapusRentang(tab, dataTab),
          icon: Icon(Icons.delete_sweep, color: kosong ? Colors.white38 : Colors.black),
          label: Text('HAPUS RENTANG TAB INI',
            style: TextStyle(color: kosong ? Colors.white38 : Colors.black,
              fontWeight: FontWeight.bold, fontSize: 12)))),
      ]));
  }
}
