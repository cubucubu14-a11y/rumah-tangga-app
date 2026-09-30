import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:intl/intl.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await initializeDateFormatting('id_ID', null);
  runApp(const RumahTanggaApp());
}

const String kDefaultApiUrl =
    'https://script.google.com/macros/s/AKfycbxcJu1lR7UhCmw1IzAjW9Dl-sU8aQb6kEyWP1RbNXnOWfm7-vRyPaRrL4bGDnbjM9s/exec';

// ============================================================
// APP ROOT
// ============================================================
class RumahTanggaApp extends StatelessWidget {
  const RumahTanggaApp({super.key});
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Kas Rumah',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.teal),
        useMaterial3: true,
      ),
      home: const HomePage(),
    );
  }
}

// ============================================================
// MODEL
// ============================================================
class Pengeluaran {
  final String id;
  final DateTime tanggal;
  final String kategori;
  final String deskripsi;
  final int nominal;

  Pengeluaran({
    required this.id,
    required this.tanggal,
    required this.kategori,
    required this.deskripsi,
    required this.nominal,
  });

  factory Pengeluaran.fromJson(Map<String, dynamic> j) => Pengeluaran(
        id: j['id']?.toString() ?? '',
        tanggal: DateTime.parse(j['tanggal']),
        kategori: j['kategori'] ?? '',
        deskripsi: j['deskripsi'] ?? '',
        nominal: (j['nominal'] as num?)?.toInt() ?? 0,
      );
}

class DashboardData {
  final int toko, lain, gaji, totalMasuk;
  final int totalKeluar;
  final int sisa;
  final bool cukup;

  DashboardData({
    required this.toko,
    required this.lain,
    required this.gaji,
    required this.totalMasuk,
    required this.totalKeluar,
    required this.sisa,
    required this.cukup,
  });

  factory DashboardData.fromJson(Map<String, dynamic> j) {
    final p = j['pemasukan'];
    final k = j['pengeluaran'];
    return DashboardData(
      toko: (p['toko'] as num).toInt(),
      lain: (p['lain'] as num).toInt(),
      gaji: (p['gaji'] as num).toInt(),
      totalMasuk: (p['total'] as num).toInt(),
      totalKeluar: (k['total'] as num).toInt(),
      sisa: (j['sisa'] as num).toInt(),
      cukup: j['cukup'] == true,
    );
  }
}

// ============================================================
// API SERVICE
// ============================================================
class ApiService {
  static Future<String> _getUrl() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString('api_url') ?? kDefaultApiUrl;
  }

  static Future<void> saveUrl(String url) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('api_url', url);
  }

  static Future<Map<String, dynamic>> _get(
      String action, Map<String, String> params) async {
    final base = await _getUrl();
    final q = {'action': action, ...params};
    final uri = Uri.parse(base).replace(queryParameters: q);
    final res = await http.get(uri);
    if (res.statusCode != 200) {
      throw Exception('HTTP ${res.statusCode}');
    }
    final body = jsonDecode(res.body) as Map<String, dynamic>;
    if (body['ok'] != true) {
      throw Exception(body['error'] ?? 'Gagal');
    }
    return body;
  }

  static Future<DashboardData> dashboard({String? bulan}) async {
    final body = await _get('dashboard', bulan != null ? {'bulan': bulan} : {});
    return DashboardData.fromJson(body['data']);
  }

  static Future<List<Pengeluaran>> listPengeluaran({String? bulan}) async {
    final body =
        await _get('list-pengeluaran', bulan != null ? {'bulan': bulan} : {});
    return (body['data'] as List)
        .map((e) => Pengeluaran.fromJson(e))
        .toList();
  }

  static Future<void> addPengeluaran({
    required DateTime tanggal,
    required String kategori,
    required String deskripsi,
    required int nominal,
  }) async {
    await _get('add-pengeluaran', {
      'tanggal': DateFormat('yyyy-MM-dd').format(tanggal),
      'kategori': kategori,
      'deskripsi': deskripsi,
      'nominal': nominal.toString(),
    });
  }

  static Future<void> deletePengeluaran(String id) async {
    await _get('delete-pengeluaran', {'id': id});
  }

  static Future<void> addGaji({
    required DateTime tanggal,
    required String keterangan,
    required int nominal,
  }) async {
    await _get('add-gaji', {
      'tanggal': DateFormat('yyyy-MM-dd').format(tanggal),
      'keterangan': keterangan,
      'nominal': nominal.toString(),
    });
  }
}

// ============================================================
// HOME (Dashboard + List)
// ============================================================
class HomePage extends StatefulWidget {
  const HomePage({super.key});
  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  DashboardData? _dash;
  List<Pengeluaran> _list = [];
  bool _loading = true;
  String? _error;
  DateTime _bulanAcuan = DateTime.now();

  final _rp = NumberFormat.currency(
      locale: 'id_ID', symbol: 'Rp ', decimalDigits: 0);

  @override
  void initState() {
    super.initState();
    _load();
  }

  String get _bulanStr => DateFormat('yyyy-MM').format(_bulanAcuan);

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final d = await ApiService.dashboard(bulan: _bulanStr);
      final l = await ApiService.listPengeluaran(bulan: _bulanStr);
      setState(() {
        _dash = d;
        _list = l;
        _loading = false;
      });
    } catch (e) {
      setState(() {
        _error = e.toString();
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Kas Rumah'),
        actions: [
          IconButton(
              icon: const Icon(Icons.settings), onPressed: _showSettings),
          IconButton(icon: const Icon(Icons.refresh), onPressed: _load),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? _buildError()
              : _buildContent(),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _menuTambah,
        icon: const Icon(Icons.add),
        label: const Text('Tambah'),
      ),
    );
  }

  Widget _buildError() => Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.error_outline, size: 64, color: Colors.red),
              const SizedBox(height: 16),
              Text(_error!, textAlign: TextAlign.center),
              const SizedBox(height: 16),
              ElevatedButton(
                  onPressed: _showSettings,
                  child: const Text('Atur URL')),
            ],
          ),
        ),
      );

  Widget _buildContent() {
    final d = _dash!;
    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _bulanPicker(),
          const SizedBox(height: 12),
          _cardRingkasan(d),
          const SizedBox(height: 16),
          Text('Riwayat', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 8),
          if (_list.isEmpty)
            const Padding(
              padding: EdgeInsets.all(32),
              child: Center(child: Text('Belum ada pengeluaran')),
            ),
          ..._list.map(_itemCard),
        ],
      ),
    );
  }

  Widget _bulanPicker() {
    return Row(
      children: [
        IconButton(
          icon: const Icon(Icons.chevron_left),
          onPressed: () {
            setState(() {
              _bulanAcuan = DateTime(_bulanAcuan.year, _bulanAcuan.month - 1);
            });
            _load();
          },
        ),
        Expanded(
          child: Center(
            child: Text(
              DateFormat('MMMM yyyy', 'id_ID').format(_bulanAcuan),
              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
            ),
          ),
        ),
        IconButton(
          icon: const Icon(Icons.chevron_right),
          onPressed: () {
            setState(() {
              _bulanAcuan = DateTime(_bulanAcuan.year, _bulanAcuan.month + 1);
            });
            _load();
          },
        ),
      ],
    );
  }

  Widget _cardRingkasan(DashboardData d) {
    final warnaSisa = d.cukup ? Colors.green : Colors.red;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('PEMASUKAN',
                style: TextStyle(fontWeight: FontWeight.bold)),
            const SizedBox(height: 6),
            _row('Omset Toko', _rp.format(d.toko)),
            _row('Gaji', _rp.format(d.gaji)),
            _row('Lain-lain', _rp.format(d.lain)),
            _divider(),
            _row('Total Masuk', _rp.format(d.totalMasuk), bold: true),
            const SizedBox(height: 12),
            const Text('PENGELUARAN RT',
                style: TextStyle(fontWeight: FontWeight.bold)),
            const SizedBox(height: 6),
            _row('Total Keluar', _rp.format(d.totalKeluar)),
            _divider(),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: warnaSisa.withOpacity(0.1),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: warnaSisa),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text('SISA',
                      style: TextStyle(
                          color: warnaSisa, fontWeight: FontWeight.bold)),
                  Text(
                    _rp.format(d.sisa),
                    style: TextStyle(
                        color: warnaSisa,
                        fontWeight: FontWeight.bold,
                        fontSize: 16),
                  ),
                ],
              ),
            ),
            if (!d.cukup)
              const Padding(
                padding: EdgeInsets.only(top: 8),
                child: Row(
                  children: [
                    Icon(Icons.warning, color: Colors.red, size: 16),
                    SizedBox(width: 4),
                    Text('Tidak cukup!',
                        style: TextStyle(color: Colors.red)),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _row(String label, String value, {bool bold = false}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label),
          Text(value,
              style: TextStyle(
                  fontWeight: bold ? FontWeight.bold : FontWeight.normal)),
        ],
      ),
    );
  }

  Widget _divider() => const Divider(height: 16);

  Widget _itemCard(Pengeluaran p) {
    return Card(
      margin: const EdgeInsets.symmetric(vertical: 4),
      child: ListTile(
        leading: CircleAvatar(
          child: Text(p.kategori.isNotEmpty ? p.kategori[0] : '?'),
        ),
        title: Text(p.deskripsi.isNotEmpty ? p.deskripsi : p.kategori),
        subtitle: Text(
            '${DateFormat('dd MMM', 'id_ID').format(p.tanggal)} • ${p.kategori}'),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('-${_rp.format(p.nominal)}',
                style: const TextStyle(
                    color: Colors.red, fontWeight: FontWeight.bold)),
            IconButton(
              icon: const Icon(Icons.delete_outline, size: 20),
              onPressed: () => _hapus(p),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _menuTambah() async {
    final pilihan = await showModalBottomSheet<String>(
      context: context,
      builder: (_) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.shopping_cart),
              title: const Text('Tambah Pengeluaran RT'),
              onTap: () => Navigator.pop(context, 'rt'),
            ),
            ListTile(
              leading: const Icon(Icons.attach_money),
              title: const Text('Tambah Gaji'),
              onTap: () => Navigator.pop(context, 'gaji'),
            ),
          ],
        ),
      ),
    );
    if (pilihan == 'rt') {
      final ok = await Navigator.push<bool>(
          context, MaterialPageRoute(builder: (_) => const TambahRTPage()));
      if (ok == true) _load();
    } else if (pilihan == 'gaji') {
      final ok = await Navigator.push<bool>(
          context, MaterialPageRoute(builder: (_) => const TambahGajiPage()));
      if (ok == true) _load();
    }
  }

  Future<void> _hapus(Pengeluaran p) async {
    final ya = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Hapus?'),
        content: Text('Hapus "${p.deskripsi}"?'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Batal')),
          ElevatedButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Hapus')),
        ],
      ),
    );
    if (ya == true) {
      try {
        await ApiService.deletePengeluaran(p.id);
        _load();
      } catch (e) {
        if (!mounted) return;
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Gagal: $e')));
      }
    }
  }

  Future<void> _showSettings() async {
    final prefs = await SharedPreferences.getInstance();
    final ctrl = TextEditingController(
        text: prefs.getString('api_url') ?? kDefaultApiUrl);
    if (!mounted) return;
    await showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('URL Apps Script'),
        content: TextField(
          controller: ctrl,
          maxLines: 3,
          decoration: const InputDecoration(hintText: 'https://...'),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Batal')),
          ElevatedButton(
            onPressed: () async {
              await ApiService.saveUrl(ctrl.text.trim());
              if (!mounted) return;
              Navigator.pop(context);
              _load();
            },
            child: const Text('Simpan'),
          ),
        ],
      ),
    );
  }
}

// ============================================================
// TAMBAH PENGELUARAN RT
// ============================================================
class TambahRTPage extends StatefulWidget {
  const TambahRTPage({super.key});
  @override
  State<TambahRTPage> createState() => _TambahRTPageState();
}

class _TambahRTPageState extends State<TambahRTPage> {
  final _desk = TextEditingController();
  final _nom = TextEditingController();
  DateTime _tgl = DateTime.now();
  String _kat = 'Makanan';
  bool _saving = false;

  final _kats = ['Makanan', 'Non Makanan', 'Bahan Baku'];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Tambah Pengeluaran')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          ListTile(
            title: const Text('Tanggal'),
            subtitle: Text(DateFormat('dd MMM yyyy', 'id_ID').format(_tgl)),
            trailing: const Icon(Icons.calendar_today),
            onTap: () async {
              final p = await showDatePicker(
                context: context,
                initialDate: _tgl,
                firstDate: DateTime(2020),
                lastDate: DateTime(2100),
              );
              if (p != null) setState(() => _tgl = p);
            },
          ),
          const SizedBox(height: 8),
          DropdownButtonFormField<String>(
            value: _kat,
            decoration: const InputDecoration(
                labelText: 'Kategori', border: OutlineInputBorder()),
            items: _kats
                .map((e) => DropdownMenuItem(value: e, child: Text(e)))
                .toList(),
            onChanged: (v) => setState(() => _kat = v!),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _desk,
            decoration: const InputDecoration(
                labelText: 'Deskripsi', border: OutlineInputBorder()),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _nom,
            keyboardType: TextInputType.number,
            decoration: const InputDecoration(
                labelText: 'Nominal',
                prefixText: 'Rp ',
                border: OutlineInputBorder()),
          ),
          const SizedBox(height: 24),
          FilledButton.icon(
            onPressed: _saving ? null : _save,
            icon: _saving
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2))
                : const Icon(Icons.save),
            label: Text(_saving ? 'Menyimpan...' : 'Simpan'),
          ),
        ],
      ),
    );
  }

  Future<void> _save() async {
    if (_nom.text.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Nominal wajib diisi')));
      return;
    }
    setState(() => _saving = true);
    try {
      await ApiService.addPengeluaran(
        tanggal: _tgl,
        kategori: _kat,
        deskripsi: _desk.text.trim(),
        nominal: int.parse(_nom.text.replaceAll('.', '')),
      );
      if (!mounted) return;
      Navigator.pop(context, true);
    } catch (e) {
      if (!mounted) return;
      setState(() => _saving = false);
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('Gagal: $e')));
    }
  }
}

// ============================================================
// TAMBAH GAJI
// ============================================================
class TambahGajiPage extends StatefulWidget {
  const TambahGajiPage({super.key});
  @override
  State<TambahGajiPage> createState() => _TambahGajiPageState();
}

class _TambahGajiPageState extends State<TambahGajiPage> {
  final _ket = TextEditingController();
  final _nom = TextEditingController();
  DateTime _tgl = DateTime.now();
  bool _saving = false;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Tambah Gaji')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          ListTile(
            title: const Text('Tanggal'),
            subtitle: Text(DateFormat('dd MMM yyyy', 'id_ID').format(_tgl)),
            trailing: const Icon(Icons.calendar_today),
            onTap: () async {
              final p = await showDatePicker(
                context: context,
                initialDate: _tgl,
                firstDate: DateTime(2020),
                lastDate: DateTime(2100),
              );
              if (p != null) setState(() => _tgl = p);
            },
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _ket,
            decoration: const InputDecoration(
                labelText: 'Keterangan', border: OutlineInputBorder()),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _nom,
            keyboardType: TextInputType.number,
            decoration: const InputDecoration(
                labelText: 'Nominal',
                prefixText: 'Rp ',
                border: OutlineInputBorder()),
          ),
          const SizedBox(height: 24),
          FilledButton.icon(
            onPressed: _saving ? null : _save,
            icon: _saving
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2))
                : const Icon(Icons.save),
            label: Text(_saving ? 'Menyimpan...' : 'Simpan'),
          ),
        ],
      ),
    );
  }

  Future<void> _save() async {
    if (_nom.text.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Nominal wajib diisi')));
      return;
    }
    setState(() => _saving = true);
    try {
      await ApiService.addGaji(
        tanggal: _tgl,
        keterangan: _ket.text.trim(),
        nominal: int.parse(_nom.text.replaceAll('.', '')),
      );
      if (!mounted) return;
      Navigator.pop(context, true);
    } catch (e) {
      if (!mounted) return;
      setState(() => _saving = false);
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('Gagal: $e')));
    }
  }
}
