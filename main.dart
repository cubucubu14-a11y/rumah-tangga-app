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

String tglStr(DateTime d) =>
    '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
String jamStr(DateTime d) =>
    '${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';
String rp(int n) => n.toString().replaceAllMapped(
    RegExp(r'(\d)(?=(\d{3})+(?!\d))'), (m) => '${m[1]}.');
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
    final r = await http.get(uri).timeout(const Duration(seconds: 20));
    if (r.statusCode == 200) return jsonDecode(r.body);
    return {'status': 'error', 'message': 'HTTP ${r.statusCode}'};
  } catch (e) {
    return {'status': 'error', 'message': e.toString()};
  }
}

// ============ MODELS ============
class PengRT {
  final int id;
  String tanggal, jam, kategori, keterangan;
  int nominal;
  bool synced;
  PengRT({required this.id, required this.tanggal, required this.jam,
    required this.kategori, required this.keterangan, required this.nominal,
    this.synced = false});
  Map<String, dynamic> toJson() => {'id': id, 'tanggal': tanggal, 'jam': jam,
    'kategori': kategori, 'keterangan': keterangan, 'nominal': nominal, 'synced': synced};
  factory PengRT.fromJson(Map m) => PengRT(
    id: m['id'], tanggal: m['tanggal'], jam: m['jam'],
    kategori: m['kategori'] ?? 'Lainnya', keterangan: m['keterangan'] ?? '',
    nominal: m['nominal'], synced: m['synced'] ?? false);
}

class Gaji {
  final int id;
  String tanggal, jam, keterangan;
  int nominal;
  bool synced;
  Gaji({required this.id, required this.tanggal, required this.jam,
    required this.keterangan, required this.nominal, this.synced = false});
  Map<String, dynamic> toJson() => {'id': id, 'tanggal': tanggal, 'jam': jam,
    'keterangan': keterangan, 'nominal': nominal, 'synced': synced};
  factory Gaji.fromJson(Map m) => Gaji(
    id: m['id'], tanggal: m['tanggal'], jam: m['jam'],
    keterangan: m['keterangan'] ?? '', nominal: m['nominal'], synced: m['synced'] ?? false);
}

// ============ HOME ============
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

  bool syncing = false;
  String progress = '';
  bool _adaHantu = false;
  bool _sedangCek = false;
  bool _offline = false;

  int omset = 0, lain = 0, totalGaji = 0, totalKeluar = 0;

  String filterPeriode = 'bulan';
  DateTime? customT1, customT2;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _load();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState s) {
    if (s == AppLifecycleState.resumed) { _loadDashboard(); _cekHantu(); }
  }

  Future<void> _load() async {
    final p = await SharedPreferences.getInstance();
    final pd = p.getString('pengRT');
    if (pd != null) peng = (jsonDecode(pd) as List).map((e) => PengRT.fromJson(e)).toList();
    final gd = p.getString('gaji');
    if (gd != null) gaji = (jsonDecode(gd) as List).map((e) => Gaji.fromJson(e)).toList();
    final pdd = p.getString('pengRTDel');
    if (pdd != null) pengDel = (jsonDecode(pdd) as List).map((e) => e as int).toList();
    final gdd = p.getString('gajiDel');
    if (gdd != null) gajiDel = (jsonDecode(gdd) as List).map((e) => e as int).toList();
    setState(() {});
    _loadDashboard();
    _sync(silent: true, retry: false);
    _cekHantu();
  }

  Future<void> _save() async {
    final p = await SharedPreferences.getInstance();
    await p.setString('pengRT', jsonEncode(peng.map((t) => t.toJson()).toList()));
    await p.setString('gaji', jsonEncode(gaji.map((t) => t.toJson()).toList()));
    await p.setString('pengRTDel', jsonEncode(pengDel));
    await p.setString('gajiDel', jsonEncode(gajiDel));
  }

  Future<void> _loadDashboard() async {
    final now = DateTime.now();
    final bulan = '${now.year}-${now.month.toString().padLeft(2, '0')}';
    final r = await apiGet({'action': 'get-dashboard', 'bulan': bulan});
    if (r['status'] == 'ok' && mounted) {
      setState(() {
        omset = (r['pemasukan']['toko'] as num).toInt();
        lain = (r['pemasukan']['lain'] as num).toInt();
        totalGaji = (r['pemasukan']['gaji'] as num).toInt();
        totalKeluar = (r['pengeluaran']['total'] as num).toInt();
      });
    }
  }

  Future<void> _cekHantu() async {
    if (_sedangCek || syncing) return;
    setState(() { _sedangCek = true; _offline = false; });
    final r = await apiGet({'action': 'cek-hantu', 'hari': '7'});
    if (!mounted) return;
    if (r['status'] == 'ok') {
      final idsRT = ((r['idsRT'] ?? []) as List).map((e) => (e['id'] as num).toInt()).toSet();
      final idsGJ = ((r['idsGJ'] ?? []) as List).map((e) => (e['id'] as num).toInt()).toSet();
      final hpRT = peng.map((t) => t.id).toSet();
      final hpGJ = gaji.map((t) => t.id).toSet();
      final hRT = idsRT.where((id) => !hpRT.contains(id)).toList();
      final hGJ = idsGJ.where((id) => !hpGJ.contains(id)).toList();
      setState(() { _adaHantu = hRT.isNotEmpty || hGJ.isNotEmpty; _sedangCek = false; });
    } else {
      setState(() { _sedangCek = false; _offline = true; });
    }
  }

  Color get _syncColor {
    if (_sedangCek || syncing) return ACCENT;
    if (_offline) return Colors.grey;
    if (_adaHantu) return YELLOW;
    return PURPLE;
  }

  bool _inPeriode(String tgl) {
    final now = DateTime.now();
    final today = tglStr(now);
    switch (filterPeriode) {
      case 'hari': return tgl == today;
      case 'minggu':
        final start = now.subtract(Duration(days: now.weekday - 1));
        return tgl.compareTo(tglStr(start)) >= 0 && tgl.compareTo(today) <= 0;
      case 'bulan':
        return tgl.startsWith('${now.year}-${now.month.toString().padLeft(2, '0')}');
      case 'custom':
        if (customT1 == null || customT2 == null) return false;
        return tgl.compareTo(tglStr(customT1!)) >= 0 && tgl.compareTo(tglStr(customT2!)) <= 0;
    }
    return true;
  }

  List<PengRT> get _pf => peng.where((p) => _inPeriode(p.tanggal)).toList().reversed.toList();
  List<Gaji> get _gf => gaji.where((g) => _inPeriode(g.tanggal)).toList().reversed.toList();
  int get _totalPeng => _pf.fold(0, (s, t) => s + t.nominal);

  int get belumSync =>
    peng.where((t) => !t.synced).length + gaji.where((t) => !t.synced).length +
    pengDel.length + gajiDel.length;

  Future<Map<String, dynamic>> _upPeng(PengRT t) => apiGet({
    'action': 'upsert-pengeluaran-rt', 'id': t.id.toString(), 'tanggal': t.tanggal,
    'jam': t.jam, 'kategori': t.kategori, 'keterangan': t.keterangan,
    'nominal': t.nominal.toString()});
  Future<Map<String, dynamic>> _delPeng(int id) =>
    apiGet({'action': 'delete-pengeluaran-rt', 'id': id.toString()});
  Future<Map<String, dynamic>> _upGaji(Gaji t) => apiGet({
    'action': 'upsert-gaji', 'id': t.id.toString(), 'tanggal': t.tanggal,
    'jam': t.jam, 'keterangan': t.keterangan, 'nominal': t.nominal.toString()});
  Future<Map<String, dynamic>> _delGaji(int id) =>
    apiGet({'action': 'delete-gaji', 'id': id.toString()});

  Future<void> _sync({bool silent = false, bool retry = true}) async {
    if (syncing) return;
    int att = 0;
    while (true) {
      att++;
      final pn = peng.where((t) => !t.synced).toList();
      final gn = gaji.where((t) => !t.synced).toList();
      final pd = List<int>.from(pengDel);
      final gd = List<int>.from(gajiDel);
      if (pn.isEmpty && gn.isEmpty && pd.isEmpty && gd.isEmpty) {
        if (mounted && !silent && att == 1) _snack('Semua data sudah tersinkron');
        return;
      }
      setState(() { syncing = true; progress = 'Memulai...'; });
      int ke = 0; final total = pn.length + gn.length + pd.length + gd.length;
      int gagal = 0; String err = '';
      final sisaP = <int>[]; final sisaG = <int>[];
      for (final id in pd) {
        ke++; if (mounted) setState(() => progress = 'Hapus RT $ke/$total');
        final r = await _delPeng(id);
        if (r['status'] != 'ok') { sisaP.add(id); gagal++; if (err.isEmpty) err = r['message'] ?? '?'; }
        await Future.delayed(const Duration(milliseconds: 80));
      }
      for (final id in gd) {
        ke++; if (mounted) setState(() => progress = 'Hapus Gaji $ke/$total');
        final r = await _delGaji(id);
        if (r['status'] != 'ok') { sisaG.add(id); gagal++; if (err.isEmpty) err = r['message'] ?? '?'; }
        await Future.delayed(const Duration(milliseconds: 80));
      }
      for (final t in pn) {
        ke++; if (mounted) setState(() => progress = 'Kirim RT $ke/$total');
        final r = await _upPeng(t);
        if (r['status'] == 'ok') { t.synced = true; } else { gagal++; if (err.isEmpty) err = r['message'] ?? '?'; }
        await Future.delayed(const Duration(milliseconds: 80));
      }
      for (final t in gn) {
        ke++; if (mounted) setState(() => progress = 'Kirim Gaji $ke/$total');
        final r = await _upGaji(t);
        if (r['status'] == 'ok') { t.synced = true; } else { gagal++; if (err.isEmpty) err = r['message'] ?? '?'; }
        await Future.delayed(const Duration(milliseconds: 80));
      }
      pengDel = sisaP; gajiDel = sisaG;
      await _save();
      if (gagal == 0) {
        if (mounted) { setState(() { syncing = false; progress = ''; });
          if (!silent) _snack('✓ Sync berhasil', ok: true); }
        _cekHantu();
        return;
      }
      if (!retry || att >= 5) {
        if (mounted) { setState(() { syncing = false; progress = ''; });
          _snack('Gagal $att percobaan: $err', err: true); }
        return;
      }
      if (mounted) setState(() => progress = 'Retry...');
      await Future.delayed(const Duration(seconds: 3));
    }
  }

  Future<void> _resync() async {
    setState(() { syncing = true; progress = 'Cek hantu...'; });
    final r = await apiGet({'action': 'cek-hantu', 'hari': '7'});
    if (r['status'] != 'ok') {
      setState(() { syncing = false; progress = ''; });
      _snack('Gagal: ${r['message']}', err: true); return;
    }
    final hpRT = peng.map((t) => t.id).toSet();
    final hpGJ = gaji.map((t) => t.id).toSet();
    final hRT = <int>[], hGJ = <int>[];
    for (final item in (r['idsRT'] as List)) {
      final id = (item['id'] as num).toInt();
      final tgl = (item['tanggal'] ?? '').toString();
      final today = tglStr(DateTime.now());
      if (!hpRT.contains(id) && tgl == today) hRT.add(id);
    }
    for (final item in (r['idsGJ'] as List)) {
      final id = (item['id'] as num).toInt();
      final tgl = (item['tanggal'] ?? '').toString();
      final today = tglStr(DateTime.now());
      if (!hpGJ.contains(id) && tgl == today) hGJ.add(id);
    }
    int ke = 0; final total = hRT.length + hGJ.length;
    for (final id in hRT) {
      ke++; if (mounted) setState(() => progress = 'Hapus RT $ke/$total');
      await _delPeng(id); await Future.delayed(const Duration(milliseconds: 60));
    }
    for (final id in hGJ) {
      ke++; if (mounted) setState(() => progress = 'Hapus Gaji $ke/$total');
      await _delGaji(id); await Future.delayed(const Duration(milliseconds: 60));
    }
    setState(() { syncing = false; progress = ''; });
    await _sync(silent: true, retry: true);
    await _loadDashboard();
    await _cekHantu();
    _snack(total > 0 ? '✓ $total hantu dihapus' : '✓ Sync selesai', ok: true);
  }

  void _snack(String m, {bool ok = false, bool err = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(m), duration: const Duration(seconds: 4),
      backgroundColor: ok ? const Color(0xFF2D4F2D) : err ? const Color(0xFF7F3F3F) : null));
  }

  Future<void> _tambahPeng() async {
    final p = await Navigator.push<bool>(context,
      MaterialPageRoute(builder: (_) => const TambahPengPage()));
    if (p == true) _loadDashboard();
  }

  Future<void> _tambahGaji() async {
    final p = await Navigator.push<bool>(context,
      MaterialPageRoute(builder: (_) => const TambahGajiPage()));
    if (p == true) _loadDashboard();
  }

  Future<void> _editPeng(PengRT t) async {
    final hasil = await Navigator.push<bool>(context,
      MaterialPageRoute(builder: (_) => TambahPengPage(existing: t)));
    if (hasil == true) _loadDashboard();
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
      setState(() { peng.removeWhere((x) => x.id == t.id); pengDel.add(t.id); });
      await _save();
      _sync(silent: true, retry: true);
      _loadDashboard();
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
      setState(() { gaji.removeWhere((x) => x.id == g.id); gajiDel.add(g.id); });
      await _save();
      _sync(silent: true, retry: true);
      _loadDashboard();
    }
  }

  Future<void> _pilihFilter() async {
    final p = await showDialog<String>(context: context, builder: (c) => SimpleDialog(
      title: const Text('Filter Periode'),
      children: [
        SimpleDialogOption(onPressed: () => Navigator.pop(c, 'hari'), child: const Text('Hari Ini')),
        SimpleDialogOption(onPressed: () => Navigator.pop(c, 'minggu'), child: const Text('Minggu Ini')),
        SimpleDialogOption(onPressed: () => Navigator.pop(c, 'bulan'), child: const Text('Bulan Ini')),
        SimpleDialogOption(onPressed: () => Navigator.pop(c, 'custom'), child: const Text('Pilih Tanggal...')),
      ]));
    if (p == null) return;
    if (p == 'custom') {
      final r = await showDateRangePicker(context: context,
        firstDate: DateTime(2020), lastDate: DateTime(2100),
        helpText: 'PILIH RENTANG', saveText: 'PILIH', cancelText: 'BATAL',
        builder: (c, ch) => Theme(data: ThemeData.dark().copyWith(
          colorScheme: const ColorScheme.dark(primary: ACCENT, onPrimary: Colors.black,
            surface: BG, onSurface: Colors.white)), child: ch!));
      if (r == null) return;
      setState(() { filterPeriode = 'custom'; customT1 = r.start; customT2 = r.end; });
    } else {
      setState(() => filterPeriode = p);
    }
  }

  String get _filterLabel {
    switch (filterPeriode) {
      case 'hari': return 'Hari Ini';
      case 'minggu': return 'Minggu Ini';
      case 'bulan': return 'Bulan Ini';
      case 'custom':
        if (customT1 != null && customT2 != null)
          return '${fmtTgl(tglStr(customT1!))} - ${fmtTgl(tglStr(customT2!))}';
        return 'Pilih Tanggal';
    }
    return 'Bulan Ini';
  }

  Future<void> _lihatSheet() async {
    await Navigator.push(context, MaterialPageRoute(builder: (_) => const LihatSheetPage()));
    _loadDashboard();
    _cekHantu();
  }

  @override
  Widget build(BuildContext context) {
    final pf = _pf;
    final totalMasuk = omset + lain + totalGaji;
    final sisa = totalMasuk - totalKeluar;
    final cukup = sisa >= 0;

    return Scaffold(
      body: SafeArea(child: SingleChildScrollView(
        padding: const EdgeInsets.all(12),
        child: Column(children: [
          Row(mainAxisAlignment: MainAxisAlignment.center, children: [
            const Text('KAS RUMAH', style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold)),
            const SizedBox(width: 6),
            PopupMenuButton<String>(
              icon: const Icon(Icons.more_vert, color: Colors.white70, size: 20),
              onSelected: (v) { if (v == 'lihat') _lihatSheet(); },
              itemBuilder: (c) => const [
                PopupMenuItem(value: 'lihat', child: Row(children: [
                  Icon(Icons.table_chart, color: GREEN, size: 18),
                  SizedBox(width: 8), Text('Lihat Sheet')])),
              ]),
          ]),
          const SizedBox(height: 12),

          // ===== CARD DASHBOARD =====
          Container(
            padding: const EdgeInsets.all(14), width: double.infinity,
            decoration: BoxDecoration(color: CARD, borderRadius: BorderRadius.circular(12)),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              const Text('PEMASUKAN', style: TextStyle(color: GREEN, fontWeight: FontWeight.bold, fontSize: 12)),
              const SizedBox(height: 6),
              _row('Omset Toko', omset),
              _row('Gaji', totalGaji),
              _row('Lain-lain', lain),
              const Divider(color: Colors.white24, height: 16),
              _row('Total Masuk', totalMasuk, bold: true, color: GREEN),
              const SizedBox(height: 12),
              const Text('PENGELUARAN RT', style: TextStyle(color: RED, fontWeight: FontWeight.bold, fontSize: 12)),
              const SizedBox(height: 6),
              _row('Total Keluar', totalKeluar, color: RED),
              const SizedBox(height: 10),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: (cukup ? GREEN : RED).withOpacity(0.1),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: cukup ? GREEN : RED),
                ),
                child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                  Text('SISA', style: TextStyle(color: cukup ? GREEN : RED, fontWeight: FontWeight.bold)),
                  Text('Rp ${rp(sisa)}', style: TextStyle(color: cukup ? GREEN : RED,
                    fontWeight: FontWeight.bold, fontSize: 16)),
                ]),
              ),
              if (!cukup) const Padding(
                padding: EdgeInsets.only(top: 8),
                child: Row(children: [
                  Icon(Icons.warning, color: RED, size: 16), SizedBox(width: 4),
                  Text('Tidak cukup!', style: TextStyle(color: RED)),
                ]),
              ),
            ]),
          ),
          const SizedBox(height: 10),

          // ===== PENGELUARAN SUMMARY =====
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(color: CARD, borderRadius: BorderRadius.circular(12)),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                const Text('📉 PENGELUARAN', style: TextStyle(color: RED, fontWeight: FontWeight.bold)),
                GestureDetector(onTap: _pilihFilter, child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(color: CARD2, borderRadius: BorderRadius.circular(8)),
                  child: Row(children: [
                    Text(_filterLabel, style: const TextStyle(fontSize: 12, color: ACCENT)),
                    const Icon(Icons.arrow_drop_down, size: 18, color: ACCENT)]))),
              ]),
              const SizedBox(height: 6),
              Text('Rp ${rp(_totalPeng)}', style: const TextStyle(
                fontSize: 20, color: Colors.white, fontWeight: FontWeight.bold)),
            ]),
          ),
          const SizedBox(height: 10),

          // ===== TOMBOL TAMBAH =====
          Row(children: [
            Expanded(flex: 70, child: ElevatedButton.icon(
              style: ElevatedButton.styleFrom(backgroundColor: RED, padding: const EdgeInsets.symmetric(vertical: 14)),
              onPressed: _tambahPeng,
              icon: const Icon(Icons.add, color: Colors.black),
              label: const Text('PENGELUARAN RT', style: TextStyle(color: Colors.black, fontSize: 12, fontWeight: FontWeight.bold)))),
            const SizedBox(width: 6),
            Expanded(flex: 30, child: ElevatedButton(
              style: ElevatedButton.styleFrom(backgroundColor: ACCENT, padding: const EdgeInsets.symmetric(vertical: 14)),
              onPressed: _tambahGaji,
              child: const Text('➕ Gaji', style: TextStyle(color: Colors.black, fontSize: 12, fontWeight: FontWeight.bold)))),
          ]),
          const SizedBox(height: 10),

          // ===== SYNC STATUS =====
          Row(mainAxisAlignment: MainAxisAlignment.center, children: [
            Icon(belumSync == 0 ? Icons.cloud_done : Icons.cloud_off,
              color: _sedangCek ? ACCENT : belumSync == 0 ? GREEN : YELLOW, size: 16),
            const SizedBox(width: 4),
            Flexible(child: Text(syncing && progress.isNotEmpty ? progress
                : belumSync == 0 ? 'Semua tersinkron' : '$belumSync data pending',
              style: TextStyle(fontSize: 12, color: _sedangCek ? ACCENT : belumSync == 0 ? GREEN : YELLOW),
              overflow: TextOverflow.ellipsis)),
            const SizedBox(width: 8),
            GestureDetector(
              onTap: () { if (!syncing) _resync(); },
              child: Container(padding: const EdgeInsets.all(6),
                decoration: BoxDecoration(color: _syncColor.withOpacity(0.2), borderRadius: BorderRadius.circular(24)),
                child: Icon(syncing ? Icons.sync : Icons.sync, size: 32, color: _syncColor))),
          ]),

          if (belumSync > 0) Padding(
            padding: const EdgeInsets.only(top: 8),
            child: SizedBox(width: double.infinity, child: ElevatedButton.icon(
              style: ElevatedButton.styleFrom(backgroundColor: YELLOW, padding: const EdgeInsets.all(10)),
              onPressed: syncing ? null : () => _sync(retry: true),
              icon: syncing ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.black))
                  : const Icon(Icons.sync, color: Colors.black),
              label: Text(syncing ? 'SYNC $progress' : 'SYNC SEKARANG ($belumSync)',
                style: const TextStyle(color: Colors.black, fontWeight: FontWeight.bold))))),

          const SizedBox(height: 16),

          // ===== DAFTAR PENGELUARAN =====
          Align(alignment: Alignment.centerLeft, child: Text('DAFTAR PENGELUARAN (${pf.length})',
            style: const TextStyle(fontSize: 13, color: ACCENT))),
          const SizedBox(height: 8),
          if (pf.isEmpty)
            const Padding(padding: EdgeInsets.all(12), child: Text('Belum ada pengeluaran', style: TextStyle(color: Colors.grey)))
          else ...pf.map((t) => Container(
            margin: const EdgeInsets.only(bottom: 6), padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            decoration: BoxDecoration(color: CARD, borderRadius: BorderRadius.circular(8)),
            child: Row(children: [
              Icon(t.synced ? Icons.cloud_done : Icons.cloud_off,
                color: t.synced ? GREEN : YELLOW, size: 14),
              const SizedBox(width: 6),
              Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('${fmtTgl(t.tanggal)} - ${t.keterangan}', style: const TextStyle(color: Colors.white, fontSize: 13)),
                Text('${t.kategori} • Rp ${rp(t.nominal)}',
                  style: const TextStyle(color: RED, fontSize: 12, fontWeight: FontWeight.bold))])),
              IconButton(icon: const Icon(Icons.edit, size: 20, color: ACCENT), onPressed: () => _editPeng(t)),
              IconButton(icon: const Icon(Icons.delete, size: 20, color: RED), onPressed: () => _hapusPeng(t))]))),

          const SizedBox(height: 16),

          // ===== DAFTAR GAJI =====
          Align(alignment: Alignment.centerLeft, child: Text('DAFTAR GAJI (${_gf.length})',
            style: const TextStyle(fontSize: 13, color: ACCENT))),
          const SizedBox(height: 8),
          if (_gf.isEmpty)
            const Padding(padding: EdgeInsets.all(12), child: Text('Belum ada gaji', style: TextStyle(color: Colors.grey)))
          else ..._gf.map((g) => Container(
            margin: const EdgeInsets.only(bottom: 6), padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            decoration: BoxDecoration(color: CARD, borderRadius: BorderRadius.circular(8)),
            child: Row(children: [
              Icon(g.synced ? Icons.cloud_done : Icons.cloud_off,
                color: g.synced ? GREEN : YELLOW, size: 14),
              const SizedBox(width: 6),
              Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('${fmtTgl(g.tanggal)} - ${g.keterangan}', style: const TextStyle(color: Colors.white, fontSize: 13)),
                Text('Rp ${rp(g.nominal)}', style: const TextStyle(color: GREEN, fontSize: 12, fontWeight: FontWeight.bold))])),
              IconButton(icon: const Icon(Icons.delete, size: 20, color: RED), onPressed: () => _hapusGaji(g))]))),

          const SizedBox(height: 20),
        ]),
      )),
    );
  }

  Widget _row(String label, int val, {bool bold = false, Color? color}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
        Text(label, style: const TextStyle(fontSize: 13, color: Colors.white70)),
        Text('Rp ${rp(val)}', style: TextStyle(fontSize: 13,
          color: color ?? Colors.white, fontWeight: bold ? FontWeight.bold : FontWeight.normal)),
      ]));
  }
}

// ============ TAMBAH PENGELUARAN ============
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
  bool _saving = false;
  final _kats = ['Makanan', 'Non Makanan', 'Bahan Baku'];

  @override
  void initState() {
    super.initState();
    if (widget.existing != null) {
      _ket.text = widget.existing!.keterangan;
      _nom.text = widget.existing!.nominal.toString();
      _kat = widget.existing!.kategori;
      try { _tgl = DateTime.parse(widget.existing!.tanggal); } catch (_) {}
    }
  }

  Future<void> _save() async {
    if (_nom.text.isEmpty || _ket.text.trim().isEmpty) {
      _snack('Keterangan & Nominal wajib'); return;
    }
    final n = int.tryParse(_nom.text);
    if (n == null || n <= 0) { _snack('Nominal tidak valid'); return; }
    setState(() => _saving = true);
    final prefs = await SharedPreferences.getInstance();
    final list = prefs.getString('pengRT');
    final arr = list != null ? (jsonDecode(list) as List).map((e) => PengRT.fromJson(e)).toList() : <PengRT>[];

    if (widget.existing != null) {
      final i = arr.indexWhere((x) => x.id == widget.existing!.id);
      if (i >= 0) {
        arr[i]..tanggal = tglStr(_tgl)..kategori = _kat
          ..keterangan = _ket.text.trim()..nominal = n..synced = false;
      }
    } else {
      arr.add(PengRT(id: nowStamp(), tanggal: tglStr(_tgl), jam: jamStr(DateTime.now()),
        kategori: _kat, keterangan: _ket.text.trim(), nominal: n));
    }
    await prefs.setString('pengRT', jsonEncode(arr.map((t) => t.toJson()).toList()));
    if (!mounted) return;
    Navigator.pop(context, true);
  }

  void _snack(String m) => ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(m)));

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(widget.existing != null ? 'Edit Pengeluaran' : 'Tambah Pengeluaran'),
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
          decoration: const InputDecoration(labelText: 'Nominal', prefixText: 'Rp ', border: OutlineInputBorder())),
        const SizedBox(height: 24),
        FilledButton.icon(
          style: FilledButton.styleFrom(backgroundColor: GREEN, padding: const EdgeInsets.all(14)),
          onPressed: _saving ? null : _save,
          icon: _saving ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
              : const Icon(Icons.save, color: Colors.black),
          label: Text(_saving ? 'Menyimpan...' : 'SIMPAN',
            style: const TextStyle(color: Colors.black, fontWeight: FontWeight.bold))),
      ])),
    );
  }
}

// ============ TAMBAH GAJI ============
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
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Nominal wajib'))); return;
    }
    final n = int.tryParse(_nom.text);
    if (n == null || n <= 0) return;
    final prefs = await SharedPreferences.getInstance();
    final list = prefs.getString('gaji');
    final arr = list != null ? (jsonDecode(list) as List).map((e) => Gaji.fromJson(e)).toList() : <Gaji>[];
    arr.add(Gaji(id: nowStamp(), tanggal: tglStr(_tgl), jam: jamStr(DateTime.now()),
      keterangan: _ket.text.trim(), nominal: n));
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
          decoration: const InputDecoration(labelText: 'Nominal', prefixText: 'Rp ', border: OutlineInputBorder())),
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

// ============ LIHAT SHEET ============
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
      hasil[tab] = r['status'] == 'ok' ? (r['data'] as List).cast<Map<String, dynamic>>() : [];
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
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(m),
      backgroundColor: ok ? const Color(0xFF2D4F2D) : err ? const Color(0xFF7F3F3F) : null));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Lihat Sheet'), backgroundColor: BG,
        actions: [IconButton(icon: const Icon(Icons.refresh), onPressed: loading ? null : _load)]),
      body: SafeArea(child: loading ? const Center(child: CircularProgressIndicator())
        : error != null ? Center(child: Padding(padding: const EdgeInsets.all(24), child: Column(
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
            Expanded(child: Text(tab, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold))),
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
                Text('Rp ${rp((t['nominal'] ?? 0) as int)}',
                  style: const TextStyle(fontSize: 11))]))),
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
