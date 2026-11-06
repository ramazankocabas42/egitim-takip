# Eğitim Takip (Android)

Çocukların ödev, kitap okuma, test kitabı ve deneme çalışmalarını takip eden
Android uygulaması. Veli, öğrenci ve öğretmen her biri kendi telefonundan,
kendi hesabıyla girer ve aynı veriyi canlı olarak görür.

## Özellikler

| Modül | Ne yapar |
|---|---|
| **Özet** | Bekleyen/gecikmiş ödev, kontrol bekleyen ödev, son 7 gün okunan sayfa grafiği, test kitabı ilerlemesi, son deneme neti |
| **Ödevler** | Veli, öğretmen ya da öğrenci ödev ekler (ders, açıklama, teslim tarihi). Öğrenci büyük yeşil **"Yaptım"** butonuna basar. Veli/öğretmen **"Kontrol Et"** ile onaylar. Gecikenler kırmızı görünür. |
| **Kitaplar** | Okunan kitap eklenir. Öğrenci **"Bugün Okudum"** deyip kaç sayfa ve kaç dakika okuduğunu yazar. İlerleme çubuğu, okuma geçmişi, biten kitaplar. |
| **Test Kitapları** | **"Test Kitabı Ekle"** ile alınan kitap; yayınevi, ders, sayfa sayısı ve konuları (sayfa aralıklarıyla) girilir. Öğrenci **çözdüğü sayfalara dokunarak** yeşile çevirir, **bitirdiği konuları** işaretler. Konu ve kitap bazında yüzde ilerleme. |
| **Denemeler** | Test/deneme sonucu: doğru-yanlış-boş, net hesabı (yok / LGS 3Y1D / YKS 4Y1D), derse göre filtre, son 10 sonucun grafiği. |

**Çok kullanıcılı yapı**
- Bir veli birden fazla çocuk ekleyebilir; bir öğretmen birçok öğrenciyi takip edebilir.
- Her öğrenci için 6 haneli bir **davet kodu** oluşur (öğrenci sayfasında sağ üstteki 👥 simgesi).
- Öğretmen ve çocuğun kendi hesabı bu kodla **"Kodla Katıl"** der ve bağlanır.
- İkinci veli (eş) için ayrı, tek kullanımlık bir **Veli kodu** vardır; yalnızca veliler görür.
- Veli, bağlı kişileri görür, istediğini çıkarabilir, kodu yenileyebilir.
- Veri güvenliği Firestore kurallarıyla sağlanır (Firebase'in kural denetleyicisiyle gözden geçirildi): bir öğrencinin bilgisini **yalnızca ona bağlı kişiler** görebilir, roller sonradan değiştirilemez, öğrenci kendi ödevini "kontrol edildi" yapamaz, kayıtlarda boyut sınırları vardır.

## Kurulum (bir kez, yaklaşık 30-45 dakika)

Bilgisayarda (Windows, Mac ya da Linux) yapılır. Sonunda telefonlara
yükleyebileceğiniz bir **APK** dosyası çıkar.

### 1. Gerekli programlar
1. **Flutter**: https://docs.flutter.dev/get-started/install adresindeki
   "Android" kurulumunu izleyin (Android Studio dahil).
   Bitince `flutter doctor` komutu Android için ✓ göstermeli.
2. **Node.js** (https://nodejs.org) kurun, sonra **Firebase CLI**:
   ```
   npm install -g firebase-tools
   firebase login
   ```

### 2. Firebase projesi (ücretsiz)
1. https://console.firebase.google.com → **Proje ekle** → ad: `egitim-takip`.
2. Sol menü **Build → Authentication → Get started → Sign-in method →
   Email/Password → Etkinleştir**.
3. Sol menü **Build → Firestore Database → Create database** →
   konum: `eur3 (europe-west)` → **production mode**.

Ücretsiz (Spark) plan bir ailenin ve birkaç öğretmenin kullanımı için fazlasıyla yeterlidir.

### 3. Projeyi hazırlama
Bu klasörü açın ve terminalde:

**Mac / Linux / Windows (Git Bash):**
```
bash kurulum.sh
```

Betik sırasıyla şunları yapar (elle yapmak isterseniz aynı komutlar):
```
flutter create --platforms=android --org com.egitimtakip --project-name egitim_takip .
flutter pub upgrade --major-versions
dart pub global activate flutterfire_cli
flutterfire configure --platforms=android
firebase deploy --only firestore:rules --project <PROJE-KIMLIGI>
```
Elle yapıyorsanız ayrıca `android/app/build.gradle(.kts)` içindeki
`minSdk` değerini **24** yapın.

> `flutterfire configure` sizden Firebase projenizi seçmenizi ister ve
> `lib/firebase_options.dart` dosyasını otomatik oluşturur.
>
> Kuralları komutla yükleyemezseniz: Firebase Console → Firestore →
> **Rules** sekmesine `firestore.rules` dosyasının içeriğini yapıştırıp **Publish**.

### 4. Çalıştırma ve APK
- Telefonu USB ile bağlayın (telefonda Geliştirici seçenekleri → USB hata ayıklama açık):
  ```
  flutter run
  ```
- Herkese dağıtmak için:
  ```
  flutter build apk --release
  ```
  Çıkan dosya: `build/app/outputs/flutter-apk/app-release.apk`.
  Bu dosyayı WhatsApp / Drive ile öğretmenlere ve çocuğa gönderin;
  telefonda açıp "bilinmeyen kaynaklardan yüklemeye izin ver" deyip kurarlar.
- İleride Google Play'e koymak isterseniz: `flutter build appbundle` ve
  Play Console geliştirici hesabı (tek seferlik ücretli) gerekir.

## Kullanım akışı

1. **Veli** hesap açar → rol: *Veli* → **Öğrenci Ekle** (ad, sınıf).
2. Öğrenci sayfasında 👥 simgesine basar → **davet kodunu kopyalar**.
3. **Öğretmen** uygulamayı kurar, hesap açar → rol: *Öğretmen* → **Kodla Katıl** → kodu yazar.
4. **Çocuk** kendi telefonuna kurar, hesap açar → rol: *Öğrenci* → kodu yazar.
   Uygulama açılınca doğrudan kendi sayfası gelir.
5. Eş de *Veli* olarak hesap açar; 👥 ekranındaki ayrı **Veli kodu** ile sağ üstteki 🔑 simgesinden katılır.
   Veli kodu tam yetki verir, tek kullanımlıktır ve yalnızca velilere görünür; öğretmenle paylaşmayın.

## Proje yapısı

```
lib/
  main.dart                     Uygulama girişi, Türkçe yerelleştirme
  models.dart                   Veri sınıfları (öğrenci, ödev, kitap, test kitabı, sonuç)
  services/db.dart              Tüm Firestore işlemleri
  widgets/common.dart           Ortak bileşenler, ders/sınıf listeleri
  screens/
    auth_gate.dart              Oturum yönlendirmesi
    login_screen.dart           Giriş / kayıt / şifre sıfırlama
    profile_setup_screen.dart   Ad ve rol seçimi
    home_screen.dart            Öğrenci listesi, öğrenci ekleme, kodla katılma
    student_screen.dart         Öğrenci sekmeleri + kişiler/davet kodu
    modules/
      overview_tab.dart         Özet
      homework_tab.dart         Ödevler ("Yaptım" butonu)
      books_tab.dart            Kitap okuma
      test_books_tab.dart       Test kitapları (konu + sayfa işaretleme)
      tests_tab.dart            Test / deneme sonuçları
firestore.rules                 Güvenlik kuralları
kurulum.sh                      Tek seferlik kurulum betiği
```

Yeni bir modül eklemek için: `models.dart`'a sınıf, `db.dart`'a okuma/yazma,
`screens/modules/` altına bir sekme dosyası ekleyip `student_screen.dart`
içindeki sekme listesine eklemek yeterli. Yeni alt koleksiyonu
`Db.subCollections` listesine de ekleyin (öğrenci silinirken temizlensin).

## Sonraki adım fikirleri
- **Bildirim**: öğretmen ödev verince öğrenciye, öğrenci "Yaptım" deyince veliye
  bildirim (Firebase Cloud Messaging + Cloud Functions; Blaze planı gerekir).
- Ödev fotoğrafı ekleme (Firebase Storage).
- Haftalık rapor ekranı / PDF dışa aktarma.

## Sorun giderme
- **"Firebase henüz yapılandırılmadı"**: `flutterfire configure` çalıştırılmamış.
- **"Bu işlem için yetkiniz yok"**: Firestore kuralları yüklenmemiş ya da kişi o öğrenciye bağlı değil.
- **Derleme hatası (minSdk)**: `android/app/build.gradle(.kts)` içinde `minSdk = 24`.
- **Paket sürüm uyumsuzluğu**: `flutter pub upgrade --major-versions` sonra `flutter clean`.
