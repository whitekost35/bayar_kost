import 'package:flutter/material.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/rendering.dart';
import 'dart:ui' as ui;
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:workmanager/workmanager.dart' as wm;
import 'package:timezone/data/latest_all.dart' as tz;
import 'package:timezone/timezone.dart' as tz;
import 'web_download.dart';

const String supabaseUrl = 'https://tdauvovlbrxlkofenjfu.supabase.co';
const String supabasePublishableKey = 'sb_publishable_tVudAb-eRFpLPBGoPJpAHg_eXG9rM9Y';

// Identifikasi tugas Workmanager
const String checkPaymentTask = "checkPaymentTask";

@pragma('vm:entry-point')
void callbackDispatcher() {
  wm.Workmanager().executeTask((task, inputData) async {
    tz.initializeTimeZones();
    WidgetsFlutterBinding.ensureInitialized();

    // Inisialisasi Supabase di background
    if (supabaseUrl != 'YOUR_SUPABASE_URL' && supabasePublishableKey != 'YOUR_SUPABASE_PUBLISHABLE_KEY') {
      try {
        await Supabase.initialize(
          url: supabaseUrl,
          anonKey: supabasePublishableKey,
        );
      } catch (e) {
        debugPrint('Gagal inisialisasi Supabase di background: $e');
      }
    }

    final prefs = await SharedPreferences.getInstance();
    
    // Inisialisasi data kost untuk pengecekan
    // Kita perlu data yang sama dengan yang ada di HomeScreen
    final whiteKostItems = _generateLocalWhiteKostDataStatic();
    final whiteKost = KostData(
      name: 'WHITE KOST 35',
      logoText: 'WK',
      themeColor: Colors.blue.shade50,
      buttonColor: Colors.black,
      buttonTextColor: Colors.white,
      tableItems: whiteKostItems,
      isSupabaseConnected: true, // Asumsi terkoneksi untuk pengecekan live
    );

    final myKost = KostData(
      name: 'MYKOST 179',
      logoText: 'MK',
      themeColor: const Color(0xFFFDF5E6),
      buttonColor: const Color(0xFFD7CCC8),
      buttonTextColor: const Color(0xFF4E342E),
      tableItems: [
        'Lantai A',
        for (int i = 1; i <= 10; i++) Penghuni(noKamar: 'A$i'),
        'Lantai B',
        for (int i = 1; i <= 10; i++) Penghuni(noKamar: 'B$i'),
      ],
      isSupabaseConnected: false,
    );

    int hariIniCount = 0;
    int terlambatCount = 0;

    // Ambil data dari kedua kost
    final whiteData = await fetchRoomsData(whiteKost, prefs);
    final myData = await fetchRoomsData(myKost, prefs);

    void processItems(List<dynamic> items) {
      for (var item in items) {
        if (item is Penghuni) {
          if (item.status.contains('Hari ini')) {
            hariIniCount++;
          } else if (item.status.contains('Terlambat')) {
            terlambatCount++;
          }
        }
      }
    }

    processItems(whiteData);
    processItems(myData);

    if (hariIniCount > 0 || terlambatCount > 0) {
      await _showNotification(hariIniCount, terlambatCount);
    }

    return Future.value(true);
  });
}

// Versi static untuk dipanggil di background dispatcher
List<dynamic> _generateLocalWhiteKostDataStatic() {
  final items = <dynamic>[];
  final dataLantai = {
    'D9': Penghuni(noKamar: 'D9', nama: 'Kenny Aditya Arizona', jatuhTempo: '29', status: 'Terlambat', tanggalBayar: '-', catatan: 'Sudah bayar 1.500.000'),
    '404': Penghuni(noKamar: '404', nama: 'Teddy Irlan Wibowo', jatuhTempo: '15', status: 'Terlambat\n7 Hari', tanggalBayar: '-', catatan: '-'),
  };

  for (var floor in ['A', 'B', 'C', 'D']) {
    items.add('Lantai $floor');
    for (int i = 1; i <= 11; i++) {
      String key = '$floor$i';
      items.add(dataLantai[key] ?? Penghuni(noKamar: key, status: 'Kosong'));
    }
  }
  for (int f = 1; f <= 4; f++) {
    items.add('Lantai $f');
    for (int i = 1; i <= 6; i++) {
      String key = '${f}0$i';
      items.add(dataLantai[key] ?? Penghuni(noKamar: key, status: 'Kosong'));
    }
  }
  return items;
}

Future<void> _showNotification(int hariIni, int terlambat) async {
  final FlutterLocalNotificationsPlugin flutterLocalNotificationsPlugin = FlutterLocalNotificationsPlugin();
  
  const AndroidInitializationSettings initializationSettingsAndroid = AndroidInitializationSettings('@mipmap/ic_launcher');
  const InitializationSettings initializationSettings = InitializationSettings(android: initializationSettingsAndroid);
  await flutterLocalNotificationsPlugin.initialize(initializationSettings);

  const AndroidNotificationDetails androidPlatformChannelSpecifics = AndroidNotificationDetails(
    'payment_reminder_channel',
    'Pengingat Pembayaran',
    channelDescription: 'Notifikasi untuk tagihan jatuh tempo dan terlambat',
    importance: Importance.max,
    priority: Priority.high,
    showWhen: true,
  );
  
  const NotificationDetails platformChannelSpecifics = NotificationDetails(android: androidPlatformChannelSpecifics);
  
  await flutterLocalNotificationsPlugin.show(
    0,
    'Tagihan Pembayaran Kost',
    '$hariIni Kamar Jatuh tempo Hari ini dan $terlambat Terlambat. Tagih Segera!!!',
    platformChannelSpecifics,
  );
}

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  tz.initializeTimeZones();
  
  // Inisialisasi Workmanager (Hanya untuk Android/iOS, tidak didukung di Web)
  if (!kIsWeb) {
    await wm.Workmanager().initialize(callbackDispatcher, isInDebugMode: false);
    
    // Jadwalkan tugas jam 09.00 dan 21.00
    _scheduleDailyTasks();
  }

  if (supabaseUrl != 'YOUR_SUPABASE_URL' && supabasePublishableKey != 'YOUR_SUPABASE_PUBLISHABLE_KEY') {
    try {
      await Supabase.initialize(
        url: supabaseUrl,
        anonKey: supabasePublishableKey,
      );
    } catch (e) {
      debugPrint('Gagal inisialisasi Supabase: $e');
    }
  }

  runApp(const BayarKostApp());
}

void _scheduleDailyTasks() {
  final now = DateTime.now();
  
  // Hitung delay untuk jam 09.00
  DateTime schedule9 = DateTime(now.year, now.month, now.day, 9, 0);
  if (now.isAfter(schedule9)) {
    schedule9 = schedule9.add(const Duration(days: 1));
  }
  final Duration delay9 = schedule9.difference(now);

  // Hitung delay untuk jam 21.00
  DateTime schedule21 = DateTime(now.year, now.month, now.day, 21, 0);
  if (now.isAfter(schedule21)) {
    schedule21 = schedule21.add(const Duration(days: 1));
  }
  final Duration delay21 = schedule21.difference(now);

  // Daftarkan tugas periodik ke Workmanager
  // Workmanager punya limitasi interval minimum 15 menit, dan tidak bisa menjadwalkan tepat waktu detik.
  // Tapi kita bisa gunakan delay awal untuk mendekati jam yang diinginkan.
  
  wm.Workmanager().registerPeriodicTask(
    "daily_check_9am",
    checkPaymentTask,
    frequency: const Duration(hours: 24),
    initialDelay: delay9,
    constraints: wm.Constraints(networkType: wm.NetworkType.connected),
  );

  wm.Workmanager().registerPeriodicTask(
    "daily_check_9pm",
    checkPaymentTask,
    frequency: const Duration(hours: 24),
    initialDelay: delay21,
    constraints: wm.Constraints(networkType: wm.NetworkType.connected),
  );
}

class BayarKostApp extends StatelessWidget {
  const BayarKostApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Pembayaran Kost',
      debugShowCheckedModeBanner: false,
      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      supportedLocales: const [
        Locale('en', 'US'),
        Locale('id', 'ID'),
      ],
      theme: ThemeData(
        brightness: Brightness.light,
        scaffoldBackgroundColor: const Color(0xFFF2F2F7),
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF007AFF),
          background: const Color(0xFFF2F2F7),
        ),
        useMaterial3: true,
        fontFamily: '.SF Pro Text',
      ),
      home: const HomeScreen(),
    );
  }
}

class KostData {
  final String name;
  final String logoText;
  final String? logoAsset;
  final Color themeColor;
  final Color buttonColor;
  final Color buttonTextColor;
  final List<dynamic> tableItems;
  final bool isSupabaseConnected;

  KostData({
    required this.name,
    required this.logoText,
    this.logoAsset,
    required this.themeColor,
    required this.buttonColor,
    required this.buttonTextColor,
    required this.tableItems,
    this.isSupabaseConnected = false,
  });
}

class Penghuni {
  final String noKamar;
  final String nama;
  final String jatuhTempo;
  final String status;
  final String tanggalBayar;
  final String catatan;
  final String catatanAdmin;
  final String? originalNoKamar;

  Penghuni({
    required this.noKamar,
    this.nama = '',
    this.jatuhTempo = '',
    this.status = '',
    this.tanggalBayar = '',
    this.catatan = '',
    this.catatanAdmin = '',
    this.originalNoKamar,
  });
}

// Fungsi top-level untuk memuat data kamar dari lokal maupun Supabase secara konsisten
Future<List<dynamic>> fetchRoomsData(KostData kost, SharedPreferences prefs, {DateTime? selectedDate}) async {
  final date = selectedDate ?? DateTime.now();
  final isFuture = date.year > DateTime.now().year || (date.year == DateTime.now().year && date.month > DateTime.now().month);
  final isPast = date.year < DateTime.now().year || (date.year == DateTime.now().year && date.month < DateTime.now().month);
  final String prefSuffix = "${date.year}_${date.month}";

  // Jika tidak terhubung ke Supabase atau bukan WHITE KOST 35 yang dikonfigurasi Supabase, gunakan data lokal
  if (!kost.isSupabaseConnected) {
    final Map<String, List<Penghuni>> tempGrouped = {};
    final List<String> floorOrder = [];
    String currentFloor = '';

    for (var item in kost.tableItems) {
      if (item is String) {
        currentFloor = item;
        if (!floorOrder.contains(currentFloor)) floorOrder.add(currentFloor);
      } else if (item is Penghuni) {
        final String initNoKamar = item.originalNoKamar ?? item.noKamar;
        
        final savedNoKamar = prefs.getString('nokamar_${kost.name}_$initNoKamar') ?? item.noKamar;
        final savedNama = prefs.getString('nama_${kost.name}_$initNoKamar') ?? item.nama;
        final savedStatus = prefs.getString('status_${kost.name}_$initNoKamar') ?? item.status;
        final savedJatuhTempoRaw = prefs.getString('jtempo_raw_${kost.name}_$initNoKamar') ?? '';
        
        final savedTanggalBayar = prefs.getString('tgl_${kost.name}_${initNoKamar}_$prefSuffix');
        final savedCatatan = prefs.getString('cat_${kost.name}_${initNoKamar}_$prefSuffix');

        // Gunakan data awal dari kode jika di prefs masih kosong
        String? initialTgl;
        String? initialCat;
        
        if (date.year == 2026) {
          if (date.month == 9) {
            if (initNoKamar == '404') {
              initialCat = 'Sudah bayar 1.500.000';
            }
            if (item.tanggalBayar != '-') {
              initialTgl = item.tanggalBayar;
              initialCat = item.catatan;
            }
          } else if (date.month == 8 && initNoKamar == 'D9') {
            initialTgl = item.tanggalBayar;
            initialCat = item.catatan;
          }
        }

        String displayTanggalBayar = savedTanggalBayar ?? initialTgl ?? '-';
        String displayCatatan = savedCatatan ?? initialCat ?? '-';

        String displayJatuhTempo = savedJatuhTempoRaw.isNotEmpty ? savedJatuhTempoRaw : item.jatuhTempo;
        if (displayJatuhTempo.contains('/')) {
          displayJatuhTempo = displayJatuhTempo.split('/').first;
        }

        String displayStatus = savedStatus;

        // Logika penghitungan status otomatis jika ada nama penghuni (kamar terisi)
        if (savedNama.isNotEmpty && savedNama != '-') {
          final today = DateTime.now();
          final isCurrentMonth = date.year == today.year && date.month == today.month;
          final intJatuhTempo = int.tryParse(displayJatuhTempo);

          if (displayTanggalBayar != '-' && displayTanggalBayar.isNotEmpty) {
            displayStatus = 'Lunas';
          } else if (intJatuhTempo != null) {
            if (isCurrentMonth) {
              if (intJatuhTempo == today.day) {
                displayStatus = 'Hari ini';
              } else if (intJatuhTempo < today.day) {
                displayStatus = 'Terlambat\n${today.day - intJatuhTempo} Hari';
              } else {
                displayStatus = '${intJatuhTempo - today.day}\nHari Lagi';
              }
            } else if (isPast) {
              displayStatus = 'Terlambat';
            } else if (isFuture) {
              displayStatus = 'Isi';
            }
          } else {
            if (displayStatus == 'Kosong' || displayStatus.isEmpty) {
              displayStatus = 'Isi';
            }
          }
        } else {
          displayStatus = 'Kosong';
        }
        
        // Filter untuk bulan yang sudah lewat
        if (isPast) {
          // Kasus khusus: Agustus 2026 kamar D9
          if ((kost.name == 'MYKOST 179' || kost.name == 'WHITE KOST 35') && date.year == 2026 && date.month == 8) {
            if (initNoKamar != 'D9') continue;
          } else {
            // Sembunyikan yang sudah lunas atau kosong di bulan lalu
            if (displayTanggalBayar != '-' && displayTanggalBayar.isNotEmpty) continue;
            if (displayStatus == 'Kosong' || displayStatus.isEmpty || displayStatus == 'DP') continue;
          }
          if (!displayStatus.startsWith('Terlambat') && displayStatus != 'Hari ini') {
            displayStatus = 'Terlambat';
          }
        } else if (displayTanggalBayar != '-' && displayTanggalBayar.isNotEmpty) {
          displayStatus = 'Lunas';
        }

        final p = Penghuni(
          noKamar: savedNoKamar,
          nama: savedNama,
          jatuhTempo: displayJatuhTempo,
          status: displayStatus,
          tanggalBayar: displayTanggalBayar,
          catatan: displayCatatan,
          catatanAdmin: '-',
          originalNoKamar: initNoKamar,
        );

        if (!tempGrouped.containsKey(currentFloor)) tempGrouped[currentFloor] = [];
        tempGrouped[currentFloor]!.add(p);
      }
    }

    final List<dynamic> result = [];
    for (var f in floorOrder) {
      if (tempGrouped[f] != null && tempGrouped[f]!.isNotEmpty) {
        result.add(f);
        result.addAll(tempGrouped[f]!);
      }
    }
    return result;
  }

  // Jika kost adalah WHITE KOST 35 dan Supabase terhubung
  try {
    final client = Supabase.instance.client;
    final response = await client
        .from('rooms')
        .select('room_number, floor, status, tenants(full_name, entry_date, admin_note)');

    if (response == null || (response as List).isEmpty) {
      return kost.tableItems;
    }

    final List<dynamic> roomsData = response as List<dynamic>;
    final Map<String, List<Penghuni>> groupedRooms = {
      'Lantai A': [], 'Lantai B': [], 'Lantai C': [], 'Lantai D': [],
      'Lantai 1': [], 'Lantai 2': [], 'Lantai 3': [], 'Lantai 4': [],
    };

    final today = DateTime.now();
    final isCurrentMonth = date.year == today.year && date.month == today.month;

    for (var room in roomsData) {
      final String roomNumber = room['room_number']?.toString() ?? '';
      String rawFloor = room['floor']?.toString() ?? 'A';
      if (!rawFloor.startsWith('Lantai ')) rawFloor = 'Lantai $rawFloor';

      final String roomStatus = room['status']?.toString() ?? 'Kosong';
      final tenantsList = room['tenants'] as List<dynamic>?;

      String nama = '';
      String jatuhTempo = '';
      String adminNote = '-';
      String statusDisplay = roomStatus;

      // Key includes year and month
      final String prefSuffix = "${date.year}_${date.month}";
      final savedTanggalBayar = prefs.getString('tgl_${kost.name}_${roomNumber}_$prefSuffix');
      final savedCatatan = prefs.getString('cat_${kost.name}_${roomNumber}_$prefSuffix');

      // Gunakan data awal dari kode jika di prefs masih kosong
      String? initialTgl;
      String? initialCat;
      
      if (date.year == 2026) {
        if (date.month == 9) {
          if (roomNumber == '404') {
            statusDisplay = 'Terlambat\n7 Hari';
            initialCat = 'Sudah bayar 1.500.000';
          }
          for (var item in kost.tableItems) {
            if (item is Penghuni && (item.noKamar == roomNumber || item.originalNoKamar == roomNumber)) {
              if (item.tanggalBayar != '-') {
                initialTgl = item.tanggalBayar;
                initialCat = item.catatan;
              }
              break;
            }
          }
        } else if (date.month == 8 && roomNumber == 'D9') {
          initialCat = 'Sudah bayar 1.500.000';
        }
      }

      String displayTanggalBayar = savedTanggalBayar ?? initialTgl ?? '-';
      String displayCatatan = savedCatatan ?? initialCat ?? '-';

      if (roomStatus == 'Isi') {
        if (tenantsList != null && tenantsList.isNotEmpty) {
          final tenant = tenantsList.first;
          nama = tenant['full_name']?.toString() ?? '';
          adminNote = tenant['admin_note']?.toString() ?? '-';
          
          final String entryDateStr = tenant['entry_date']?.toString() ?? '';
          final entryDate = DateTime.tryParse(entryDateStr);
          
          if (entryDate != null) {
            jatuhTempo = entryDate.day.toString();
            if (displayTanggalBayar != '-' && displayTanggalBayar.isNotEmpty) {
              statusDisplay = 'Lunas';
            } else if (isCurrentMonth) {
              if (entryDate.day == today.day) {
                statusDisplay = 'Hari ini';
              } else if (entryDate.day < today.day) {
                statusDisplay = 'Terlambat\n${today.day - entryDate.day} Hari';
              } else {
                statusDisplay = '${entryDate.day - today.day}\nHari Lagi'; 
              }
            } else if (isPast) {
              statusDisplay = 'Terlambat'; // In the past, if not paid, it's late
            } else if (isFuture) {
              statusDisplay = 'Isi'; // Future default state
            }
          } else {
            statusDisplay = 'Isi';
          }
        }
      } else if (roomStatus == 'DP') {
        statusDisplay = 'DP';
        if (tenantsList != null && tenantsList.isNotEmpty) {
          nama = tenantsList.first['full_name']?.toString() ?? '';
          adminNote = tenantsList.first['admin_note']?.toString() ?? '-';
        }
      } else {
        statusDisplay = 'Kosong';
      }

      if (displayTanggalBayar != '-' && displayTanggalBayar.isNotEmpty) {
        statusDisplay = 'Lunas';
      }

      // Filter bulan lalu: hanya tampilkan tunggakan
      if (isPast) {
        // Kasus khusus: Agustus 2026 kamar D9
        if (date.year == 2026 && date.month == 8) {
          if (roomNumber == 'D9') {
            statusDisplay = 'Terlambat';
          } else {
            continue; // Selain D9 dianggap lunas dan disembunyikan
          }
        } else {
          // Bulan lalu lainnya: sembunyikan jika lunas/kosong/dp
          if (statusDisplay == 'Lunas' || statusDisplay == 'Kosong' || statusDisplay == 'DP') continue;
          if (!statusDisplay.startsWith('Terlambat') && statusDisplay != 'Hari ini') continue;
        }
      }

      final penghuni = Penghuni(
        noKamar: roomNumber,
        nama: nama,
        jatuhTempo: jatuhTempo,
        status: statusDisplay,
        tanggalBayar: displayTanggalBayar,
        catatan: displayCatatan,
        catatanAdmin: adminNote,
        originalNoKamar: roomNumber,
      );

      if (groupedRooms.containsKey(rawFloor)) {
        groupedRooms[rawFloor]!.add(penghuni);
      }
    }

    final List<dynamic> finalItems = [];
    final orderedFloors = ['Lantai A', 'Lantai B', 'Lantai C', 'Lantai D', 'Lantai 1', 'Lantai 2', 'Lantai 3', 'Lantai 4'];

    for (var floor in orderedFloors) {
      if (groupedRooms[floor] != null && groupedRooms[floor]!.isNotEmpty) {
        finalItems.add(floor);
        groupedRooms[floor]!.sort((a, b) {
          final numA = int.tryParse(RegExp(r'\d+').firstMatch(a.noKamar)?.group(0) ?? '0') ?? 0;
          final numB = int.tryParse(RegExp(r'\d+').firstMatch(b.noKamar)?.group(0) ?? '0') ?? 0;
          return numA != numB ? numA.compareTo(numB) : a.noKamar.compareTo(b.noKamar);
        });
        finalItems.addAll(groupedRooms[floor]!);
      }
    }
    return finalItems;
  } catch (e) {
    debugPrint('Koneksi Supabase Gagal: $e');
    return kost.tableItems;
  }
}

class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final isSupabaseConfigured = supabaseUrl.startsWith('https://') && supabasePublishableKey.startsWith('sb_');
    final whiteKostItems = _generateLocalWhiteKostData();

    final whiteKost = KostData(
      name: 'WHITE KOST 35',
      logoText: 'WK',
      logoAsset: 'assets/white_kost_logo.png',
      themeColor: Colors.blue.shade50,
      buttonColor: Colors.black,
      buttonTextColor: Colors.white,
      tableItems: whiteKostItems,
      isSupabaseConnected: isSupabaseConfigured,
    );

    final myKost = KostData(
      name: 'MYKOST 179',
      logoText: 'MK',
      logoAsset: 'assets/mykost_logo.png',
      themeColor: const Color(0xFFFDF5E6),
      buttonColor: const Color(0xFFD7CCC8),
      buttonTextColor: const Color(0xFF4E342E),
      tableItems: [
        'Lantai A',
        for (int i = 1; i <= 10; i++) 
          Penghuni(
            noKamar: 'A$i', 
            nama: '', 
            jatuhTempo: '', 
            status: '', 
            tanggalBayar: ''
          ),
        'Lantai B',
        for (int i = 1; i <= 10; i++) 
          Penghuni(
            noKamar: 'B$i', 
            nama: '', 
            jatuhTempo: '', 
            status: '', 
            tanggalBayar: ''
          ),
      ],
      isSupabaseConnected: false,
    );

    return Scaffold(
      body: CustomScrollView(
        slivers: [
          SliverAppBar(
            title: const Text('Pembayaran Kost', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 17)),
            centerTitle: true,
            backgroundColor: const Color(0xCCFFFFFF),
            floating: true,
            pinned: true,
            surfaceTintColor: Colors.transparent,
          ),
          SliverToBoxAdapter(
            child: Center(
              child: Container(
                constraints: const BoxConstraints(maxWidth: 720),
                padding: const EdgeInsets.all(20.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Pilih kost anda yang ingin dikelola',
                      style: TextStyle(color: Color(0xFF8E8E93), fontSize: 15, fontWeight: FontWeight.w500),
                    ),
                    const SizedBox(height: 20),
                    ModernKostCard(kost: whiteKost),
                    const SizedBox(height: 24),
                    ModernKostCard(kost: myKost),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  List<dynamic> _generateLocalWhiteKostData() {
    final items = <dynamic>[];
    
    // Data dari screenshot untuk Lantai A, B, C, D
    final dataLantai = {
      // Lantai A
      'A2': Penghuni(noKamar: 'A2', nama: 'Felicia Intan', jatuhTempo: '1', status: 'Lunas', tanggalBayar: '31/08/26', catatan: '-'),
      'A4': Penghuni(noKamar: 'A4', nama: 'Jihan Zakiyah', jatuhTempo: '20', status: 'Lunas', tanggalBayar: '20/09/26', catatan: '-'),
      'A6': Penghuni(noKamar: 'A6', nama: 'Alisha', jatuhTempo: '12', status: 'Lunas', tanggalBayar: '12/09/26', catatan: '-'),
      'A8': Penghuni(noKamar: 'A8', nama: 'Anisa Dira Yustarina', jatuhTempo: '3', status: 'Lunas', tanggalBayar: '03/09/26', catatan: '-'),
      'A10': Penghuni(noKamar: 'A10', nama: 'Fathin Rahma Aisyah', jatuhTempo: '1', status: 'Lunas', tanggalBayar: '01/09/26', catatan: '-'),
      'A11': Penghuni(noKamar: 'A11', nama: 'Rizki Arya Malik', jatuhTempo: '1', status: 'Lunas', tanggalBayar: '01/09/26', catatan: '-'),
      
      // Lantai B
      'B1': Penghuni(noKamar: 'B1', nama: 'Nameera Medina Wijaya', jatuhTempo: '2', status: 'Lunas', tanggalBayar: '02/09/26', catatan: '-'),
      'B3': Penghuni(noKamar: 'B3', nama: 'Safitri Nurhasanah', jatuhTempo: '1', status: 'Lunas', tanggalBayar: '01/09/26', catatan: '-'),
      'B4': Penghuni(noKamar: 'B4', nama: 'Rintari Zonira', jatuhTempo: '21', status: 'Lunas', tanggalBayar: '21/09/26', catatan: '-'),
      'B5': Penghuni(noKamar: 'B5', nama: 'Rakha Al Prayoga', jatuhTempo: '9', status: 'Lunas', tanggalBayar: '09/09/26', catatan: '-'),
      'B7': Penghuni(noKamar: 'B7', nama: 'Alisya Aditya A', jatuhTempo: '3', status: 'Lunas', tanggalBayar: '03/09/26', catatan: '-'),
      'B9': Penghuni(noKamar: 'B9', nama: 'Rochimatus Sa\'Diyah', jatuhTempo: '14', status: 'Lunas', tanggalBayar: '14/09/26', catatan: '-'),
      'B10': Penghuni(noKamar: 'B10', nama: 'Galang Prasanjaya', jatuhTempo: '20', status: 'Lunas', tanggalBayar: '20/09/26', catatan: '-'),
      
      // Lantai C
      'C5': Penghuni(noKamar: 'C5', nama: 'Bayu Ariwibowo', jatuhTempo: '1', status: 'Lunas', tanggalBayar: '01/09/26', catatan: '-'),
      'C6': Penghuni(noKamar: 'C6', nama: 'Rizki Wijayanti', jatuhTempo: '2', status: 'Lunas', tanggalBayar: '02/09/26', catatan: '-'),
      'C7': Penghuni(noKamar: 'C7', nama: 'M Rohadi Roid', jatuhTempo: '5', status: 'Lunas', tanggalBayar: '05/09/26', catatan: '-'),
      'C10': Penghuni(noKamar: 'C10', nama: 'Wisnu Juan Pradana', jatuhTempo: '7', status: 'Lunas', tanggalBayar: '07/09/26', catatan: '-'),
      
      // Lantai D
      'D9': Penghuni(noKamar: 'D9', nama: 'Kenny Aditya Arizona', jatuhTempo: '29', status: 'Terlambat', tanggalBayar: '-', catatan: 'Sudah bayar 1.500.000'),
      
      // Lantai 1 (Gedung Baru)
      '101': Penghuni(noKamar: '101', nama: 'Bagus Asep Indarto', jatuhTempo: '29', status: 'Lunas', tanggalBayar: '29/08/26', catatan: '-'),
      '102': Penghuni(noKamar: '102', nama: 'Raisanaya', jatuhTempo: '1', status: 'Lunas', tanggalBayar: '01/09/26', catatan: '-'),
      '103': Penghuni(noKamar: '103', nama: 'Ihza Anantama K P', jatuhTempo: '3', status: 'Lunas', tanggalBayar: '03/09/26', catatan: '-'),
      
      // Lantai 2
      '201': Penghuni(noKamar: '201', nama: 'Hana Salsabila Putri', jatuhTempo: '27', status: 'Lunas', tanggalBayar: '27/08/26', catatan: '-'),
      '202': Penghuni(noKamar: '202', nama: 'Rayhan Aditya Saputra', jatuhTempo: '28', status: 'Lunas', tanggalBayar: '28/08/26', catatan: '-'),
      '204': Penghuni(noKamar: '204', nama: 'Febriana Valentina', jatuhTempo: '9', status: 'Lunas', tanggalBayar: '09/09/26', catatan: '-'),
      '205': Penghuni(noKamar: '205', nama: 'Alviola Anenda', jatuhTempo: '20', status: 'Lunas', tanggalBayar: '20/09/26', catatan: '-'),
      '206': Penghuni(noKamar: '206', nama: 'Fiorentina Novella', jatuhTempo: '8', status: 'Lunas', tanggalBayar: '08/09/26', catatan: '-'),
      
      // Lantai 3
      '301': Penghuni(noKamar: '301', nama: 'Kristo Setiadi', jatuhTempo: '2', status: 'Lunas', tanggalBayar: '02/09/26', catatan: '-'),
      '304': Penghuni(noKamar: '304', nama: 'Dinda Tanti Mulatsih', jatuhTempo: '3', status: 'Lunas', tanggalBayar: '03/09/26', catatan: '-'),
      '305': Penghuni(noKamar: '305', nama: 'Fathin Adila', jatuhTempo: '11', status: 'Lunas', tanggalBayar: '11/09/26', catatan: '-'),
      
      // Lantai 4
      '401': Penghuni(noKamar: '401', nama: 'Citra Hapsary Ningtyas', jatuhTempo: '12', status: 'Lunas', tanggalBayar: '12/09/26', catatan: '-'),
      '404': Penghuni(noKamar: '404', nama: 'Teddy Irlan Wibowo', jatuhTempo: '15', status: 'Terlambat\n7 Hari', tanggalBayar: '-', catatan: '-'),
      '405': Penghuni(noKamar: '405', nama: 'Ardyfa Listantyo Husodo', jatuhTempo: '7', status: 'Lunas', tanggalBayar: '07/09/26', catatan: '-'),
    };

    for (var floor in ['A', 'B', 'C', 'D']) {
      items.add('Lantai $floor');
      for (int i = 1; i <= 11; i++) {
        String key = '$floor$i';
        items.add(dataLantai[key] ?? Penghuni(noKamar: key, status: 'Kosong'));
      }
    }
    
    for (int f = 1; f <= 4; f++) {
      items.add('Lantai $f');
      for (int i = 1; i <= 6; i++) {
        String key = '${f}0$i';
        items.add(dataLantai[key] ?? Penghuni(noKamar: key, status: 'Kosong'));
      }
    }
    
    return items;
  }
}

class ModernKostCard extends StatefulWidget {
  final KostData kost;
  const ModernKostCard({super.key, required this.kost});

  @override
  State<ModernKostCard> createState() => _ModernKostCardState();
}

class _ModernKostCardState extends State<ModernKostCard> {
  late Future<List<dynamic>> _itemsFuture;

  @override
  void initState() {
    super.initState();
    _itemsFuture = _initAndLoadData();
  }

  Future<List<dynamic>> _initAndLoadData() async {
    final prefs = await SharedPreferences.getInstance();
    return fetchRoomsData(widget.kost, prefs);
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<List<dynamic>>(
      future: _itemsFuture,
      initialData: widget.kost.tableItems,
      builder: (context, snapshot) {
        final items = snapshot.data ?? widget.kost.tableItems;

        int totalRooms = 0;
        int occupiedRooms = 0;
        int emptyRooms = 0;
        int lunasCount = 0;
        int dpCount = 0;
        int jatuhTempoCount = 0;

        List<String> lunasList = [];
        List<String> dpList = [];
        List<String> jatuhTempoList = [];
        List<String> emptyList = [];

        for (var item in items) {
          if (item is Penghuni) {
            totalRooms++;
            if (item.status == 'Kosong' || (item.status.isEmpty && item.nama.isEmpty)) {
              emptyRooms++;
              emptyList.add(item.noKamar);
            } else {
              occupiedRooms++;
              if (item.status == 'Lunas') {
                lunasCount++;
                lunasList.add(item.noKamar);
              } else if (item.status == 'DP') {
                dpCount++;
                dpList.add(item.noKamar);
              } else if (item.status.contains('Hari ini') || item.status.contains('Terlambat')) {
                jatuhTempoCount++;
                jatuhTempoList.add(item.noKamar);
              }
            }
          }
        }

        return Container(
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(20),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.04),
                blurRadius: 20,
                offset: const Offset(0, 10),
              ),
            ],
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(20),
            child: Stack(
              children: [
                Padding(
                  padding: const EdgeInsets.all(24.0),
                  child: Column(
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Container(
                            height: 60,
                            width: 60,
                            decoration: BoxDecoration(
                              color: widget.kost.logoAsset != null ? Colors.white : widget.kost.buttonColor.withOpacity(0.1),
                              borderRadius: BorderRadius.circular(16),
                              boxShadow: widget.kost.logoAsset != null ? [
                                BoxShadow(
                                  color: Colors.black.withOpacity(0.05),
                                  blurRadius: 10,
                                  offset: const Offset(0, 4),
                                )
                              ] : null,
                            ),
                            child: Center(
                              child: widget.kost.logoAsset != null
                                  ? ClipRRect(
                                      borderRadius: BorderRadius.circular(16),
                                      child: Padding(
                                        padding: const EdgeInsets.all(6.0),
                                        child: Image.asset(
                                          widget.kost.logoAsset!,
                                          width: 60,
                                          height: 60,
                                          fit: BoxFit.contain,
                                        ),
                                      ),
                                    )
                                  : Text(
                                      widget.kost.logoText,
                                      style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700, color: widget.kost.buttonColor),
                                    ),
                            ),
                          ),
                          Expanded(
                            child: Padding(
                              padding: const EdgeInsets.symmetric(horizontal: 4.0),
                              child: Text(
                                widget.kost.name,
                                textAlign: TextAlign.center,
                                maxLines: 1,
                                style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold, letterSpacing: -0.8),
                              ),
                            ),
                          ),
                          if (widget.kost.isSupabaseConnected)
                            Container(
                              width: 60,
                              alignment: Alignment.centerRight,
                              child: Container(
                                padding: const EdgeInsets.all(6),
                                decoration: const BoxDecoration(
                                  color: Color(0xFFE8F5E9),
                                  shape: BoxShape.circle,
                                ),
                                child: const Icon(Icons.cloud_done, color: Color(0xFF34C759), size: 18),
                              ),
                            )
                          else
                            Container(
                              width: 60,
                              alignment: Alignment.centerRight,
                              child: Container(
                                padding: const EdgeInsets.all(6),
                                decoration: BoxDecoration(
                                  color: Colors.blue.withOpacity(0.1),
                                  shape: BoxShape.circle,
                                ),
                                child: const Icon(Icons.sd_storage, color: Colors.blue, size: 18),
                              ),
                            ), // local storage indicator to keep layout consistent
                        ],
                      ),
                      const SizedBox(height: 24),
                      Row(
                        children: [
                          Expanded(child: _buildStat(lunasCount.toString(), 'Lunas', color: const Color(0xFF34C759), onTap: () => _showRoomListDialog('Lunas', lunasList))),
                          Expanded(child: _buildStat(dpCount.toString(), 'DP', color: const Color(0xFFFFCC00), onTap: () => _showRoomListDialog('DP', dpList))),
                          Expanded(child: _buildStat(jatuhTempoCount.toString(), 'Jatuh Tempo', color: const Color(0xFFFF3B30), onTap: () => _showRoomListDialog('Jatuh Tempo', jatuhTempoList))),
                        ],
                      ),
                      const SizedBox(height: 20),
                      Row(
                        children: [
                          Expanded(child: _buildStat(totalRooms.toString(), 'Kamar')),
                          Expanded(child: _buildStat(occupiedRooms.toString(), 'Terisi')),
                          Expanded(child: _buildStat(emptyRooms.toString(), 'Kosong', onTap: () => _showRoomListDialog('Kosong', emptyList))),
                        ],
                      ),
                      const SizedBox(height: 24),
                      SizedBox(
                        width: double.infinity,
                        child: CupertinoButton(
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          color: widget.kost.buttonColor,
                          borderRadius: BorderRadius.circular(12),
                          onPressed: () async {
                            await Navigator.push(
                              context,
                              CupertinoPageRoute(builder: (context) => KostDetailScreen(kost: widget.kost)),
                            );
                            setState(() {
                              _itemsFuture = _initAndLoadData();
                            });
                          },
                          child: Text(
                            'Buka Data Kost',
                            style: TextStyle(
                              fontWeight: FontWeight.w600,
                              fontSize: 16,
                              color: widget.kost.buttonTextColor,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                Positioned(
                  top: 16,
                  right: 16,
                  child: (widget.kost.isSupabaseConnected || widget.kost.name == 'MYKOST 179') ? const SizedBox.shrink() : _buildNotificationBadge(),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  void _showRoomListDialog(String title, List<String> rooms) {
    if (rooms.isEmpty) return;

    showCupertinoDialog(
      context: context,
      builder: (context) => CupertinoAlertDialog(
        title: Text('Daftar Kamar $title', style: const TextStyle(fontWeight: FontWeight.bold)),
        content: Padding(
          padding: const EdgeInsets.only(top: 12.0),
          child: Text(
            rooms.join('  '),
            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w500, letterSpacing: 0.5),
            textAlign: TextAlign.center,
          ),
        ),
        actions: [
          CupertinoDialogAction(
            child: const Text('Tutup'),
            onPressed: () => Navigator.pop(context),
          ),
        ],
      ),
    );
  }

  Widget _buildNotificationBadge() {
    return Stack(
      alignment: Alignment.topRight,
      children: [
        const Padding(
          padding: EdgeInsets.all(4.0),
          child: Icon(CupertinoIcons.bell_fill, color: Color(0xFFFF3B30), size: 24),
        ),
        Container(
          padding: const EdgeInsets.all(4),
          decoration: const BoxDecoration(color: Color(0xFFFF9500), shape: BoxShape.circle),
          child: const Text(
            '2',
            style: TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold),
          ),
        ),
      ],
    );
  }

  Widget _buildStat(String value, String label, {Color? color, VoidCallback? onTap}) {
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Column(
        children: [
          Text(
            value,
            style: TextStyle(
              fontSize: 22,
              fontWeight: FontWeight.w700,
              letterSpacing: -0.5,
              color: color ?? const Color(0xFF1C1C1E),
            ),
          ),
          const SizedBox(height: 2),
          Text(
            label,
            style: const TextStyle(
              fontSize: 14,
              color: Color(0xFF8E8E93),
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }
}

class KostDetailScreen extends StatefulWidget {
  final KostData kost;
  const KostDetailScreen({super.key, required this.kost});

  @override
  State<KostDetailScreen> createState() => _KostDetailScreenState();
}

class _KostDetailScreenState extends State<KostDetailScreen> {
  late Future<List<dynamic>> _tableItemsFuture;
  late SharedPreferences _prefs;
  bool _isPrefsInitialized = false;
  DateTime _selectedDate = DateTime.now();

  @override
  void initState() {
    super.initState();
    _tableItemsFuture = _initAndLoadData();
  }

  Future<List<dynamic>> _initAndLoadData() async {
    _prefs = await SharedPreferences.getInstance();
    _isPrefsInitialized = true;
    return _loadTableData();
  }

  Future<List<dynamic>> _loadTableData() async {
    return fetchRoomsData(widget.kost, _prefs, selectedDate: _selectedDate);
  }

  String _getMonthName(int month) {
    const months = ['Januari', 'Februari', 'Maret', 'April', 'Mei', 'Juni', 'Juli', 'Agustus', 'September', 'Oktober', 'November', 'Desember'];
    return months[month - 1];
  }

  Widget _buildMonthSelector() {
    final prevMonth = DateTime(_selectedDate.year, _selectedDate.month - 1);
    final nextMonth = DateTime(_selectedDate.year, _selectedDate.month + 1);
    
    // Batasan: Agustus 2026 adalah bulan awal
    final minDate = DateTime(2026, 8);
    final showPrev = prevMonth.isAtSameMomentAs(minDate) || prevMonth.isAfter(minDate);

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 12.0),
      child: Row(
        children: [
          Expanded(
            child: showPrev 
              ? _buildMonthButton(prevMonth, const Color(0xFFFFF9C4), false)
              : const SizedBox.shrink(),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: _buildMonthButton(_selectedDate, const Color(0xFFC8E6C9), true),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: _buildMonthButton(nextMonth, const Color(0xFFE1F5FE), false),
          ),
        ],
      ),
    );
  }

  Widget _buildMonthButton(DateTime date, Color color, bool isActive) {
    final label = "${_getMonthName(date.month)} ${date.year}";
    final isCurrentlySelected = date.year == _selectedDate.year && date.month == _selectedDate.month;

    return GestureDetector(
      onTap: () {
        setState(() {
          _selectedDate = date;
          _tableItemsFuture = _loadTableData();
        });
      },
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 12),
        decoration: BoxDecoration(
          color: color,
          borderRadius: BorderRadius.circular(12),
          border: isCurrentlySelected ? Border.all(color: Colors.black.withOpacity(0.2), width: 2) : null,
          boxShadow: [
            if (isCurrentlySelected)
              BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 4, offset: const Offset(0, 2))
          ],
        ),
        child: Center(
          child: Text(
            label,
            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: Colors.black),
            textAlign: TextAlign.center,
          ),
        ),
      ),
    );
  }

  void _showEditDialog(Penghuni p) {
    final String initNoKamar = p.originalNoKamar ?? p.noKamar;
    final bool isMyKost = widget.kost.name == 'MYKOST 179';
    final String prefSuffix = "${_selectedDate.year}_${_selectedDate.month}";

    String currentTanggal = p.tanggalBayar == '-' || p.tanggalBayar == 'Sudah Bayar' ? '' : p.tanggalBayar;
    String currentJatuhTempoRaw = _prefs.getString('jtempo_raw_${widget.kost.name}_$initNoKamar') ?? '';

    final noKamarController = TextEditingController(text: p.noKamar);
    final namaController = TextEditingController(text: p.nama);
    final statusController = TextEditingController(text: p.status);
    final catController = TextEditingController(text: p.catatan == '-' ? '' : p.catatan);

    showCupertinoDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => CupertinoAlertDialog(
          title: Text(isMyKost ? 'Edit Data Kamar' : 'Edit Kamar ${p.noKamar}', style: const TextStyle(fontWeight: FontWeight.bold)),
          content: SingleChildScrollView(
            child: Padding(
              padding: const EdgeInsets.only(top: 12.0),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (isMyKost) ...[
                    CupertinoTextField(
                      controller: noKamarController,
                      placeholder: 'Nomor Kamar',
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                      decoration: BoxDecoration(color: const Color(0xFFF2F2F7), borderRadius: BorderRadius.circular(8)),
                    ),
                    const SizedBox(height: 12),
                    CupertinoTextField(
                      controller: namaController,
                      placeholder: 'Nama Penghuni',
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                      decoration: BoxDecoration(color: const Color(0xFFF2F2F7), borderRadius: BorderRadius.circular(8)),
                    ),
                    const SizedBox(height: 12),
                    GestureDetector(
                      onTap: () async {
                        final DateTime? picked = await showDatePicker(
                          context: context,
                          initialDate: DateTime.now(),
                          firstDate: DateTime(2020),
                          lastDate: DateTime(2101),
                          locale: const Locale('id', 'ID'),
                        );
                        if (picked != null) {
                          setDialogState(() {
                            currentJatuhTempoRaw = "${picked.day}/${picked.month}/${picked.year}";
                          });
                        }
                      },
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                        decoration: BoxDecoration(color: const Color(0xFFF2F2F7), borderRadius: BorderRadius.circular(8)),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text(
                              currentJatuhTempoRaw.isEmpty ? 'Pilih Tanggal Masuk' : currentJatuhTempoRaw,
                              style: TextStyle(color: currentJatuhTempoRaw.isEmpty ? const Color(0xFFC7C7CC) : Colors.black, fontSize: 14),
                            ),
                            const Icon(CupertinoIcons.calendar, color: Color(0xFF007AFF), size: 20),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),
                  ] else ...[
                    if (p.nama.isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 12.0),
                        child: Text('Penghuni: ${p.nama}', style: const TextStyle(fontSize: 13, color: Colors.grey)),
                      ),
                  ],
                  GestureDetector(
                    onTap: () async {
                      final DateTime? picked = await showDatePicker(
                        context: context,
                        initialDate: DateTime.now(),
                        firstDate: DateTime(2020),
                        lastDate: DateTime(2101),
                        locale: const Locale('id', 'ID'),
                      );
                      if (picked != null) {
                        setDialogState(() {
                          currentTanggal = "${picked.day}/${picked.month}/${picked.year}";
                        });
                      }
                    },
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                      decoration: BoxDecoration(color: const Color(0xFFF2F2F7), borderRadius: BorderRadius.circular(8)),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(
                            currentTanggal.isEmpty ? 'Pilih Tanggal Bayar' : currentTanggal,
                            style: TextStyle(color: currentTanggal.isEmpty ? const Color(0xFFC7C7CC) : Colors.black, fontSize: 14),
                          ),
                          const Icon(CupertinoIcons.calendar, color: Color(0xFF007AFF), size: 20),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  CupertinoTextField(
                    controller: catController,
                    placeholder: 'Catatan tambahan',
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                    decoration: BoxDecoration(color: const Color(0xFFF2F2F7), borderRadius: BorderRadius.circular(8)),
                  ),
                ],
              ),
            ),
          ),
          actions: [
            CupertinoDialogAction(
              isDestructiveAction: true,
              onPressed: () => Navigator.pop(context),
              child: const Text('Batal'),
            ),
            CupertinoDialogAction(
              isDefaultAction: true,
              onPressed: () async {
                if (_isPrefsInitialized) {
                  final catVal = catController.text.trim().isEmpty ? '-' : catController.text.trim();
                  
                  if (isMyKost) {
                    await _prefs.setString('nokamar_${widget.kost.name}_$initNoKamar', noKamarController.text.trim());
                    await _prefs.setString('nama_${widget.kost.name}_$initNoKamar', namaController.text.trim());
                    await _prefs.setString('status_${widget.kost.name}_$initNoKamar', statusController.text.trim());
                    await _prefs.setString('jtempo_raw_${widget.kost.name}_$initNoKamar', currentJatuhTempoRaw);
                    
                    final tglVal = currentTanggal.isEmpty ? '-' : currentTanggal;
                    await _prefs.setString('tgl_${widget.kost.name}_${initNoKamar}_$prefSuffix', tglVal);
                    await _prefs.setString('cat_${widget.kost.name}_${initNoKamar}_$prefSuffix', catVal);
                  } else {
                    final tglVal = currentTanggal.isEmpty ? '-' : currentTanggal;
                    await _prefs.setString('tgl_${widget.kost.name}_${p.noKamar}_$prefSuffix', tglVal);
                    await _prefs.setString('cat_${widget.kost.name}_${p.noKamar}_$prefSuffix', catVal);
                  }
                  
                  if (mounted) {
                    Navigator.pop(context);
                    setState(() {
                      _tableItemsFuture = _loadTableData();
                    });
                  }
                }
              },
              child: const Text('Simpan'),
            ),
          ],
        ),
      ),
    );
  }

  void _showTanggalBayarOptions(Penghuni p) {
    showCupertinoModalPopup(
      context: context,
      builder: (context) => CupertinoActionSheet(
        title: Text('Tanggal Bayar - Kamar ${p.noKamar}'),
        message: const Text('Pilih metode pengisian tanggal bayar:'),
        actions: [
          CupertinoActionSheetAction(
            child: const Text('Ambil Data dari Supabase'),
            onPressed: () {
              Navigator.pop(context);
              _syncTanggalBayarFromSupabase(p);
            },
          ),
          CupertinoActionSheetAction(
            child: const Text('Input Manual (Lokal)'),
            onPressed: () {
              Navigator.pop(context);
              _inputManualTanggalBayar(p);
            },
          ),
          CupertinoActionSheetAction(
            isDestructiveAction: true,
            child: const Text('Kosongkan'),
            onPressed: () async {
              Navigator.pop(context);
              final initNoKamar = p.originalNoKamar ?? p.noKamar;
              final prefSuffix = "${_selectedDate.year}_${_selectedDate.month}";
              await _prefs.setString('tgl_${widget.kost.name}_${initNoKamar}_$prefSuffix', '-');
              setState(() {
                _tableItemsFuture = _loadTableData();
              });
            },
          ),
        ],
        cancelButton: CupertinoActionSheetAction(
          child: const Text('Batal'),
          onPressed: () => Navigator.pop(context),
        ),
      ),
    );
  }

  Future<void> _syncTanggalBayarFromSupabase(Penghuni p) async {
    if (!widget.kost.isSupabaseConnected) {
      if (!mounted) return;
      showCupertinoDialog(
        context: context,
        builder: (context) => CupertinoAlertDialog(
          title: const Text('Info'),
          content: const Text('Kost ini tidak terhubung ke Supabase.'),
          actions: [
            CupertinoDialogAction(
              child: const Text('OK'),
              onPressed: () => Navigator.pop(context),
            ),
          ],
        ),
      );
      return;
    }

    if (!mounted) return;
    showCupertinoDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => const CupertinoAlertDialog(
        content: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            CupertinoActivityIndicator(),
            SizedBox(width: 16),
            Text('Mengambil data dari Supabase...'),
          ],
        ),
      ),
    );

    try {
      final client = Supabase.instance.client;
      final initNoKamar = p.originalNoKamar ?? p.noKamar;
      
      final res = await client
          .from('rooms')
          .select('*, tenants(*)')
          .eq('room_number', initNoKamar)
          .maybeSingle();

      if (!mounted) return;
      if (Navigator.canPop(context)) {
        Navigator.pop(context); // Dismiss loading dialog
      }

      String? supabaseDate;
      if (res != null) {
        supabaseDate = res['payment_date']?.toString() 
            ?? res['tanggal_bayar']?.toString() 
            ?? res['paid_at']?.toString();

        if ((supabaseDate == null || supabaseDate.isEmpty || supabaseDate == '-') && res['tenants'] != null) {
          final tenants = res['tenants'];
          if (tenants is List && tenants.isNotEmpty) {
            final t = tenants[0];
            supabaseDate = t['payment_date']?.toString() 
                ?? t['tanggal_bayar']?.toString() 
                ?? t['paid_at']?.toString();
          } else if (tenants is Map) {
            supabaseDate = tenants['payment_date']?.toString() 
                ?? tenants['tanggal_bayar']?.toString() 
                ?? tenants['paid_at']?.toString();
          }
        }
      }

      String? validFormattedDate;
      if (supabaseDate != null && supabaseDate.isNotEmpty && supabaseDate != '-') {
        final parsed = DateTime.tryParse(supabaseDate);
        if (parsed != null) {
          if (parsed.month == _selectedDate.month && parsed.year == _selectedDate.year) {
            validFormattedDate = "${parsed.day.toString().padLeft(2, '0')}/${parsed.month.toString().padLeft(2, '0')}/${parsed.year.toString().substring(2)}";
          }
        } else {
          validFormattedDate = supabaseDate;
        }
      }

      if (!mounted) return;
      if (validFormattedDate != null) {
        final prefSuffix = "${_selectedDate.year}_${_selectedDate.month}";
        await _prefs.setString('tgl_${widget.kost.name}_${initNoKamar}_$prefSuffix', validFormattedDate);

        if (!mounted) return;
        setState(() {
          _tableItemsFuture = _loadTableData();
        });
        if (!mounted) return;
        showCupertinoDialog(
          context: context,
          builder: (context) => CupertinoAlertDialog(
            title: const Text('Berhasil'),
            content: Text('Tanggal bayar berhasil disinkronkan dari Supabase: $validFormattedDate'),
            actions: [
              CupertinoDialogAction(
                child: const Text('OK'),
                onPressed: () => Navigator.pop(context),
              ),
            ],
          ),
        );
      } else {
        if (!mounted) return;
        showCupertinoDialog(
          context: context,
          builder: (context) => CupertinoAlertDialog(
            title: const Text('Tidak Ditemukan'),
            content: Text('Data tanggal bayar untuk bulan ${_getMonthName(_selectedDate.month)} ${_selectedDate.year} tidak ditemukan di Supabase untuk kamar ini.'),
            actions: [
              CupertinoDialogAction(
                child: const Text('OK'),
                onPressed: () => Navigator.pop(context),
              ),
            ],
          ),
        );
      }
    } catch (e) {
      if (!mounted) return;
      if (Navigator.canPop(context)) {
        Navigator.pop(context); // Dismiss loading dialog
      }
      if (!mounted) return;
      showCupertinoDialog(
        context: context,
        builder: (context) => CupertinoAlertDialog(
          title: const Text('Gagal'),
          content: Text('Gagal mengambil data dari Supabase: $e'),
          actions: [
            CupertinoDialogAction(
              child: const Text('OK'),
              onPressed: () => Navigator.pop(context),
            ),
          ],
        ),
      );
    }
  }

  Future<void> _inputManualTanggalBayar(Penghuni p) async {
    final DateTime? picked = await showDatePicker(
      context: context,
      initialDate: DateTime.now(),
      firstDate: DateTime(2020),
      lastDate: DateTime(2101),
      locale: const Locale('id', 'ID'),
    );

    if (picked != null) {
      final formattedDate = "${picked.day.toString().padLeft(2, '0')}/${picked.month.toString().padLeft(2, '0')}/${picked.year.toString().substring(2)}";
      final initNoKamar = p.originalNoKamar ?? p.noKamar;
      final prefSuffix = "${_selectedDate.year}_${_selectedDate.month}";
      
      // Save locally only, explicitly NOT sent to Supabase
      await _prefs.setString('tgl_${widget.kost.name}_${initNoKamar}_$prefSuffix', formattedDate);

      if (mounted) {
        setState(() {
          _tableItemsFuture = _loadTableData();
        });
      }
    }
  }

  Future<void> _syncAllTanggalBayarFromSupabase() async {
    if (!widget.kost.isSupabaseConnected) {
      if (!mounted) return;
      showCupertinoDialog(
        context: context,
        builder: (context) => CupertinoAlertDialog(
          title: const Text('Info'),
          content: const Text('Kost ini tidak terhubung ke Supabase.'),
          actions: [
            CupertinoDialogAction(
              child: const Text('OK'),
              onPressed: () => Navigator.pop(context),
            ),
          ],
        ),
      );
      return;
    }

    if (!mounted) return;
    showCupertinoDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => const CupertinoAlertDialog(
        content: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            CupertinoActivityIndicator(),
            SizedBox(width: 16),
            Text('Menyinkronkan semua tanggal bayar...'),
          ],
        ),
      ),
    );

    try {
      final client = Supabase.instance.client;
      final response = await client
          .from('rooms')
          .select('*, tenants(*)');

      if (!mounted) return;
      if (Navigator.canPop(context)) {
        Navigator.pop(context); // Dismiss loading dialog
      }

      if (response == null || (response as List).isEmpty) {
        if (!mounted) return;
        showCupertinoDialog(
          context: context,
          builder: (context) => CupertinoAlertDialog(
            title: const Text('Info'),
            content: const Text('Tidak ada data kamar ditemukan di Supabase.'),
            actions: [
              CupertinoDialogAction(
                child: const Text('OK'),
                onPressed: () => Navigator.pop(context),
              ),
            ],
          ),
        );
        return;
      }

      final List<dynamic> roomsData = response as List<dynamic>;
      final prefSuffix = "${_selectedDate.year}_${_selectedDate.month}";
      int syncedCount = 0;

      for (var room in roomsData) {
        final roomNumber = room['room_number']?.toString();
        if (roomNumber == null || roomNumber.isEmpty) continue;

        String? supabaseDate = room['payment_date']?.toString() 
            ?? room['tanggal_bayar']?.toString() 
            ?? room['paid_at']?.toString();

        if ((supabaseDate == null || supabaseDate.isEmpty || supabaseDate == '-') && room['tenants'] != null) {
          final tenants = room['tenants'];
          if (tenants is List && tenants.isNotEmpty) {
            final t = tenants[0];
            supabaseDate = t['payment_date']?.toString() 
                ?? t['tanggal_bayar']?.toString() 
                ?? t['paid_at']?.toString();
          } else if (tenants is Map) {
            supabaseDate = tenants['payment_date']?.toString() 
                ?? tenants['tanggal_bayar']?.toString() 
                ?? tenants['paid_at']?.toString();
          }
        }

        if (supabaseDate != null && supabaseDate.isNotEmpty && supabaseDate != '-') {
          final parsed = DateTime.tryParse(supabaseDate);
          if (parsed != null) {
            if (parsed.month == _selectedDate.month && parsed.year == _selectedDate.year) {
              final formattedDate = "${parsed.day.toString().padLeft(2, '0')}/${parsed.month.toString().padLeft(2, '0')}/${parsed.year.toString().substring(2)}";
              await _prefs.setString('tgl_${widget.kost.name}_${roomNumber}_$prefSuffix', formattedDate);
              syncedCount++;
            }
          }
        }
      }

      if (!mounted) return;
      setState(() {
        _tableItemsFuture = _loadTableData();
      });

      if (!mounted) return;
      showCupertinoDialog(
        context: context,
        builder: (context) => CupertinoAlertDialog(
          title: const Text('Sinkronisasi Berhasil'),
          content: Text('Berhasil menyinkronkan tanggal bayar untuk $syncedCount kamar (sesuai bulan ${_getMonthName(_selectedDate.month)} ${_selectedDate.year}) dari Supabase.'),
          actions: [
            CupertinoDialogAction(
              child: const Text('OK'),
              onPressed: () => Navigator.pop(context),
            ),
          ],
        ),
      );
    } catch (e) {
      if (!mounted) return;
      if (Navigator.canPop(context)) {
        Navigator.pop(context); // Dismiss loading dialog
      }
      if (!mounted) return;
      showCupertinoDialog(
        context: context,
        builder: (context) => CupertinoAlertDialog(
          title: const Text('Gagal Sinkronisasi'),
          content: Text('Terjadi kesalahan: $e'),
          actions: [
            CupertinoDialogAction(
              child: const Text('OK'),
              onPressed: () => Navigator.pop(context),
            ),
          ],
        ),
      );
    }
  }

  void _showClearLocalDataConfirmation() {
    showCupertinoDialog(
      context: context,
      builder: (context) => CupertinoAlertDialog(
        title: const Text('Konfirmasi'),
        content: const Text('Hapus data tanggal bayar dan catatan local?'),
        actions: [
          CupertinoDialogAction(
            child: const Text('Batal'),
            onPressed: () => Navigator.pop(context),
          ),
          CupertinoDialogAction(
            isDestructiveAction: true,
            onPressed: () async {
              Navigator.pop(context);
              await _clearLocalTanggalBayarAndNotes();
            },
            child: const Text('Hapus'),
          ),
        ],
      ),
    );
  }

  Future<void> _clearLocalTanggalBayarAndNotes() async {
    if (!_isPrefsInitialized) return;

    final prefSuffix = "${_selectedDate.year}_${_selectedDate.month}";
    final keys = _prefs.getKeys();
    
    for (String key in keys) {
      if ((key.startsWith('tgl_${widget.kost.name}_') || key.startsWith('cat_${widget.kost.name}_')) &&
          key.endsWith('_$prefSuffix')) {
        await _prefs.remove(key);
      }
    }

    if (mounted) {
      setState(() {
        _tableItemsFuture = _loadTableData();
      });
      showCupertinoDialog(
        context: context,
        builder: (context) => CupertinoAlertDialog(
          title: const Text('Berhasil'),
          content: const Text('Data tanggal bayar dan catatan lokal berhasil dihapus. Menampilkan data sinkronisasi Supabase.'),
          actions: [
            CupertinoDialogAction(
              child: const Text('OK'),
              onPressed: () => Navigator.pop(context),
            ),
          ],
        ),
      );
    }
  }

  Future<void> _showLunasOrTerlambatReport() async {
    final now = DateTime.now();
    final isFuture = _selectedDate.year > now.year || (_selectedDate.year == now.year && _selectedDate.month > now.month);
    
    final targetDate = _selectedDate;
    final monthName = _getMonthName(targetDate.month);
    final monthLabel = "$monthName ${targetDate.year}";

    final items = await fetchRoomsData(widget.kost, _prefs, selectedDate: targetDate);
    final List<Penghuni> filteredList = [];
    
    for (var item in items) {
      if (item is Penghuni) {
        if (!isFuture) {
          if (item.status.startsWith('Terlambat') || item.status == 'DP') {
            filteredList.add(item);
          }
        } else {
          if (item.status == 'Lunas') {
            filteredList.add(item);
          }
        }
      }
    }

    final GlobalKey repaintKey = GlobalKey();
    final badgeText = !isFuture ? 'Terlambat' : 'Lunas';
    final badgeColor = !isFuture ? const Color(0xFFFF3B30) : const Color(0xFF34C759);
    final badgeBgColor = !isFuture ? const Color(0xFFFFEBEE) : const Color(0xFFE8F5E9);

    if (!mounted) return;

    showCupertinoDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => CupertinoAlertDialog(
          title: Text('Laporan $badgeText - $monthLabel', style: const TextStyle(fontWeight: FontWeight.bold)),
          content: SizedBox(
            width: 620,
            child: SingleChildScrollView(
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Padding(
                  padding: const EdgeInsets.only(top: 12.0),
                  child: RepaintBoundary(
                    key: repaintKey,
                    child: Container(
                      width: 620,
                      padding: const EdgeInsets.all(28),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(
                          color: Colors.grey.withOpacity(0.2),
                        ),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                                decoration: BoxDecoration(
                                  color: badgeBgColor,
                                  borderRadius: BorderRadius.circular(14),
                                ),
                                child: Text(
                                  badgeText,
                                  style: TextStyle(
                                    color: badgeColor,
                                    fontWeight: FontWeight.bold,
                                    fontSize: 15,
                                  ),
                                ),
                              ),
                              Text(
                                monthLabel,
                                style: const TextStyle(
                                  fontSize: 22,
                                  fontWeight: FontWeight.bold,
                                  color: Color(0xFF1C1C1E),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 18),
                          const Divider(height: 1, thickness: 1),
                          const SizedBox(height: 16),
                          if (filteredList.isEmpty)
                            Padding(
                              padding: const EdgeInsets.symmetric(vertical: 24),
                              child: Center(
                                child: Text(
                                  !isFuture ? 'Tidak ada data terlambat / DP' : 'Belum ada kamar yang lunas',
                                  style: const TextStyle(color: Colors.grey, fontSize: 14),
                                ),
                              ),
                            )
                          else
                            ...filteredList.map((p) => Padding(
                              padding: const EdgeInsets.symmetric(vertical: 8.0),
                              child: Row(
                                children: [
                                  SizedBox(
                                    width: 55,
                                    child: Text(
                                      p.noKamar,
                                      style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14, color: Color(0xFF1C1C1E)),
                                    ),
                                  ),
                                  SizedBox(
                                    width: 210,
                                    child: Text(
                                      p.nama,
                                      maxLines: 1,
                                      softWrap: false,
                                      overflow: TextOverflow.ellipsis,
                                      style: const TextStyle(
                                        fontSize: 14,
                                        color: Color(0xFF1C1C1E),
                                        fontWeight: FontWeight.w500,
                                      ),
                                    ),
                                  ),
                                  SizedBox(
                                    width: 50,
                                    child: Text(
                                      p.jatuhTempo,
                                      style: const TextStyle(fontSize: 13, color: Color(0xFF8E8E93)),
                                      textAlign: TextAlign.center,
                                    ),
                                  ),
                                  const SizedBox(width: 12),
                                  (() {
                                    final isDp = p.status == 'DP';
                                    Color itemColor = isDp ? const Color(0xFFFF9500) : badgeColor;
                                    Color itemBgColor = isDp ? const Color(0xFFFFF3E0) : badgeBgColor;
                                    
                                    String text = p.status;
                                    if (isDp) {
                                      text = 'DP';
                                    } else if (!isFuture) {
                                      final intJatuhTempo = int.tryParse(p.jatuhTempo.contains('/') ? p.jatuhTempo.split('/').first : p.jatuhTempo);
                                      if (intJatuhTempo != null) {
                                        final dueDate = DateTime(targetDate.year, targetDate.month, intJatuhTempo);
                                        final now = DateTime.now();
                                        final todayDate = DateTime(now.year, now.month, now.day);
                                        final dueDateOnly = DateTime(dueDate.year, dueDate.month, dueDate.day);
                                        final diffDays = todayDate.difference(dueDateOnly).inDays;
                                        if (diffDays > 0) {
                                          text = 'Terlambat $diffDays hari';
                                        } else {
                                          text = 'Terlambat';
                                        }
                                      } else {
                                        text = 'Terlambat';
                                      }
                                    } else {
                                      text = p.status;
                                    }

                                    return Container(
                                      width: 110,
                                      alignment: Alignment.center,
                                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                                      decoration: BoxDecoration(
                                        color: itemBgColor,
                                        borderRadius: BorderRadius.circular(6),
                                      ),
                                      child: Text(
                                        text,
                                        style: TextStyle(color: itemColor, fontSize: 12, fontWeight: FontWeight.bold),
                                        textAlign: TextAlign.center,
                                      ),
                                    );
                                  }()),
                                  if (isFuture) ...[
                                    const SizedBox(width: 16),
                                    SizedBox(
                                      width: 90,
                                      child: Text(
                                        p.tanggalBayar,
                                        style: const TextStyle(fontSize: 13, color: Color(0xFF8E8E93)),
                                        textAlign: TextAlign.right,
                                      ),
                                    ),
                                  ],
                                ],
                              ),
                            )).toList(),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
          actions: [
            CupertinoDialogAction(
              onPressed: () => Navigator.pop(context),
              child: const Text('Tutup'),
            ),
            CupertinoDialogAction(
              isDefaultAction: true,
              onPressed: () async {
                try {
                  final boundary = repaintKey.currentContext?.findRenderObject() as RenderRepaintBoundary?;
                  if (boundary != null) {
                    final ui.Image image = await boundary.toImage(pixelRatio: 3.0);
                    final ByteData? byteData = await image.toByteData(format: ui.ImageByteFormat.png);
                    final Uint8List pngBytes = byteData!.buffer.asUint8List();

                    downloadBytes(
                      pngBytes,
                      'Laporan_${badgeText}_${targetDate.month}_${targetDate.year}.png',
                    );

                    if (mounted) {
                      Navigator.pop(context);
                      showCupertinoDialog(
                        context: context,
                        builder: (ctx) => CupertinoAlertDialog(
                          title: const Text('Berhasil'),
                          content: const Text('Gambar laporan berhasil diunduh!'),
                          actions: [
                            CupertinoDialogAction(
                              child: const Text('OK'),
                              onPressed: () => Navigator.pop(ctx),
                            ),
                          ],
                        ),
                      );
                    }
                  }
                } catch (e) {
                  if (mounted) {
                    showCupertinoDialog(
                      context: context,
                      builder: (ctx) => CupertinoAlertDialog(
                        title: const Text('Gagal'),
                        content: Text('Gagal mengunduh gambar: $e'),
                        actions: [
                          CupertinoDialogAction(
                            child: const Text('OK'),
                            onPressed: () => Navigator.pop(ctx),
                          ),
                        ],
                      ),
                    );
                  }
                }
              },
              child: const Text('Download JPG'),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        title: Text(widget.kost.name, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 17)),
        centerTitle: true,
        backgroundColor: Colors.white,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        leading: CupertinoButton(
          padding: EdgeInsets.zero,
          onPressed: () => Navigator.pop(context),
          child: const Icon(CupertinoIcons.back, size: 28),
        ),
        actions: [
          CupertinoButton(
            padding: const EdgeInsets.symmetric(horizontal: 8),
            onPressed: _showLunasOrTerlambatReport,
            child: const Icon(
              CupertinoIcons.cloud_download,
              color: Color(0xFF007AFF),
              size: 22,
            ),
          ),
          CupertinoButton(
            padding: const EdgeInsets.symmetric(horizontal: 8),
            onPressed: _showClearLocalDataConfirmation,
            child: const Icon(
              CupertinoIcons.trash,
              color: Color(0xFFFF3B30),
              size: 22,
            ),
          ),
        ],
      ),
      body: FutureBuilder<List<dynamic>>(
        future: _tableItemsFuture,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(
              child: CupertinoActivityIndicator(radius: 12),
            );
          }

          if (snapshot.hasError) {
            return Center(
              child: Text('Terjadi kesalahan: ${snapshot.error}', style: const TextStyle(color: Colors.red)),
            );
          }

          final items = snapshot.data ?? [];
          int dataRowIndex = 0;
          final bool isMyKost = widget.kost.name == 'MYKOST 179';

          return LayoutBuilder(
            builder: (context, constraints) {
              final bool isDesktop = constraints.maxWidth >= 1000;

              if (isDesktop) {
                return Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: Padding(
                        padding: const EdgeInsets.all(20.0),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            _buildMonthSelector(),
                            const SizedBox(height: 12),
                            Expanded(
                              child: SingleChildScrollView(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    _buildTableHeader(true),
                                    if (items.isEmpty)
                                      Container(
                                        width: double.infinity,
                                        padding: const EdgeInsets.symmetric(vertical: 40),
                                        child: const Center(
                                          child: Text('Tidak ada data untuk bulan ini', style: TextStyle(color: Colors.grey)),
                                        ),
                                      )
                                    else
                                      ...items.map((item) {
                                        if (item is String) return _buildFloorHeader(item, true);
                                        if (item is Penghuni) {
                                          final row = _buildDataRow(item, dataRowIndex % 2 == 0, true);
                                          dataRowIndex++;
                                          return row;
                                        }
                                        return const SizedBox.shrink();
                                      }).toList(),
                                  ],
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(width: 16), // Small gap to summary list as requested
                    Container(
                      width: 360,
                      height: MediaQuery.of(context).size.height - 100,
                      margin: const EdgeInsets.only(top: 20, right: 20, bottom: 20),
                      child: _buildDesktopSummaryCard(items),
                    ),
                  ],
                );
              } else {
                final double containerWidth = isMyKost ? 690 : 840;
                return SingleChildScrollView(
                  child: SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: Padding(
                      padding: const EdgeInsets.only(left: 16.0, right: 16.0, top: 8.0, bottom: 100.0),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          SizedBox(
                            width: containerWidth,
                            child: _buildMonthSelector(),
                          ),
                          _buildTableHeader(false),
                          if (items.isEmpty)
                            Container(
                              width: containerWidth,
                              padding: const EdgeInsets.symmetric(vertical: 40),
                              child: const Center(
                                child: Text('Tidak ada data untuk bulan ini', style: TextStyle(color: Colors.grey)),
                              ),
                            )
                          else
                            ...items.map((item) {
                              if (item is String) return _buildFloorHeader(item, false);
                              if (item is Penghuni) {
                                final row = _buildDataRow(item, dataRowIndex % 2 == 0, false);
                                dataRowIndex++;
                                return row;
                              }
                              return const SizedBox.shrink();
                            }).toList(),
                        ],
                      ),
                    ),
                  ),
                );
              }
            },
          );
        },
      ),
    );
  }

  Widget _buildTableHeader(bool isDesktop) {
    final bool isMyKost = widget.kost.name == 'MYKOST 179';
    if (isDesktop) {
      return Container(
        decoration: const BoxDecoration(
          color: Color(0xFFF2F2F7),
          borderRadius: BorderRadius.vertical(top: Radius.circular(10)),
        ),
        child: Row(
          children: [
            Expanded(flex: 1, child: const _TableCell('Kamar', isHeader: true)),
            Expanded(flex: 3, child: const _TableCell('Nama', isHeader: true, textAlign: TextAlign.left)),
            Expanded(flex: 2, child: const _TableCell('Jatuh Tempo', isHeader: true)),
            Expanded(flex: 2, child: const _TableCell('Status', isHeader: true)),
            Expanded(
              flex: 2,
              child: Container(
                constraints: const BoxConstraints(minHeight: 44),
                padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Expanded(
                      child: Text(
                        'Tanggal Bayar',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontSize: 12,
                          color: Color(0xFF8E8E93),
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ),
                    GestureDetector(
                      onTap: _syncAllTanggalBayarFromSupabase,
                      child: const Padding(
                        padding: EdgeInsets.all(2.0),
                        child: Icon(
                          Icons.sync,
                          size: 16,
                          color: Color(0xFF007AFF),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            Expanded(flex: 3, child: const _TableCell('Catatan Saya', isHeader: true)),
            if (!isMyKost) Expanded(flex: 3, child: const _TableCell('Catatan Admin', isHeader: true)),
          ],
        ),
      );
    } else {
      final double wKamar = 80;
      final double wNama = 150;
      final double wJtempo = 110;
      final double wStatus = 100;
      final double wTgl = 100;
      final double wCat = 150;

      return Container(
        decoration: const BoxDecoration(
          color: Color(0xFFF2F2F7),
          borderRadius: BorderRadius.vertical(top: Radius.circular(10)),
        ),
        child: Row(
          children: [
            _TableCell('Kamar', width: wKamar, isHeader: true),
            _TableCell('Nama', width: wNama, isHeader: true),
            _TableCell('Jatuh Tempo', width: wJtempo, isHeader: true),
            _TableCell('Status', width: wStatus, isHeader: true),
            Container(
              width: wTgl,
              constraints: const BoxConstraints(minHeight: 44),
              padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Expanded(
                    child: Text(
                      'Tanggal Bayar',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 12,
                        color: Color(0xFF8E8E93),
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                  GestureDetector(
                    onTap: _syncAllTanggalBayarFromSupabase,
                    child: const Padding(
                      padding: EdgeInsets.all(2.0),
                      child: Icon(
                        Icons.sync,
                        size: 16,
                        color: Color(0xFF007AFF),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            _TableCell('Catatan Saya', width: wCat, isHeader: true),
            if (!isMyKost) _TableCell('Catatan Admin', width: wCat, isHeader: true),
          ],
        ),
      );
    }
  }

  Widget _buildFloorHeader(String floor, bool isDesktop) {
    final bool isMyKost = widget.kost.name == 'MYKOST 179';
    if (isDesktop) {
      return Container(
        width: double.infinity,
        color: const Color(0xFFE5E5EA),
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Text(
          floor.toUpperCase(),
          textAlign: TextAlign.center,
          style: const TextStyle(color: Color(0xFF3A3A3C), fontWeight: FontWeight.w700, fontSize: 11, letterSpacing: 1.2),
        ),
      );
    } else {
      final double containerWidth = 80 + 150 + 110 + 100 + 100 + 150 + (isMyKost ? 0 : 150);
      return Container(
        width: containerWidth,
        color: const Color(0xFFE5E5EA),
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Text(
          floor.toUpperCase(),
          textAlign: TextAlign.center,
          style: const TextStyle(color: Color(0xFF3A3A3C), fontWeight: FontWeight.w700, fontSize: 11, letterSpacing: 1.2),
        ),
      );
    }
  }

  Widget _buildDataRow(Penghuni p, bool isEven, bool isDesktop) {
    final bool isMyKost = widget.kost.name == 'MYKOST 179';
    if (isDesktop) {
      return Container(
        decoration: BoxDecoration(
          color: isEven ? Colors.white : const Color(0xFFF9F9FB),
          border: Border(bottom: BorderSide(color: Colors.grey.withOpacity(0.1), width: 0.5)),
        ),
        child: Row(
          children: [
            Expanded(
              flex: 1,
              child: GestureDetector(
                onTap: () => _showEditDialog(p),
                child: _TableCell(p.noKamar, isBold: true, textAlign: TextAlign.center),
              ),
            ),
            Expanded(
              flex: 3,
              child: GestureDetector(
                onTap: () => _showEditDialog(p),
                child: _TableCell(p.nama, textAlign: TextAlign.left),
              ),
            ),
            Expanded(
              flex: 2,
              child: GestureDetector(
                onTap: () => _showEditDialog(p),
                child: _TableCell(p.jatuhTempo, textAlign: TextAlign.center),
              ),
            ),
            Expanded(
              flex: 2,
              child: GestureDetector(
                onTap: () => _showEditDialog(p),
                child: _StatusCell(p.status),
              ),
            ),
            Expanded(
              flex: 2,
              child: GestureDetector(
                onTap: () => _showTanggalBayarOptions(p),
                child: Container(
                  color: Colors.transparent,
                  child: _TableCell(p.tanggalBayar, textAlign: TextAlign.center),
                ),
              ),
            ),
            Expanded(
              flex: 3,
              child: GestureDetector(
                onTap: () => _showEditDialog(p),
                child: _TableCell(p.catatan, textAlign: TextAlign.center),
              ),
            ),
            if (!isMyKost)
              Expanded(
                flex: 3,
                child: GestureDetector(
                  onTap: () => _showEditDialog(p),
                  child: _TableCell(p.catatanAdmin, textAlign: TextAlign.center, textColor: const Color(0xFFFF3B30)),
                ),
              ),
          ],
        ),
      );
    } else {
      final double wKamar = 80;
      final double wNama = 150;
      final double wJtempo = 110;
      final double wStatus = 100;
      final double wTgl = 100;
      final double wCat = 150;

      return Container(
        decoration: BoxDecoration(
          color: isEven ? Colors.white : const Color(0xFFF9F9FB),
          border: Border(bottom: BorderSide(color: Colors.grey.withOpacity(0.1), width: 0.5)),
        ),
        child: Row(
          children: [
            GestureDetector(
              onTap: () => _showEditDialog(p),
              child: Row(
                children: [
                  _TableCell(p.noKamar, width: wKamar, isBold: true, textAlign: TextAlign.center),
                  _TableCell(p.nama, width: wNama, textAlign: TextAlign.left),
                  _TableCell(p.jatuhTempo, width: wJtempo, textAlign: TextAlign.center),
                  _StatusCell(p.status, width: wStatus),
                ],
              ),
            ),
            GestureDetector(
              onTap: () => _showTanggalBayarOptions(p),
              child: Container(
                color: Colors.transparent,
                child: _TableCell(p.tanggalBayar, width: wTgl, textAlign: TextAlign.center),
              ),
            ),
            GestureDetector(
              onTap: () => _showEditDialog(p),
              child: Row(
                children: [
                  _TableCell(p.catatan, width: wCat, textAlign: TextAlign.center),
                  if (!isMyKost) 
                    _TableCell(p.catatanAdmin, width: wCat, textAlign: TextAlign.center, textColor: const Color(0xFFFF3B30)),
                ],
              ),
            ),
          ],
        ),
      );
    }
  }

  Widget _buildDesktopSummaryCard(List<dynamic> items) {
    final List<Penghuni> allPenghuni = [];
    for (var item in items) {
      if (item is Penghuni) {
        allPenghuni.add(item);
      }
    }

    final lunasList = allPenghuni.where((p) => p.status == 'Lunas').toList();
    final dpList = allPenghuni.where((p) => p.status == 'DP').toList();
    final kosongList = allPenghuni.where((p) => p.status == 'Kosong' || p.status == '-' || p.status.isEmpty).toList();
    final lainnyaList = allPenghuni.where((p) => p.status != 'Lunas' && p.status != 'DP' && p.status != 'Kosong' && p.status != '-' && p.status.isNotEmpty).toList();

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.grey.withOpacity(0.2)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.04),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text(
                'Ringkasan Bulan Ini',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Color(0xFF1C1C1E)),
              ),
              Text(
                "${_getMonthName(_selectedDate.month)} ${_selectedDate.year}",
                style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: Color(0xFF007AFF)),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              _buildStatBadge('Total', '${allPenghuni.length}', const Color(0xFFE3F2FD), const Color(0xFF007AFF)),
              const SizedBox(width: 8),
              _buildStatBadge('Lunas', '${lunasList.length}', const Color(0xFFE8F5E9), const Color(0xFF34C759)),
              const SizedBox(width: 8),
              if (dpList.isNotEmpty) ...[
                _buildStatBadge('DP', '${dpList.length}', const Color(0xFFFFF3E0), const Color(0xFFFF9500)),
                const SizedBox(width: 8),
              ],
              _buildStatBadge('Kosong', '${kosongList.length}', const Color(0xFFF2F2F7), const Color(0xFF8E8E93)),
            ],
          ),
          const SizedBox(height: 16),
          const Divider(height: 1, thickness: 1),
          const SizedBox(height: 12),
          Expanded(
            child: ListView(
              shrinkWrap: true,
              children: [
                if (lunasList.isNotEmpty) ...[
                  _buildSummarySectionHeader('🟢 Kamar Lunas (${lunasList.length})', const Color(0xFF34C759)),
                  const SizedBox(height: 6),
                  ...lunasList.map((p) => _buildSummaryRoomItem(p)),
                  const SizedBox(height: 12),
                ],
                if (dpList.isNotEmpty) ...[
                  _buildSummarySectionHeader('🟠 Kamar DP (${dpList.length})', const Color(0xFFFF9500)),
                  const SizedBox(height: 6),
                  ...dpList.map((p) => _buildSummaryRoomItem(p)),
                  const SizedBox(height: 12),
                ],
                if (lainnyaList.isNotEmpty) ...[
                  _buildSummarySectionHeader('🔴 Belum Lunas / Terlambat (${lainnyaList.length})', const Color(0xFFFF3B30)),
                  const SizedBox(height: 6),
                  ...lainnyaList.map((p) => _buildSummaryRoomItem(p)),
                  const SizedBox(height: 12),
                ],
                if (kosongList.isNotEmpty) ...[
                  _buildSummarySectionHeader('⚪ Kamar Kosong (${kosongList.length})', const Color(0xFF8E8E93)),
                  const SizedBox(height: 6),
                  ...kosongList.map((p) => _buildSummaryRoomItem(p)),
                  const SizedBox(height: 12),
                ],
                if (allPenghuni.isEmpty)
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: 32),
                    child: Center(
                      child: Text('Tidak ada data kamar', style: TextStyle(color: Colors.grey, fontSize: 13)),
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStatBadge(String label, String value, Color bgColor, Color textColor) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 4),
        decoration: BoxDecoration(
          color: bgColor,
          borderRadius: BorderRadius.circular(10),
        ),
        child: Column(
          children: [
            Text(label, style: TextStyle(fontSize: 11, fontWeight: FontWeight.w500, color: textColor)),
            const SizedBox(height: 2),
            Text(value, style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: textColor)),
          ],
        ),
      ),
    );
  }

  Widget _buildSummarySectionHeader(String title, Color color) {
    return Text(
      title,
      style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: color),
    );
  }

  Widget _buildSummaryRoomItem(Penghuni p) {
    return Container(
      margin: const EdgeInsets.only(bottom: 6),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: const Color(0xFFF9F9FB),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.grey.withOpacity(0.15)),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(color: Colors.grey.withOpacity(0.2)),
                ),
                child: Text(
                  'Kamar ${p.noKamar}',
                  style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12, color: Color(0xFF1C1C1E)),
                ),
              ),
              if (p.nama.isNotEmpty && p.nama != '-') ...[
                const SizedBox(width: 8),
                SizedBox(
                  width: 100,
                  child: Text(
                    p.nama,
                    style: const TextStyle(fontSize: 12, color: Color(0xFF3A3A3C)),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ],
          ),
          _StatusCell(p.status, width: 85),
        ],
      ),
    );
  }
}

class _TableCell extends StatelessWidget {
  final String text;
  final double? width;
  final bool isHeader;
  final bool isBold;
  final TextAlign textAlign;
  final Color? textColor;

  const _TableCell(this.text, {
    this.width, 
    this.isHeader = false, 
    this.isBold = false, 
    this.textAlign = TextAlign.center,
    this.textColor,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: width,
      constraints: const BoxConstraints(minHeight: 44),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
      alignment: textAlign == TextAlign.left ? Alignment.centerLeft : Alignment.center,
      child: Text(
        text,
        textAlign: textAlign,
        style: TextStyle(
          fontSize: 13,
          color: textColor ?? (isHeader ? const Color(0xFF8E8E93) : const Color(0xFF1C1C1E)),
          fontWeight: isBold ? FontWeight.w600 : (isHeader ? FontWeight.w500 : FontWeight.w400),
        ),
      ),
    );
  }
}

class _StatusCell extends StatelessWidget {
  final String status;
  final double? width;
  const _StatusCell(this.status, {this.width});

  @override
  Widget build(BuildContext context) {
    Color textColor = const Color(0xFF1C1C1E);
    Color bgColor = Colors.transparent;

    if (status == 'Lunas') {
      textColor = const Color(0xFF34C759);
      bgColor = const Color(0xFFE8F5E9);
    } else if (status == 'Hari ini') {
      textColor = const Color(0xFF007AFF);
      bgColor = const Color(0xFFE3F2FD);
    } else if (status.contains('Terlambat')) {
      textColor = const Color(0xFFFF3B30);
      bgColor = const Color(0xFFFFEBEE);
    } else if (status.contains('Hari Lagi')) {
      textColor = const Color(0xFF5856D6); // iOS Purple
      bgColor = const Color(0xFFF2F2FF); // Soft Purple Background
    } else if (status == 'DP') {
      textColor = const Color(0xFFFF9500);
      bgColor = const Color(0xFFFFF3E0);
    }

    final content = status == 'Kosong' || status == '' || status == '-' 
        ? Text(status, style: const TextStyle(fontSize: 13, color: Color(0xFF8E8E93)))
        : Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
            decoration: BoxDecoration(color: bgColor, borderRadius: BorderRadius.circular(6)),
            child: Text(
              status,
              textAlign: TextAlign.center, // Memastikan teks multi-baris berada di tengah (Center)
              style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: textColor, height: 1.1),
            ),
          );

    if (width != null) {
      return Container(
        width: width,
        height: 44,
        alignment: Alignment.center,
        child: content,
      );
    }
    return Container(
      height: 44,
      alignment: Alignment.center,
      child: content,
    );
  }
}
