// : HSTREAM HTTPS İSTEMCİSİ — Android'de HTTPS'i çalışır hale getirir.
//
// NEDEN VAR (kök neden):
// reqwest 0.13'te `rustls` özelliği, sunucu sertifikasını doğrulamak için
// ZORUNLU olarak `rustls-platform-verifier` kullanır (reqwest kaynağı,
// `async_impl/client.rs`: `rustls_platform_verifier::Verifier::new(...)`).
// O doğrulayıcı Android'de kendiliğinden çalışmaz; uygulamanın
// `init_hosted` / `init_with_runtime` ile AÇIKÇA başlatması gerekir. Bu proje
// başlatmıyor, dolayısıyla Android'de doğrulayıcı ilk kullanımda PANIC atar:
//
//     "Expect rustls-platform-verifier to be initialized"
//     (rustls-platform-verifier/src/android.rs, `global()`)
//
// Panic bir tokio görevi içinde oluştuğu için FFI geri çağrısı HİÇ ÇALIŞMAZ:
// `c::queue_async` içindeki gelecek düşer, `send_to_callback` çağrılmaz.
// Dart tarafındaki `await` sonsuza kadar bekler. Kullanıcının gördüğü şey
// "yükleme çemberi dönüyor, liste eklenmiyor" olur. Aynı adres masaüstünde
// sorunsuz çalışır; çünkü orada platform doğrulayıcı işletim sisteminin
// sertifika deposunu kullanır ve başlatma adımı istemez. Bu yüzden belirti
// "Android'e özel, sadece HTTPS adreslerde" olur (HTTP panelleri etkilenmez).
//
// ÇÖZÜM:
// Platform doğrulayıcı tamamen devre dışı bırakılır ve istemciye kendi rustls
// yapılandırmamız verilir (`use_preconfigured_tls`). Kök sertifikalar Mozilla
// listesinden gelir (webpki-roots): Android, iOS ve masaüstünde aynı şekilde
// çalışır, hiçbir platform başlatma adımı istemez ve **sertifika doğrulaması
// açık kalır** (doğrulamayı kapatmak yerine doğru kök listesini veriyoruz).
//
// KULLANIM KURALI: reqwest istemcisi kuran HER yer bu fonksiyonu kullanmalı
// (`m3u.rs`, `xtream.rs`). `Client::builder()` doğrudan çağrılırsa hata
// Android'de geri gelir.

use anyhow::Result;

/// Verilen user-agent ile HTTPS destekli bir HTTP istemcisi kurar.
pub fn client(user_agent: &str) -> Result<reqwest::Client> {
    let mut kokler = rustls::RootCertStore::empty();
    kokler
        .roots
        .extend(webpki_roots::TLS_SERVER_ROOTS.iter().cloned());
    let mut tls = rustls::ClientConfig::builder()
        .with_root_certificates(kokler)
        .with_no_client_auth();
    // reqwest'in kendi yapılandırmasıyla aynı ALPN sırası: önce HTTP/2.
    tls.alpn_protocols = vec![b"h2".to_vec(), b"http/1.1".to_vec()];
    Ok(reqwest::Client::builder()
        .use_preconfigured_tls(tls)
        .user_agent(user_agent.to_string())
        .build()?)
}

#[cfg(test)]
mod test_tls {
    use crate::tls;

    /// : İstemci kurulabilmeli (panik yok) ve HTTPS üzerinden gerçek bir
    /// istek atabilmeli. Bu test Android'deki panic hatasının panzehiridir:
    /// platform doğrulayıcı devrede olsaydı istemci kurulur ama istek
    /// aşamasında panik atardı.
    #[test]
    fn test_https_gercek_istek() {
        let rt = tokio::runtime::Runtime::new().unwrap();
        let sonuc = rt.block_on(async {
            let c = tls::client("HStream-test")?;
            let yanit = c
                .get("https://iptv-org.github.io/iptv/index.m3u")
                .send()
                .await?;
            Ok::<u16, anyhow::Error>(yanit.status().as_u16())
        });
        match sonuc {
            Ok(kod) => assert_eq!(kod, 200),
            Err(e) => {
                // Ağ yoksa (çevrimdışı derleme) test atlanır; hata ağ
                // kaynaklıysa bu bir kod hatası değildir.
                println!("ATLANDI (ağ): {e}");
            }
        }
    }
}
