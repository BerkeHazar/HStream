import 'package:flutter/material.dart';

/// HStream renk paleti — **TEK KAYNAK**.
///
/// Uygulamadaki tüm renkler buradan okunur. Bir rengi değiştirmek için yalnızca
/// bu dosyayı düzenle; hub, ayarlar, detay, oynatıcı ve tüm kartlar uyar.
///
/// Android tarafı (XML/Kotlin) Dart'ı okuyamaz. Oradaki karşılıklar
/// `android/app/src/main/res/values/hs_renkler.xml` içindedir ve bu dosyayla
/// EŞLEŞMEK ZORUNDADIR. Bir renk değişirse iki yerde de güncellenmelidir.
class P {
  P._();

  // ==================== Zemin katmanları ====================

  /// Ana arka plan.
  static const bg = Color(0xFF0A0A16);

  /// Panel / bölüm zemini (oynatıcı alt paneli, diyalog gövdeleri).
  static const surface = Color(0xFF141826);

  /// Yükseltilmiş yüzey (kart, buton, çip).
  static const surfaceRaised = Color(0xFF1D2130);

  /// Kart kenarlığı — beyaz %10. Blur'lu gölge yerine bunu kullan.
  static const outline = Color(0x1AFFFFFF);

  /// En yüksek yüzey katmanı (seçili durum, kenarlık vurgusu).
  static const surfaceHigh = Color(0xFF2C3344);

  // ==================== Marka — tek aile ====================

  /// Ana marka rengi (dolgulu butonlar, vurgular).
  static const brand = Color(0xFF6A4FE0);

  /// Açık marka (ikonlar, odak halkası, aktif durum).
  static const brandLight = Color(0xFFA78BFA);

  /// Koyu marka (gradyan ucu).
  static const brandDark = Color(0xFF4632C0);

  /// Odak parlaması — marka renginin %40 saydam hâli.
  /// Blur'lu gölge yerine kenarlık/örtü ile kullanılır (blur takılmaya yol açar).
  static const brandGlow = Color(0x66A78BFA);

  /// Basılma örtüsü — beyaz %16.
  static const pressOverlay = Color(0x29FFFFFF);

  /// Aktif çip zemini — marka renginin %18 saydam hâli (hızlı işlem çipleri).
  static const brandSoft = Color(0x2EA78BFA);

  /// Marka gradyanı (dolgulu butonlar, aktif sekmeler).
  static const List<Color> brandGrad = [brand, brandDark];

  /// Marka gradyanı — açık varyant.
  static const List<Color> brandGradSoft = [brandDark, brandLight];

  // ==================== Metin ====================

  /// Başlıklar.
  static const textPrimary = Color(0xFFFFFFFF);

  /// Alt yazılar, meta bilgi.
  static const textSecondary = Color(0xFFAEB6D6);

  /// İpuçları, pasif etiketler.
  static const textTertiary = Color(0xFF8B93B5);

  // ==================== Bölüm kartları (sessiz/derin) ====================
  // Dolgu koyu ve donuk; renk yalnızca ikonda taşınır. Kart zeminden ince
  // kenarlıkla (`outline`) ayrışır.

  static const canliDolgu = Color(0xFF1B1B30);
  static const canliIkon = Color(0xFFA78BFA);

  static const filmDolgu = Color(0xFF251A1A);
  static const filmIkon = Color(0xFFF0917A);

  static const diziDolgu = Color(0xFF16202F);
  static const diziIkon = Color(0xFF7FB3F5);

  static const favoriDolgu = Color(0xFF241A22);
  static const favoriIkon = Color(0xFFEE8FB8);

  // ==================== Oynatıcı ====================

  /// Kontrol katmanı örtüsü — siyah %62.
  static const playerOverlay = Color(0x9E000000);

  /// Oynatıcı paneli üstü örtüsü — zemin renginin %85 saydam hâli.
  static const playerScrim = Color(0xD90A0A16);

  /// Oynanan kısım.
  static const progressPlayed = brandLight;

  /// Tamponlanan kısım — beyaz %24.
  static const progressBuffered = Color(0x3DFFFFFF);

  /// Oynanmayan kısım — beyaz %14.
  static const progressUnplayed = Color(0x24FFFFFF);

  /// Sürükleme tutamacı.
  static const progressThumb = Color(0xFFFFFFFF);

  /// Görsel yüklenene kadar gösterilen yer tutucu gradyanı.
  static const List<Color> placeholderGrad = [
    Color(0xFF3D4466),
    Color(0xFF232840),
  ];

  /// Görsel üstü karartma — yazı okunabilirliği için (üstten alta saydamlaşır).
  static const List<Color> scrimGrad = [Color(0xE60A0A16), Color(0x000A0A16)];

  /// Yumuşak gölge — yalnızca STATİK kullanım için (poster kutusu vb.).
  /// Animasyonlu gölge KULLANMA: blur her karede yeniden hesaplanır → takılma.
  static const shadowSoft = Color(0x66000000);

  // ==================== Ölçü ====================

  static const radiusCard = 14.0;
  static const radiusButton = 12.0;
  static const radiusPanel = 18.0;

  /// Kenarlık kalınlığı. Parlama efekti için blur'lu gölge YERİNE bunu
  /// kullan (blur her animasyon karesinde yeniden hesaplanır → takılma).
  static const outlineWidth = 1.0;
  static const focusWidth = 4.0;

  // ==================== Tema ====================

  /// Uygulama teması. `showFocusOutline` TV/masaüstünde odak halkasını açar;
  /// dokunmatik cihazlarda kapalıdır.
  static ThemeData tema({required bool showFocusOutline}) {
    BorderSide? odak(Set<WidgetState> states) {
      if (states.contains(WidgetState.focused) && showFocusOutline) {
        return const BorderSide(color: brandLight, width: focusWidth);
      }
      return null;
    }

    return ThemeData(
      brightness: Brightness.dark,
      useMaterial3: true,
      colorScheme: ColorScheme.fromSeed(
        seedColor: brand,
        surface: bg,
        brightness: Brightness.dark,
        surfaceContainer: surfaceRaised,
        surfaceContainerHighest: surfaceHigh,
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: ButtonStyle(
          side: WidgetStateProperty.resolveWith((states) {
            final s = odak(states);
            return s ?? BorderSide.none;
          }),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: ButtonStyle(side: WidgetStateProperty.resolveWith(odak)),
      ),
      iconButtonTheme: IconButtonThemeData(
        style: ButtonStyle(side: WidgetStateProperty.resolveWith(odak)),
      ),
      switchTheme: SwitchThemeData(
        trackOutlineColor: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.focused) && showFocusOutline) {
            return brandLight;
          }
          return null;
        }),
        trackOutlineWidth: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.focused) && showFocusOutline) {
            return focusWidth;
          }
          return null;
        }),
      ),
    );
  }
}
