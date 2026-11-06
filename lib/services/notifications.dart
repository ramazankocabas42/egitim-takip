import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:intl/intl.dart';
import 'package:timezone/data/latest_all.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;

import '../models.dart';
import 'db.dart';

/// Telefon bildirimleri: izin isteme, anlık bildirim ve ödev hatırlatmaları.
class Bildirim {
  Bildirim._();

  static final FlutterLocalNotificationsPlugin _plugin =
      FlutterLocalNotificationsPlugin();
  static bool _hazir = false;

  static const _hatirlatmaKanali = AndroidNotificationDetails(
    'odev_hatirlatma',
    'Ödev hatırlatmaları',
    channelDescription: 'Teslim tarihi yaklaşan ödevler için hatırlatma',
    importance: Importance.high,
    priority: Priority.high,
  );

  static const _guncellemeKanali = AndroidNotificationDetails(
    'odev_guncelleme',
    'Ödev güncellemeleri',
    channelDescription: 'Yeni eklenen, tamamlanan ve kontrol edilen ödevler',
    importance: Importance.high,
    priority: Priority.high,
  );

  /// Uygulama açılışında bir kez çağrılır.
  static Future<void> init() async {
    try {
      tzdata.initializeTimeZones();
      // Uygulama Türkiye'de kullanıldığı için saat dilimi sabit.
      tz.setLocalLocation(tz.getLocation('Europe/Istanbul'));
      await _plugin.initialize(
        settings: const InitializationSettings(
          android: AndroidInitializationSettings('@mipmap/ic_launcher'),
        ),
      );
      _hazir = true;
    } catch (e) {
      debugPrint('Bildirim başlatılamadı: $e');
    }
  }

  static AndroidFlutterLocalNotificationsPlugin? get _android =>
      _plugin.resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin>();

  /// Android 13 ve üzerinde bildirim iznini sorar.
  static Future<bool> izinIste() async {
    if (!_hazir) return false;
    try {
      return await _android?.requestNotificationsPermission() ?? false;
    } catch (e) {
      debugPrint('Bildirim izni istenemedi: $e');
      return false;
    }
  }

  static Future<void> goster(int id, String baslik, String metin) async {
    if (!_hazir) return;
    try {
      await _plugin.show(
        id: id,
        title: baslik,
        body: metin,
        notificationDetails:
            const NotificationDetails(android: _guncellemeKanali),
      );
    } catch (e) {
      debugPrint('Bildirim gösterilemedi: $e');
    }
  }

  static Future<void> planla(
      int id, String baslik, String metin, DateTime zaman) async {
    if (!_hazir) return;
    try {
      await _plugin.zonedSchedule(
        id: id,
        title: baslik,
        body: metin,
        scheduledDate: tz.TZDateTime.from(zaman, tz.local),
        notificationDetails:
            const NotificationDetails(android: _hatirlatmaKanali),
        androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
      );
    } catch (e) {
      debugPrint('Hatırlatma planlanamadı: $e');
    }
  }

  static Future<void> iptal(int id) async {
    if (!_hazir) return;
    try {
      await _plugin.cancel(id: id);
    } catch (_) {}
  }

  /// Planlanmış tüm hatırlatmaları siler (ekrandaki bildirimlere dokunmaz).
  static Future<void> planlananlariSil() async {
    if (!_hazir) return;
    try {
      final bekleyen = await _plugin.pendingNotificationRequests();
      for (final b in bekleyen) {
        await _plugin.cancel(id: b.id);
      }
    } catch (_) {}
  }

  /// Uygulama yeniden açıldığında da aynı kalan sabit bir numara üretir.
  static int kimlik(String anahtar) {
    var h = 0x811c9dc5;
    for (final c in anahtar.codeUnits) {
      h ^= c;
      h = (h * 0x01000193) & 0xffffffff;
    }
    return h & 0x7fffffff;
  }
}

/// Kullanıcının bağlı olduğu öğrencilerin ödevlerini izler:
/// - Teslim tarihinden önceki akşam (geçtiyse teslim günü sabah) hatırlatır.
/// - Başkası yeni ödev eklediğinde, ödev yapıldığında ya da kontrol
///   edildiğinde bildirim gösterir (uygulama açıkken veya arka plandayken).
class OdevIzleyici {
  OdevIzleyici(this.me);

  final AppUser me;

  StreamSubscription<List<Student>>? _ogrenciAboneligi;
  final Map<String, StreamSubscription<List<Homework>>> _odevAbonelikleri = {};
  final Map<String, Map<String, Homework>> _onceki = {};
  final Map<String, Set<int>> _planli = {};
  final Map<String, String> _adlar = {};

  static const _hatirlatmaSaati = 19; // teslimden önceki akşam
  static const _sabahSaati = 8; // teslim günü sabahı

  /// Öğretmenler çok sayıda öğrenciyle çalıştığı için hatırlatma almaz.
  bool get _hatirlatmaAlir => me.role != UserRole.teacher;

  Future<void> baslat() async {
    await Bildirim.planlananlariSil();
    _ogrenciAboneligi = Db.myStudents(me).listen((liste) {
      final idler = liste.map((s) => s.id).toSet();
      for (final s in liste) {
        _adlar[s.id] = s.name;
        _odevAbonelikleri.putIfAbsent(
          s.id,
          () => Db.homeworks(s.id).listen(
            (odevler) => _guncelle(s.id, odevler),
            onError: (_) {},
          ),
        );
      }
      for (final sid in _odevAbonelikleri.keys
          .where((k) => !idler.contains(k))
          .toList()) {
        _odevAbonelikleri.remove(sid)?.cancel();
        _onceki.remove(sid);
        _hatirlatmalariIptal(sid);
      }
    }, onError: (_) {});
  }

  Future<void> durdur() async {
    await _ogrenciAboneligi?.cancel();
    for (final a in _odevAbonelikleri.values) {
      await a.cancel();
    }
    _odevAbonelikleri.clear();
    _onceki.clear();
    _planli.clear();
    await Bildirim.planlananlariSil();
  }

  void _guncelle(String sid, List<Homework> odevler) {
    final ad = _adlar[sid] ?? 'Öğrenci';
    final onceki = _onceki[sid];

    // İlk yüklemede eski ödevler için bildirim gösterme, sadece kaydet.
    if (onceki != null) {
      for (final hw in odevler) {
        final eski = onceki[hw.id];
        if (eski == null) {
          if (hw.createdBy != me.uid) {
            final teslim =
                hw.dueDate == null ? '' : ' • Teslim: ${_tarih(hw.dueDate!)}';
            Bildirim.goster(
              Bildirim.kimlik('$sid/${hw.id}/yeni'),
              'Yeni ödev: $ad',
              '${_konu(hw)}$teslim',
            );
          }
          continue;
        }
        if (!eski.done && hw.done && me.role.isAdult && hw.doneBy != me.name) {
          Bildirim.goster(
            Bildirim.kimlik('$sid/${hw.id}/yapildi'),
            '$ad ödevini tamamladı',
            _konu(hw),
          );
        }
        if (!eski.checked &&
            hw.checked &&
            me.role == UserRole.student) {
          Bildirim.goster(
            Bildirim.kimlik('$sid/${hw.id}/kontrol'),
            'Ödevin kontrol edildi',
            '${_konu(hw)}${hw.checkedBy.isEmpty ? '' : ' • ${hw.checkedBy}'}',
          );
        }
      }
    }
    _onceki[sid] = {for (final hw in odevler) hw.id: hw};

    if (_hatirlatmaAlir) _hatirlatmalariKur(sid, ad, odevler);
  }

  void _hatirlatmalariKur(String sid, String ad, List<Homework> odevler) {
    final yeni = <int>{};
    final simdi = DateTime.now();
    for (final hw in odevler) {
      final d = hw.dueDate;
      if (hw.done || d == null) continue;
      final gun = DateTime(d.year, d.month, d.day);
      final aksam = gun
          .subtract(const Duration(days: 1))
          .add(const Duration(hours: _hatirlatmaSaati));
      final sabah = gun.add(const Duration(hours: _sabahSaati));
      final id = Bildirim.kimlik('$sid/${hw.id}/hatirlat');
      final kim = me.role == UserRole.student ? '' : '$ad: ';
      if (aksam.isAfter(simdi)) {
        Bildirim.planla(id, 'Yarın teslim edilecek ödev',
            '$kim${_konu(hw)}', aksam);
        yeni.add(id);
      } else if (sabah.isAfter(simdi)) {
        Bildirim.planla(
            id, 'Bugün teslim edilecek ödev', '$kim${_konu(hw)}', sabah);
        yeni.add(id);
      }
    }
    // Yapılan, silinen ya da tarihi geçen ödevlerin hatırlatmalarını kaldır.
    for (final id in (_planli[sid] ?? const <int>{}).difference(yeni)) {
      Bildirim.iptal(id);
    }
    _planli[sid] = yeni;
  }

  void _hatirlatmalariIptal(String sid) {
    for (final id in _planli.remove(sid) ?? const <int>{}) {
      Bildirim.iptal(id);
    }
  }

  static String _konu(Homework hw) =>
      hw.subject.isEmpty ? hw.title : '${hw.subject}: ${hw.title}';

  static String _tarih(DateTime d) => DateFormat('d MMMM', 'tr_TR').format(d);
}
