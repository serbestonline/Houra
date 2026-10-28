<p align="center">
  <img src="assets/icon.png" width="150" alt="Houra simgesi">
</p>

<h1 align="center">Houra</h1>

<p align="center">
  <b>macOS için sakin, siyah-beyaz bir odak zamanlayıcısı.</b><br>
  Oturumu planla, süreyi göz önünde tut, mola gelince ekrandan uzaklaş.
</p>

<p align="center">
  <a href="README.md">English</a> · <b>Türkçe</b>
</p>

<p align="center">
  <img src="assets/flow.gif" width="880" alt="Oturum başlatma, görev bitirme ve tam ekran mola">
</p>

---

Houra üç fikir üzerine kurulu:

1. **Başlamadan karar ver.** Her oturum bir kategori, bir hedef ve istersen bugünün listesinden seçilmiş kısa bir yapılacaklar listesiyle başlar. Oturum başlayınca liste kilitlenir: yeni iş eklemek yerine planladığını bitirirsin.
2. **Süre görünsün ama önüne pencere çıkmasın.** Ekranın kenarında küçük bir etiket, şerit, kapsül, kart ya da halka durur. Üzerine gelince oturumun tamamı açılır, uzaklaşınca kapanır.
3. **Molayı gerçekten ver.** Süre dolunca bütün ekranları tam ekran bir mola kaplar. Erken dönmenin tek yolu, bilerek basılı tutulan *Acil durum* düğmesidir.

Her şey Mac'inde, yerel bir SQLite dosyasında durur. Hesap, senkronizasyon ya da izleme yoktur.

*Houra*, İngilizce *hour* (saat) kelimesinden gelir. Arayüz Türkçe ve İngilizcedir.

## Oturum

<img src="assets/new-session.png" width="380" align="right" alt="Yeni oturum penceresi">

Oturumu menü çubuğundan, panelden ya da her yerden **⌥⌘N** ile başlatırsın.

- **Kategori:** her kategorinin bir rengi ve istersen bir emojisi ya da 100 hazır ikondan biri vardır.
- **Hedef:** *Neye odaklanıyorsun?* sorusuna birkaç kelimeyle cevap verirsin.
- **Görevler:** bugünün listesinden seçersin ya da başlık ve isteğe bağlı açıklamayla yenisini yazarsın. Yeni görevler bugünün listesine de eklenir.
- **Haftanın listesi:** haftanı bir Markdown dosyasında, örneğin Obsidian'daki haftalık notunda planlıyorsan Houra oradaki açık görevleri okur, onlardan da seçebilirsin. Seçili kategorinin görevleri üstte gelir, alt görevler üst görevlerinin altında girintili durur. *Ayarlar › Haftalık görevler*'de açıp yolu verirsin; yıl, hafta ve ay (`{YYYY}`, `{WW}`, `{MM}`) ile herhangi bir klasör için `*` içerebilir, böylece hafta dönünce kendiliğinden yeni dosyaya geçer. Dosya yalnız okunur, hiçbir şey yazılmaz.
- **Ritim:** iki sabit ritim: **25 + 5** ve **50 + 10**. Ya da **serbest**: sayaç ileri akar, her 50 dakikada ekran yanıp söner ve widget mola isteyip istemediğini sorar; mola isteğe bağlıdır.

Oturum sırasında her görevin üç durumu vardır, tıklayarak değişir:

| | |
|---|---|
| 🤓 | yapılacak |
| 🙂‍↔️ | şu an yapılıyor (aynı anda tek görev) |
| 🥳 | tamamlandı |

Her oturumun bir de serbest **Notlar** alanı vardır. Görevler ve notlar oturumla birlikte saklanır, sonra *Oturumlar* sayfasında görünür.

<br clear="right">

## Ekrandaki görünümler

<p align="center">
  <img src="assets/widgets.gif" width="728" alt="Beş görünüm ve ayrıntı paneli">
</p>

Oturum sürerken Houra kalan süreyi ve üzerinde çalıştığın görevi beş görünümden birinde gösterir. *Ekranda göster* ayarından seçersin:

| Görünüm | Nasıl görünür |
|---|---|
| **Etiket** | Ekran kenarına yapışık: kategori, o anki görev ve süre; altında ince ilerleme çizgisi. |
| **İnce şerit** | Kenar boyunca 5 piksellik, aşağıdan dolan bir çizgi; süre dolumun tepesinde. |
| **Kapsül** | Görev, süre ve ilerleme halkalı bir duraklat düğmesi. |
| **Kart** | Büyük ilerleme halkalı bir kart. |
| **Halka** | İçinde süre yazan küçük bir halka. |

Görünümün **üzerine gelip kısa bir süre bekleyince** ayrıntı paneli açılır: büyük geri sayım, *Duraklat* ve *Bitir*, görev listesi, notların ve bugünün akışı. Fareyi çekince kapanır; not yazarken açık kalır.

**Basılı tutup sürükleyerek** görünümü taşırsın. Etiket ve şerit en yakın kenara (sol ya da sağ) yapışır, ayrıntı paneli de o taraftan açılır. Kapsül, kart ve halka bıraktığın yerde kalır. Konumlar hatırlanır.

<p align="center">
  <img src="assets/snap.gif" width="640" alt="Etiketi öbür kenara taşımak">
</p>

## Mola ekranı

<p align="center">
  <img src="assets/rest.gif" width="720" alt="Tam ekran mola">
</p>

Odak süresi dolunca ya da *Bitir*'e basınca bütün ekranları yavaşça akan siyah-beyaz bir sahne ve mola geri sayımı kaplar. Uygulamalar arasında geçiş bilerek kapalıdır.

Bir şey gerçekten bekleyemiyorsa **Acil durum düğmesini 1,5 saniye basılı tut**. Mola menü çubuğunda sürer, erken dönüş kaydedilir, menüden molaya geri dönebilirsin. Mola bitince Houra bir sonraki oturumu sorar.

## İstatistik

<p align="center">
  <img src="assets/stats.gif" width="1000" alt="İstatistik sayfası">
</p>

Houra'da rengin kullanıldığı tek yer burası; kategoriler böylece öne çıkar.

- **Dönem:** hafta, ay, yıl ya da takvimden seçilen herhangi bir aralık (*son 7 / 30 / 90 gün* kısayollarıyla). ‹ › ile dönemler arasında gezinirsin.
- **Özet:** önceki döneme göre değişimiyle toplam odak, günlük ortalama, tamamlanan görevler ve en iyi gün.
- **Üç grafik:**
  - **Takvim:** her gün bir kutu; odak arttıkça parlaklaşır, ince bir çizgi kategori dağılımını gösterir. Uzun aralıklarda yıllık ızgaraya dönüşür.
  - **Akış:** kategoriler zaman içinde üst üste yumuşak katmanlar halinde.
  - **Zaman haritası:** her gün bir satır, oturumlar gerçekten çalıştığın saatlerde.
- **Kategoriler:** üzerine gelince grafikte öne çıkar, tıklayınca bütün sayfa ona göre süzülür.
- **En verimli saatler:** gerçekte hangi saatlerde odaklandığını gösteren 24 saatlik şerit.
- **Gün ayrıntısı:** bir güne tıklayınca kategori dağılımı, oturumlar, ritimler ve görevler.

## Bugün, oturumlar ve kategoriler

<p align="center">
  <img src="assets/panel-today.png" width="49%" alt="Bugün sayfası">
  <img src="assets/panel-sessions.png" width="49%" alt="Oturumlar sayfası">
</p>

- **Bugün:** bugünün odağı, molaları, görevleri ve acil durumları; günün yapılacaklar listesi; oturumların dikey çizelgesi; haftalık görevler açıksa haftalık notundaki açık görevleri proje proje gösteren *Bu hafta* kartı. Bir göreve tıklayınca o görevle oturum açılır.
- **Oturumlar:** gün gün geçmiş; kategoriye ya da notlu oturumlara göre süzülür. Oturuma tıklayınca görevleri ve notları açılır.

<p align="center">
  <img src="assets/categories-picker.png" width="49%" alt="Kategoriler ve ikon seçici">
  <img src="assets/panel-settings.png" width="49%" alt="Ayarlar">
</p>

- **Kategoriler:** adı yerinde değiştirirsin. Kareye tıklayınca renk (ya da istediğin özel renk), emoji ya da Türkçe ve İngilizce aranabilen 100 [Phosphor](https://phosphoricons.com) ikonundan birini seçersin. İkonun rengini de hazır renklerden ya da istediğin özel bir renkten seçersin; seçmezsen kategori renginin açıklığına göre siyah ya da beyaz olur.
- **Ayarlar:** dil (sistem, Türkçe, English), ekrandaki görünüm, açılışta başlatma, haftalık görevleri açıp kapatma ve veriler.

### Menü çubuğu

Menü çubuğu simgesi iç içe iki kare. Oturum sırasında yalnız dış kare kalır ve süre ilerledikçe kendini çizer; yanında kalan süre yazar. Molada mola geri sayımını gösterir. Menüden oturum başlatabilir, son oturumlardan birini tekrarlayabilir, duraklatıp bitirebilir, görünümü değiştirip paneli açabilirsin.

## Kurulum

### İndirerek

1. [Son sürümden](https://github.com/serbestonline/Houra/releases/latest) **`Houra-<sürüm>.dmg`** dosyasını indir.
2. Aç ve **Houra**'yı **Applications** klasörüne sürükle.
3. Houra'yı aç. Menü çubuğunda durur; paneli açana kadar Dock'ta görünmez.

**macOS 13 veya üstü** gerekir. Apple Silicon ve Intel Mac'lerde yerel çalışır.

> **İlk açılış:** Houra Apple tarafından onaylanmadığı (notarize edilmediği) için macOS ilk açılışta uygulamayı doğrulayamadığını söyler. **Sistem Ayarları › Gizlilik ve Güvenlik**'e git, aşağı kaydır ve **Yine de Aç**'a tıkla. Bunu bir kez yapman yeter.
> Ya da Terminal'de karantina işaretini kaldır: `xattr -dr com.apple.quarantine /Applications/Houra.app`

### Kaynaktan derleme

Gerekenler: macOS 13 veya üstü ve Xcode Command Line Tools. Xcode projesi ya da dış bağımlılık yoktur.

```bash
xcode-select --install          # Command Line Tools kurulu değilse

git clone https://github.com/serbestonline/Houra.git
cd Houra
./build.sh --install            # derler ve ~/Applications altına kurar
open ~/Applications/Houra.app
```

| Komut | Sonuç |
|---|---|
| `./build.sh` | Evrensel `build/Houra.app` derler (Apple Silicon + Intel) |
| `./build.sh --install` | Ayrıca `~/Applications` altına kurar |
| `./build.sh --dmg` | Ayrıca sürükle-bırak kurulumlu `build/Houra-<sürüm>.dmg` üretir ([uv](https://docs.astral.sh/uv/) gerekir) |

## Klavye kısayolları

| Tuş | İşlev |
|---|---|
| `⌥⌘N` | Her yerden yeni oturum |
| `⌘N` | Yeni oturum (menü) |
| `⌘.` | Duraklat / devam et (menü) |
| `⌘P` | Paneli aç (menü) |
| `⌘,` | Ayarlar (menü) |
| `Return` | Yeni oturum penceresinde oturumu başlat |
| `Esc` | Yeni oturum penceresini kapat |

## Veriler

Kategoriler, görevler, oturumlar ve notlar tek bir SQLite dosyasında durur:

```
~/Library/Application Support/Houra/houra.sqlite
```

Hiçbir şey Mac'inden dışarı çıkmaz. *Ayarlar*'dan dosyayı Finder'da gösterebilir ya da bütün oturumları CSV olarak dışa aktarabilirsin. Oturum ortasında Houra'yı kapatırsan oturum, uygulama bir sonraki açılışında planlanan süresiyle kapatılır.

## Geliştirme

Kod `Sources/` altında düz Swift'tir (AppKit + SwiftUI). Kendi testini `build/Houra.app/Contents/MacOS/Houra --selftest` ile çalıştırırsın. README'deki görseller örnek veriyle uygulamanın kendisi tarafından üretilir: `./scripts/make_media.sh`. Houra yalnız kendi pencerelerini yakaladığı için ekran kaydı izni gerekmez.

## Teşekkür

- İkonlar: [Phosphor Icons](https://phosphoricons.com) (MIT), [Iconify](https://iconify.design) üzerinden.

## Lisans

MIT
