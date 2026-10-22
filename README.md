# HADİ Crew

Ekibin uygulaması: başvurular, moderasyon, incelemeler, destek, işletme ve kurye operasyonu, kanallar, etkinlik ekleme, istatistik ve raporlar. Tek sayfalık bir web uygulamasıdır (Flutter Web, mobil öncelikli ve duyarlı). Cloudflare Pages'in ücretsiz planında yayınlanır.

- **Kim kullanır:** Ana kurucu, geçici kurucular, yöneticiler, moderatörler ve operasyon rolü verilen ekip üyeleri. Herkes yalnızca yetkisi olan bölümleri görür. Asıl denetim sunucudadır: her işlem Cloud Functions ve Firestore kurallarında yeniden denetlenir.
- **Giriş:** Yalnızca cep telefonu (SMS kodu). Uygulamadaki hesabınla aynı hesap.
- **Üye uygulamasında iz yok:** Ekip ekranları ve bağlamsal ekip düğmeleri (içerik gizle/sil, rol ver, Premium/Elmas ver, moderasyon, "Olarak gör", resmi hesaba geçiş) uygulamadan kaldırıldı. Paylaşılan kodda kalan ekip yetkileri yalnızca `Session.staffTools = true` olan Crew ve Kurucu Paneli'nde açılır; uygulamada kapalıdır.
- **Kod:** Paylaşılan kod (veri katmanı, tema, ortak bileşenler) `../hadimobile` paketinden gelir (`hadi: path: ../hadimobile`). Klasörler **yan yana** olmalı: `D:\hadimobile`, `D:\hadicrew`. Kurucu Paneli de (`D:\hadifounder`) metrik ekranlarını buradan kullanır.

## Bölümler

| Grup | Bölüm | Kim görür |
|---|---|---|
| | **Pano**: bekleyen işler, topluluk sayıları, 7/30/90 günlük eğilim grafikleri (dakikada bir yenilenir) | ekip |
| Üyelik | Başvurular · Bekleme Salonu (ev sahibi) · Üye işlemleri (rol, Premium, Elmas, moderasyon) | yönetici+ / ekip |
| Moderasyon | Moderasyon kuyruğu · Mesaj şikâyetleri · Canlı yayın şikâyetleri · Moderasyon merkezi · Gizlenen içerikler · AI güvenliği | ekip / ilgili yetenek |
| Destek | Destek talepleri (HADİ Destek masası) | ekip |
| İncelemeler | Kimlik doğrulama · Adres belgeleri · Kahve güvenliği | kurucu ya da ilgili yetenek |
| Ticaret | İşletmeler · Kuryeler · Yolculuk anlaşmazlıkları | ilgili yetenek |
| İçerik | Etkinlik ekle · Üye etkinlikleri · Kanallar · AI video şablonları | yönetici+ / ilgili yetenek |
| Raporlar | İstatistik · Ürün metrikleri · Maliyet uyarıları | ana kurucu / kurucu |

Geniş ekranda (≥ 920 px) solda gruplu kenar çubuğu ve bekleyen iş sayıları görünür. Telefonda alt menü vardır: **Pano · Kuyruklar · Üyeler · Tümü**. Kuyruklar sekmesindeki rozet toplam bekleyen iştir.

Personel bildirimleri (yeni başvuru, destek talebi, inceleme vb.) `https://crew.hadisosyal.com/...` bağlantısı taşır. Eski uygulama yolları (`/basvurular`, `/destek-talepleri`, `/yonetim/...`) Crew'de ilgili bölüme yönlenir. Sunucuda adres `CREW_BASE_URL` ortam değişkeniyle değiştirilebilir (`functions/src/crew_link.ts`).

Pano verisi tek bir sunucu çağrısından gelir: `crewDash` (`functions/src/crew_dash.ts`). Bu çağrı rolüne göre sayıları döndürür ve Kurucu Paneli › Hizmetler › **Crew panosu** (`crew_dashboard`) anahtarıyla kapatılabilir.

## Klasör düzeni

```
lib/main.dart              Firebase (web), ekip araçları açık (Session.staffTools), Bekleme Salonu kancaları
lib/app/crew_app.dart      yönlendirme, giriş ve ekip kapısı, tema
lib/app/shell.dart         kenar çubuğu / alt menü, Kuyruklar, Tümü
lib/app/sections.dart      bölüm listesi ve görünürlük kuralları
lib/app/dashboard.dart     Pano (crewDash), grafikler: charts.dart
lib/ops/…                  eski uygulama ekip ekranları (admin, moderation, support, events, lobby, members, metrics)
web/_headers               Cloudflare güvenlik başlıkları (CSP, noindex, çerçeve yasağı)
tools/make_web_config.ps1  Firebase web ayarları → web_config.json (depoya girmez)
tools/build.ps1            derle (+ -Deploy ile Cloudflare'e yükle)
.github/workflows/deploy.yml  main dalına her gönderimde derle + yayınla
```

## Kurulum (bir kez)

### 0. Firebase web uygulaması

Kurucu Paneli için eklediğin Firebase web uygulaması burada da kullanılır. `D:\hadifounder\web_config.json` dosyasını `D:\hadicrew\web_config.json` olarak kopyala. Yoksa `tools\make_web_config.ps1` şablonu oluşturur ve ne yapacağını söyler.

### 1. Cloudflare Pages projesi (ücretsiz)

**Workers & Pages › Create › Pages › Direct Upload**: proje adı `hadi-crew`. Özel alan adı: **Custom domains › `crew.hadisosyal.com`**.

Giriş yalnızca telefonla olsun diye önüne Cloudflare Access koymadım. Sayfa arama motorlarına kapalıdır; veriye erişim Firebase girişi ve sunucu yetkileriyle korunur. İstersen Kurucu Paneli'ndeki gibi Access de eklenebilir (ekip başına e-posta kodu ister).

### 2. Firebase

**Authentication › Settings › Authorized domains** listesine `crew.hadisosyal.com` ve `hadi-crew.pages.dev` alanlarını ekle.

### 3. İlk yayın (bilgisayardan)

```powershell
cd D:\hadicrew
npx wrangler login                      # bir kez
powershell -ExecutionPolicy Bypass -File tools\build.ps1 -Deploy
```

## GitHub

1. Özel depo aç: `tlghn/hadicrew`, ardından:
   ```powershell
   cd D:\hadicrew
   git init -b main
   git add .
   git commit -m "HADİ Crew"
   git remote add origin https://github.com/tlghn/hadicrew.git
   git push -u origin main
   ```
2. **Settings › Secrets and variables › Actions** bölümüne Kurucu Paneli'ndeki gizlilerin aynısını ekle: `HADIMOBILE_READ_TOKEN` (erişim anahtarına `tlghn/hadicrew` deposunu da ekle; Kurucu Paneli de Crew'i okur), `CLOUDFLARE_API_TOKEN`, `CLOUDFLARE_ACCOUNT_ID`, `FB_API_KEY`, `FB_APP_ID`, `FB_SENDER_ID`, `FB_MEASUREMENT_ID`.
3. `main` dalına her gönderim Crew'i derleyip yayınlar. Elle çalıştırmak için **Actions › Crew yayını › Run workflow** yolunu kullan.

## Yerelde deneme

```powershell
flutter run -d chrome --dart-define-from-file=web_config.json
# Firebase'siz demo (yalnızca arayüz): numara serbest, kod 123456
flutter run -d chrome --dart-define=PANEL_DEMO=true
```

Demo kipinde sunucu ya da Firestore'a doğrudan bağlanan bölümler "yüklenemedi" gösterir. Bu beklenen bir durumdur.
