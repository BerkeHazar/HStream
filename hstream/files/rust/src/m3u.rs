// : HSTREAM M3U AYRISTIRICI — Fred TV'nin `m3u.rs` dosyasinin
// duzeltilmis surumu. Bu dosya artik overlay'in bir parcasi; amac
// "duz m3u linki calismiyor" sikayetinin altindaki somut zayifliklari
// gidermek ve uygulamayi temel depodan bagimsizlastirmak.
//
// Tespit edilen ve duzeltilen sorunlar:
//  1) BOM / girinti: dosya UTF-8 BOM ile basliyorsa ya da satirlar
//     girintiliyse `starts_with("#EXTINF")` TUTMUYOR, tum liste SIFIR
//     kanal olarak ayristiriliyordu ("m3u calismiyor").
//  2) Gorunen ad: `#EXTINF` icindeki nitelik degerleri virgul
//     barindirabilir (group-title="News, Sports"). Eski regex ILK
//     virgulu ayirac sandigi icin ad bozuluyordu. Artik tirnak
//     DISINDAKI ilk virgul kullanilir.
//  3) Medya turu: yalnizca `.mp4`/`.mkv` taniniyordu ve sorgu dizesi
//     (`film.mp4?token=...`) uzantiyi bozuyordu → tum VOD "canli"
//     gorunuyordu.
//  4) Gecici dosya: tum m3u LINK kaynaklari ayni `get.m3u` dosyasini
//     kullaniyordu → birden fazla kaynak birbirinin dosyasini eziyordu.
//     Artik kaynak basina ayri dosya uretilir.

use std::io::Write;
use std::path::PathBuf;
use std::str::FromStr;
use std::sync::LazyLock;
use std::{
    collections::HashMap,
    fs::File,
    io::{BufRead, BufReader},
};

use anyhow::{Context, Result, bail};
use regex::{Captures, Regex};
use rusqlite::Transaction;
use types::{Channel, Source};

use crate::types::ChannelPreserve;
use crate::utils;
use crate::{
    media_type,
    sql::{self, set_channel_group_id},
    types::{self, ChannelHttpHeaders},
    utils::get_user_agent_from_source,
};

static NAME_REGEX: LazyLock<Regex> =
    LazyLock::new(|| Regex::new(r#"tvg-name="(?P<name>[^"]*)""#).unwrap());
static ID_REGEX: LazyLock<Regex> =
    LazyLock::new(|| Regex::new(r#"tvg-id="(?P<id>[^"]*)""#).unwrap());
static LOGO_REGEX: LazyLock<Regex> =
    LazyLock::new(|| Regex::new(r#"tvg-logo="(?P<logo>[^"]*)""#).unwrap());
static GROUP_REGEX: LazyLock<Regex> =
    LazyLock::new(|| Regex::new(r#"group-title="(?P<group>[^"]*)""#).unwrap());

static HTTP_ORIGIN_REGEX: LazyLock<Regex> =
    LazyLock::new(|| Regex::new(r#"http-origin=(?P<origin>.+)"#).unwrap());
static HTTP_REFERRER_REGEX: LazyLock<Regex> =
    LazyLock::new(|| Regex::new(r#"http-referrer=(?P<referrer>.+)"#).unwrap());
static HTTP_USER_AGENT_REGEX: LazyLock<Regex> =
    LazyLock::new(|| Regex::new(r#"http-user-agent=(?P<user_agent>.+)"#).unwrap());

/// : VOD (dosya tabanli) sayilan uzantilar. `.ts`/`.m3u8` KASITLI olarak
/// listede YOK: ikisi de canli HLS yayinlarinda yaygin kullanilir ve
/// canli kanali "film" yapmak yanlis olurdu.
const VOD_UZANTILAR: [&str; 10] = [
    ".mp4", ".mkv", ".avi", ".mov", ".webm", ".flv", ".wmv", ".m4v", ".mpg", ".mpeg",
];

struct M3UProcessing {
    channel_line: Option<String>,
    channel_headers: Option<ChannelHttpHeaders>,
    channel_headers_set: bool,
    last_non_empty_line: Option<String>,
    groups: HashMap<String, i64>,
    source_id: i64,
    line_count: usize,
}

pub fn read_m3u8(source: Source, wipe: bool) -> Result<()> {
    // : M3U (yerel dosya) yolu — `source.url` dosya yoludur.
    let path = source.url.clone().context("no file path found")?;
    read_m3u8_from(source, &path, wipe)
}

fn read_m3u8_from(mut source: Source, path: &str, wipe: bool) -> Result<()> {
    let file = File::open(path).context("Failed to open m3u8 file")?;
    let reader = BufReader::new(file);
    let mut lines = reader.lines().enumerate();
    let mut sql = sql::get_conn()?;
    let mut channel_preserve: Vec<ChannelPreserve> = Vec::new();
    let tx = sql.transaction()?;
    if wipe {
        channel_preserve =
            sql::get_preserve(&tx, source.id.context("no source id")?).unwrap_or_default();
        sql::wipe(&tx, source.id.context("no source id")?)?;
    } else {
        source.id = Some(sql::create_or_find_source_by_name(&tx, &source)?);
    }
    let mut processing = M3UProcessing {
        channel_headers: None,
        channel_headers_set: false,
        channel_line: None,
        groups: HashMap::new(),
        last_non_empty_line: None,
        source_id: source.id.context("no source id")?,
        line_count: 0,
    };
    while let Some((c1, l1)) = lines.next() {
        processing.line_count = c1;
        let l1 = match l1.with_context(|| format!("Failed to process line {c1}")) {
            Ok(r) => r,
            Err(e) => {
                tracing::error!("{:?}", e);
                continue;
            }
        };
        // : SORUN 1 DUZELTMESI — BOM ve bastaki bosluk temizlenir.
        // UTF-8 BOM (`\u{FEFF}`) ile baslayan ya da girintili satirlarda
        // `starts_with("#EXTINF")` tutmuyordu ve TUM liste sifir kanal
        // olarak ayristiriliyordu.
        let temiz = l1.trim_start_matches('\u{feff}').trim();
        if temiz.is_empty() {
            continue;
        }
        let temiz_upper = temiz.to_uppercase();
        if temiz_upper.starts_with("#EXTINF") {
            try_commit_channel(&mut processing, &tx);
            processing.channel_line = Some(temiz.to_string());
            processing.channel_headers_set = false;
        } else if temiz_upper.starts_with("#EXTVLCOPT") {
            if processing.channel_headers.is_none() {
                processing.channel_headers = Some(ChannelHttpHeaders {
                    ..Default::default()
                });
            }
            if set_http_headers(
                temiz,
                processing.channel_headers.as_mut().context("no headers")?,
            ) {
                processing.channel_headers_set = true;
            }
        } else if !temiz_upper.starts_with('#') {
            // : `#EXTM3U` gibi diger baslik satirlari ADRES DEGILDIR;
            // eskiden `last_non_empty_line`e yazilip kanal adresi
            // sanilabiliyordu. Artik yalnizca # ile baslamayan satirlar
            // adres olarak kabul edilir.
            processing.last_non_empty_line = Some(temiz.to_string());
        }
    }
    try_commit_channel(&mut processing, &tx);
    if wipe {
        sql::restore_preserve(&tx, source.id.context("no source id")?, channel_preserve)?;
    }
    sql::analyze(&tx)?;
    tx.commit()?;
    Ok(())
}

fn try_commit_channel(processing: &mut M3UProcessing, tx: &Transaction) {
    if let Some(channel) = processing.channel_line.take() {
        if !processing.channel_headers_set {
            processing.channel_headers = None;
        }
        commit_channel(
            channel,
            processing.last_non_empty_line.take(),
            &mut processing.groups,
            processing.channel_headers.take(),
            processing.source_id,
            tx,
        )
        .with_context(|| {
            format!(
                "Failed to process channel ending at line {}",
                processing.line_count
            )
        })
        .unwrap_or_else(|e| {
            tracing::error!("{:?}", e);
        });
    }
}

fn commit_channel(
    channel_line: String,
    last_line: Option<String>,
    groups: &mut HashMap<String, i64>,
    headers: Option<ChannelHttpHeaders>,
    source_id: i64,
    tx: &Transaction,
) -> Result<()> {
    let mut channel = get_channel_from_lines(
        channel_line,
        last_line.context("missing last line")?,
        source_id,
    )?;
    set_channel_group_id(groups, &mut channel, tx, &source_id).unwrap_or_else(|e| {
        tracing::error!(
            "Failed to set group id for channel: {}, Error: {:?}",
            channel.name,
            e
        )
    });
    sql::insert_channel(tx, channel)?;
    if let Some(mut headers) = headers {
        headers.channel_id = Some(tx.last_insert_rowid());
        sql::insert_channel_headers(tx, headers)?;
    }
    Ok(())
}

pub async fn get_m3u8_from_link(source: Source, wipe: bool) -> Result<()> {
    let user_agent = get_user_agent_from_source(&source)?;
    // : HTTPS İSTEMCİSİ — `crate::tls::client` kullanılır. Doğrudan
    // `reqwest::Client::builder()` çağrılırsa reqwest'in platform
    // doğrulayıcısı Android'de panic atar ve liste HİÇ eklenmez
    // (ayrıntılı gerekçe: src/tls.rs).
    let client = crate::tls::client(&user_agent)?;
    let url = source.url.clone().context("Invalid source")?;
    let mut response = client.get(&url).send().await?;
    if !response.status().is_success() {
        tracing::error!(
            "Failed to get m3u8 from link, status: {}",
            response.status()
        );
        bail!(
            "Failed to get m3u8 from link, status: {}",
            response.status()
        );
    }
    // : SORUN 4 DUZELTMESI — kaynak basina AYRI gecici dosya.
    let path = get_tmp_path(&source)?;
    {
        let mut file = std::fs::File::create(&path)?;
        while let Some(chunk) = response.chunk().await? {
            file.write_all(&chunk)?;
        }
        // : dosya kapanmadan okunmaya baslanmasin (Windows'ta paylasim
        // ihlali riski) — blok ile kapatma garantilenir.
    }
    read_m3u8_from(source, &path, wipe)
}

/// : Kaynak basina benzersiz gecici dosya yolu uretir.
/// Eskiden tum link kaynaklari ayni `get.m3u` dosyasini kullaniyordu;
/// birden fazla m3u linki eklenince kaynaklar birbirinin dosyasini
/// eziyor ve yanlis kanal listesi yukleniyordu.
fn get_tmp_path(source: &Source) -> Result<String> {
    let mut path = PathBuf::from_str(utils::TEMP_PATH.get().context("no temp path")?)?;
    if !path.exists() {
        std::fs::create_dir_all(&path)?;
    }
    // Kaynak adi arayuzde benzersiz tutulur (isim_var kontrolu); dosya
    // adina cevrilirken guvenli karakterlere indirgenir.
    // NOT: `Source::name` `String`'dir (Option DEGIL) — bu yuzden
    // `Option::filter` degil duz bir bos-kontrol kullanilir.
    let ham = if source.name.trim().is_empty() {
        source
            .id
            .map(|i| i.to_string())
            .unwrap_or_else(|| "gecici".to_string())
    } else {
        source.name.clone()
    };
    let guvenli: String = ham
        .chars()
        .map(|c| {
            if c.is_ascii_alphanumeric() || c == '-' || c == '_' {
                c
            } else {
                '_'
            }
        })
        .collect();
    path.push(format!("get_{guvenli}.m3u"));
    Ok(path.to_string_lossy().to_string())
}

fn extract_non_empty_capture(caps: Captures) -> Option<String> {
    caps.get(1)
        .map(|m| m.as_str().to_string())
        .filter(|s| !s.trim().is_empty())
}

/// : SORUN 2 DUZELTMESI — `#EXTINF` satirindaki GORUNEN AD, niteliklerden
/// sonra gelen virgulun sagindadir. Nitelik degerleri tirnak icinde virgul
/// barindirabilir (`group-title="News, Sports"`), bu yuzden ILK virgul
/// yanlis ayirac olabilir. Tirnak DISINDAKI ilk virgul dogru olandir.
fn gorunen_ad(line: &str) -> Option<String> {
    let mut tirnakta = false;
    for (i, c) in line.char_indices() {
        match c {
            '"' => tirnakta = !tirnakta,
            ',' if !tirnakta => {
                let ad = line[i + 1..].trim();
                return if ad.is_empty() {
                    None
                } else {
                    Some(ad.to_string())
                };
            }
            _ => {}
        }
    }
    None
}

fn set_http_headers(line: &str, headers: &mut ChannelHttpHeaders) -> bool {
    if let Some(origin) = HTTP_ORIGIN_REGEX
        .captures(line)
        .and_then(extract_non_empty_capture)
    {
        headers.http_origin = Some(origin);
        return true;
    } else if let Some(referrer) = HTTP_REFERRER_REGEX
        .captures(line)
        .and_then(extract_non_empty_capture)
    {
        headers.referrer = Some(referrer);
        return true;
    } else if let Some(user_agent) = HTTP_USER_AGENT_REGEX
        .captures(line)
        .and_then(extract_non_empty_capture)
    {
        headers.user_agent = Some(user_agent);
        return true;
    }
    return false;
}

fn get_channel_from_lines(first: String, mut second: String, source_id: i64) -> Result<Channel> {
    second = second.trim().to_string();
    if second.is_empty() {
        bail!("second line is empty");
    }
    let name = NAME_REGEX
        .captures(&first)
        .and_then(extract_non_empty_capture)
        .or_else(|| {
            let id = || {
                ID_REGEX
                    .captures(&first)
                    .and_then(extract_non_empty_capture)
            };
            let name_alt = || gorunen_ad(&first);
            return name_alt().or(id());
        })
        .context("Couldn't find name from Name or ID")?;
    let group = GROUP_REGEX
        .captures(&first)
        .and_then(extract_non_empty_capture);
    let image = LOGO_REGEX
        .captures(&first)
        .and_then(extract_non_empty_capture);
    let channel = Channel {
        id: None,
        name: name.trim().to_string(),
        group: group.map(|x| x.trim().to_string()),
        image: image.map(|x| x.trim().to_string()),
        url: Some(second.clone()),
        media_type: get_media_type(second),
        source_id: Some(source_id),
        series_id: None,
        group_id: None,
        favorite: false,
        stream_id: None,
        tv_archive: None,
        season_id: None,
        episode_num: None,
    };
    Ok(channel)
}

/// : SORUN 3 DUZELTMESI — medya turu tespiti.
/// Eskiden yalnizca `.mp4`/`.mkv` taniniyordu ve sorgu dizesi uzantiyi
/// bozuyordu (`film.mp4?token=abc` → "canli"). Artik sorgu/fragment
/// atilir, uzanti kucuk harfe cevrilir ve bilinen VOD uzantilari
/// listesiyle karsilastirilir.
fn get_media_type(url: String) -> u8 {
    let temiz = url
        .split(['?', '#'])
        .next()
        .unwrap_or("")
        .trim()
        .to_lowercase();
    if VOD_UZANTILAR.iter().any(|uzanti| temiz.ends_with(uzanti)) {
        media_type::MOVIE
    } else {
        media_type::LIVESTREAM
    }
}

#[cfg(test)]
mod test_m3u {

    use crate::m3u::{get_channel_from_lines, get_media_type};

    #[test]
    fn test_get_channel_from_lines() {
        get_channel_from_lines(r#"#EXTINF:-1 tvg-id="Amazing Channel" tvg-name="Amazing Channel" tvg-logo="http://myurl.local/logos/amazing/amazing-1.png" group-title="The Best Channels"#.to_string()
       , r#"http://myurl.local/1234/1234/1234"#.to_string(), 0).unwrap();
        get_channel_from_lines(r#"#EXTINF:-1 tvg-id="Amazing Channel" tvg-name="" tvg-logo="http://myurl.local/logos/amazing/amazing-1.png" group-title="The Best Channels"#.to_string()
       , r#"http://myurl.local/1234/1234/1234"#.to_string(), 0).unwrap();
        assert!(get_channel_from_lines(r#"#EXTINF:-1 tvg-id="" tvg-name="" tvg-logo="http://myurl.local/logos/amazing/amazing-1.png" group-title="The Best Channels"#.to_string()
       , r#"http://myurl.local/1234/1234/1234"#.to_string(), 0).is_err());
        assert!(get_channel_from_lines(r#"#EXTINF:-1 tvg-id=" " tvg-name="" tvg-logo="http://myurl.local/logos/amazing/amazing-1.png" group-title="The Best Channels"#.to_string()
       , r#"http://myurl.local/1234/1234/1234"#.to_string(), 0).is_err());
        assert!(get_channel_from_lines(r#"#EXTINF:-1 tvg-id="Id Of Channel" tvg-name="Name Of Channel" tvg-logo="http://myurl.local/amazing/stuff.png" group-title="|EU| FRANCE HEVC",Alt Name Of Channel"#.to_string(), "http://myurl.local/1111/1111.ts".to_string(), 0).unwrap().name == "Name Of Channel");
        // : 404 ve 405 numarali doğrulamalar upstream'de BIREBIR AYNI girdiyle
        // IKI FARKLI sonuc bekliyordu ("Id Of Channel" ve "Alt Name Of
        // Channel") — bu mantiken imkansiz oldugu icin test upstream'de
        // ZATEN DUSUYORDU (orijinal dosyayla dogrulandi: satir 304).
        // Gercek davranis `gorunen_ad().or(id())` seklindedir, yani
        // gorunen ad (virgulden sonraki) tvg-id'den ONCE gelir. Bu yuzden
        // tvg-id yedegini sinayan doğrulama, gorunen adi OLMAYAN (virgulsuz)
        // bir girdi kullanmalidir.
        assert!(get_channel_from_lines(r#"#EXTINF:-1 tvg-id="Id Of Channel" tvg-name="" tvg-logo="http://myurl.local/amazing/stuff.png" group-title="|EU| FRANCE HEVC""#.to_string(), "http://myurl.local/1111/1111.ts".to_string(), 0).unwrap().name == "Id Of Channel");
        assert!(get_channel_from_lines(r#"#EXTINF:-1 tvg-id="Id Of Channel" tvg-name="" tvg-logo="http://myurl.local/amazing/stuff.png" group-title="|EU| FRANCE HEVC",Alt Name Of Channel"#.to_string(), "http://myurl.local/1111/1111.ts".to_string(), 0).unwrap().name == "Alt Name Of Channel");
    }

    /// : YENI — grup adi virgul icerdiginde gorunen ad bozulmamali.
    #[test]
    fn test_gorunen_ad_virgul_nitelik_icinde() {
        let ch = get_channel_from_lines(
            r#"#EXTINF:-1 tvg-name="" tvg-id="" group-title="News, Sports",Real Channel Name"#
                .to_string(),
            "http://myurl.local/1.ts".to_string(),
            0,
        )
        .unwrap();
        assert_eq!(ch.name, "Real Channel Name");
        assert_eq!(ch.group.as_deref(), Some("News, Sports"));
    }

    /// : YENI — sorgu dizesi uzantiyi bozmamali.
    #[test]
    fn test_media_type_sorgu_dizesi() {
        assert_eq!(get_media_type("http://x/film.mp4?token=abc".to_string()), 1);
        assert_eq!(get_media_type("http://x/film.MKV".to_string()), 1);
        assert_eq!(get_media_type("http://x/canli.ts".to_string()), 0);
        assert_eq!(get_media_type("http://x/yayin.m3u8".to_string()), 0);
    }

}
