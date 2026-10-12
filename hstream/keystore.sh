#!/usr/bin/env bash
# HStream - release imzalama anahtari (keystore) olusturucu.
# Bir kez calistir, sonra build.sh anahtari otomatik baglar.
set -euo pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(cd "$HERE/.." && pwd)"
KEYDIR="$ROOT/keys"
KS="$KEYDIR/hstream-release.jks"
PROP="$KEYDIR/key.properties"
TOOLS="$ROOT/tools"

KEYTOOL=""
if [[ -x "$TOOLS/jdk/bin/keytool" ]]; then
  KEYTOOL="$TOOLS/jdk/bin/keytool"
elif command -v keytool >/dev/null 2>&1; then
  KEYTOOL="$(command -v keytool)"
fi
if [[ -z "$KEYTOOL" ]]; then
  echo "[hata] keytool bulunamadi. JDK kur veya once ./setup.sh calistir." >&2
  exit 1
fi

if [[ -f "$KS" ]]; then
  echo "[uyari] $KS zaten var."
  read -r -p "Uzerine yazilsin mi? Mevcut anahtar KAYBOLUR. (e/H): " ans
  if [[ "$ans" != "e" && "$ans" != "E" ]]; then
    echo "Iptal."
    exit 0
  fi
fi

mkdir -p "$KEYDIR"

printf 'Imzalama parolasi (bos birak = otomatik uret): '
read -rs PASS
echo
if [[ -z "${PASS:-}" ]]; then
  PASS="$(LC_ALL=C tr -dc 'A-Za-z0-9' < /dev/urandom | head -c 24)"
  echo "Otomatik parola uretildi."
fi

echo
echo "=== HStream imzalama anahtari olusturuluyor (30 yil gecerli) ==="
"$KEYTOOL" -genkeypair \
  -keystore "$KS" \
  -alias hstream \
  -keyalg RSA -keysize 4096 -validity 10950 \
  -storepass "$PASS" -keypass "$PASS" \
  -dname "CN=HStream, OU=BerkeHazar, O=HStream, C=TR"

{
  echo "storePassword=$PASS"
  echo "keyPassword=$PASS"
  echo "keyAlias=hstream"
  # : DUZ BOLU — `key.properties` Java .properties formatidir ve ters bolu
  # kacis karakteridir; tek ters bolu ile yazilan Windows yolu okunurken
  # bozulur ("C:\Users\..." -> "C:Users...") ve Gradle anahtari bulamaz.
  echo "storeFile=${KS//\\//}"
  # build.gradle bu satiri okur; keytool'un urettigi dosya PKCS12'dir
  # (uzantisi .jks olsa bile). Mevcut bir JKS dosyasi icin "jks" yaz.
  echo "storeType=pkcs12"
} > "$PROP"

chmod 600 "$PROP" "$KS" 2>/dev/null || true

cat > "$KEYDIR/OKUBENI.txt" <<'EOF'
HStream imzalama anahtari - YEDEKLEME TALIMATI
===============================================

Bu klasordeki iki dosya uygulamanin dijital muhru:
  hstream-release.jks   -> muhur
  key.properties        -> muhur + parola

BU KLASORU GITHUB'A YUKLEME. Asla. Kimse gormemeli.


NEREYE YEDEKLENIR
-----------------
1. Parolayi bir PAROLA YONETICISINE kaydet
   (Bitwarden, 1Password, Keepass...).
2. keys klasorunun tamamini ozel bir bulut klasorune kopyala
   (Google Drive / OneDrive - PAYLASIMA ACIK OLMASIN).
3. Bir USB bellege de kopyala.
4. Parola ile dosyayi AYRI yerlerde tut. Biri sizarsa digeri kurtarir.


KAYBEDERSEN NE OLUR
-------------------
Uygulamayi bir daha guncelleyemezsin. Kullanicilar yeni surumu
eskisinin ustune kuramaz; silip bastan kurmalari gerekir ve tum
ayarlari, kaynaklari, gecmisi gider. Geri donusu yok.


Hicbir sey yapmana gerek yok - bu klasor yerinde durdugu surece
derleme anahtari otomatik kullanir.
EOF

echo "Yedekleme talimati yazildi: $KEYDIR/OKUBENI.txt"

cat <<EOF

============================================================
 ANAHTAR HAZIR
============================================================
 Keystore : $KS
 Parola   : $PASS

 >>> BU PAROLAYI VE keys/ KLASORUNU KAYBETME!
     - Parolayi bir parola yoneticisine kaydet.
     - keys/ klasorunu yedekle (bulut, USB...).
     - Kaybedersen uygulamayi bir daha guncelleyemezsin:
       kullanicilar yeni surumu eskisinin ustune kuramaz.
============================================================
EOF
