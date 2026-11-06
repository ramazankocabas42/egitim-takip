#!/usr/bin/env bash
# Eğitim Takip - tek seferlik kurulum betiği (macOS / Linux / Windows Git Bash)
# Önce README.md içindeki 1-3. adımları yapın (Flutter, Firebase CLI, Firebase projesi).
set -e

echo ">> Android proje dosyaları oluşturuluyor (mevcut lib/ dosyalarına dokunulmaz)..."
flutter create --platforms=android --org com.egitimtakip --project-name egitim_takip .

echo ">> Paketler güncel sürümlere yükseltiliyor..."
flutter pub upgrade --major-versions firebase_core firebase_auth cloud_firestore flutter_lints

echo ">> Android ayarları (minSdk 24, uygulama adı, bildirim izinleri)..."
python3 ci/android_ayarla.py . || python ci/android_ayarla.py .

echo ">> Firebase bağlantısı yapılıyor (Firebase projenizi seçin, platform olarak sadece android)..."
dart pub global activate flutterfire_cli
flutterfire configure --platforms=android

echo ">> Firestore güvenlik kuralları yükleniyor..."
read -r -p "Firebase proje kimliğinizi yazın (ör. egitim-takip-1234): " PROJECT_ID
firebase deploy --only firestore:rules --project "$PROJECT_ID"

echo ""
echo "Kurulum tamam. Telefonu USB ile bağlayıp:  flutter run"
echo "Paylaşılabilir APK için:                   flutter build apk --release"
