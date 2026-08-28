# GitHub ve derleme

## GitHub

1. [github.com/new](https://github.com/new) — repository adı: `HStream` (boş repo).
2. Bu paketi bir klasöre çıkarın.
3.

```bat
git init
git add .
git commit -m "HStream 1.0"
git branch -M main
git remote add origin https://github.com/BerkeHazar/HStream.git
git push -u origin main
```

Git yoksa: **Add file** → **Upload files**.

## Derleme

**Windows:** `app` ile yan yana `hstream` olacak şekilde çıkarın, `hstream\build.bat` → menü **[2]** → **[4]**. APK: `output\HStream.apk`

**Linux / macOS:** `./setup.sh` → **[1]**. Sonraki derlemeler: `./hstream/build.sh`

Elle derleme komutları README.md içindedir.
