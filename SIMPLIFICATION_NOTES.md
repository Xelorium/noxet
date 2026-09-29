# Sadeleştirme, bug fix ve performans notları

Bu fork (GetX 5 RC tabanlı) yalnızca **state management + dependency injection**
kalacak şekilde sadeleştirildi, ardından bulunan bug'lar düzeltildi ve
performans iyileştirildi. Değişiklikler ayrı commit'ler halinde:

| Aşama | Commit | Konu |
|---|---|---|
| 1 | `d7a258f` | Paketin sadeleştirilmesi |
| 2 | `3189261` | Bug fix'ler + regresyon testleri |
| 3 | `a7e67f3` | Performans + benchmark |
| 4 | — | GetBuilder / Get.find iyileştirmeleri |
| 5 | — | Obx/GetX takip maliyeti, listener snapshot'ı |
| 6 | — | Sayfa state toolkit'i (PageState / PageStateMixin) |

İngilizce özet için `CHANGELOG.md` içindeki `[Unreleased]` bölümüne bakın.

## Alınan kararlar

- Dependency injection (`Get.put`, `Get.find`, `Get.lazyPut`, `Get.delete`,
  `Bind`, `Binds`, `Binding`) **kalıyor**.
- Paket adı ve public API **değişmedi**: `package:get/get.dart`, `Obx`,
  `GetBuilder`, `GetxController`, `Get.find` vb. aynı şekilde kullanılıyor.
- `StateMixin` / `GetStatus`, Rx worker'ları (`ever`, `once`, `debounce`,
  `interval`) ve `SmartManagement` tutuldu.
- `GetResponsive` çıkarıldı.
- Rx `==` / `hashCode` davranışı (asimetrik) API uyumluluğu için olduğu gibi
  bırakıldı.

## Aşama 1 — Sadeleştirme

**Silinenler:** `lib/get_navigation`, `lib/get_connect`, `lib/get_animations`,
`lib/get_utils`, `lib/route_manager.dart`, `lib/utils.dart`,
`lib/get_connect.dart`, `lib/src/responsive`, `get_responsive.dart`,
`example_nav2/`, navigasyon/animasyon/i18n/utils testleri, çeviri README'leri
ve `route_management.md` dokümanları. Toplam yaklaşık 60 bin satır.

**Kalan modüller:** `get_core`, `get_instance`, `get_rx`,
`get_state_manager`, `get_common`.

**Kopan bağımlılıkların giderilmesi:**

- `get_instance/src/extension_instance.dart`: `RouterReportManager`
  çağrıları kaldırıldı. Navigasyon olmadan hiçbir şey yapmıyorlardı; hatta
  `Get.create`/`spawn` ile üretilen her instance'ın `onDelete` referansını
  hiç temizlenmeyen bir map'te biriktiriyorlardı.
- `Equality` sınıfı `get_utils`'ten
  `get_state_manager/src/utils/equality.dart`'a taşındı.
- `GetWidget` içindeki `Get.asap` yerine `Future.delayed(Duration.zero)`.
- `Get.reset()` artık yalnızca instance'ları temizliyor
  (`clearTranslations` gitti). `clearRouteBindings` parametresi uyumluluk
  için duruyor ama etkisiz ve deprecated.
- `pubspec.yaml`: `web` ve `flutter_web_plugins` bağımlılıkları kaldırıldı.
- `example/`: `GetMaterialApp` gerektirmeyen küçük bir Obx / GetBuilder /
  StateMixin uygulaması ve testi.
- `README.md` state management + DI odaklı olarak yeniden yazıldı.

## Aşama 2 — Bug fix'ler

Her düzeltme için `test/regression/` altında test var. Bu testlerin 18'i
düzeltmelerden önceki kodda başarısız oluyor; `rx_regression_test.dart` eski
kodda derlenmiyor bile.

### Rx

- `RxList()`, `RxMap()`, `RxSet()` ve `RxList.empty()` değiştirilemez `const`
  koleksiyon sarıyordu, ilk `add` hata veriyordu.
- Rx stream'i son abone iptal edilince bir daha event göndermiyordu (ör. bir
  `ever` dispose edilip yenisi kurulunca çalışmıyordu).
- `trigger()` Obx/GetX'i yeniden çizmiyordu; ilk aynı değerde hiç
  bildirim yoktu. Setter, değeri getter üzerinden okuduğu için içinde
  bulunulan Obx'u yanlışlıkla abone ediyordu.
- `close()` iki kez çağrılınca hata veriyordu; artık idempotent ve
  `bindStream` aboneliklerini de iptal ediyor.
- Rx kapatıldıktan sonra onu okuyan Obx ekrandan kalkınca uygulama
  çöküyordu.
- `RxnDouble` üzerinde `-` toplama yapıyordu; `RxnBool ^` null değerde null
  dönmüyordu; `RxMap[]` farklı tipte anahtarla cast hatası veriyordu.
- `assignAll` listenin kendi lazy görünümüyle (`list.where(...)`) çağrılınca
  listeyi boşaltıyordu; `RxMap.assignAll` kaynak map'i paylaşıyor ve iki kez
  bildirim gönderiyordu; düz listede `assign` eski elemanları silmiyordu.
- `debounce` ve `interval` worker'ları `dispose()` sonrasında da
  tetikleniyordu.
- `MiniStream`: `cancelOnError` yok sayılıyordu, iki kez kapatmak hata
  veriyordu.

### Widget'lar

- Obx/GetX builder'ı hata fırlatırsa global takip durumu o widget'ta
  takılı kalıyordu; sonraki tüm Rx okumaları ölü widget'a abone oluyordu.
- Obx/GetX artık her build'de yalnızca o build'de okunan Rx'lere abone
  (koşullu okumalarda eski abonelikler bırakılıyor).
- Başka bir widget'ın build'i sırasında yapılan güncellemeler artık hata
  fırlatmak yerine erteleniyor.
- `Bind.builder(init:)` / `Binds` `init`'i kullanmıyordu.
- `Bind.put` otomatik silme bayrağını ters veriyordu (kalıcı olmayanlar hiç
  silinmiyordu); `Bind.spawn` hiç çalışmıyordu.
- `global: false` olan `GetX`/`Bind` aynı tipteki global instance'ı
  siliyor, kendi yerel controller'ını ise hiç kapatmıyordu.
- `GetBuilder` `id` değişince yeni id'ye abone olmuyordu.
- `GetWidget` yeni widget instance'ını takip etmiyor, eski parametrelerle
  çizmeye devam ediyordu; ayrıca `Get` içinde başıboş bir kayıt açıyordu.

### Dependency injection ve lifecycle

- `Get.putOrFind` lazy kayıtlı instance'ı `onInit` çağırmadan dönüyordu.
- Anahtar çakışması: `Foo` + tag `Bar` ile `FooBar` aynı anahtarı
  alıyordu. Yeni biçim `Tip#tag`.
- `Get.reloadAll()` ve `Get.reset()` `onClose` çağırmıyordu.
- Kapatılmış bir controller'da `onReady` yine de çalışıyordu.
- `onInit` içinden aynı controller için `Get.find` çağrısında `onInit`'in
  iki kez çalışma riski giderildi; `onInit` hata verirse instance yarım
  kalmıyor.
- `isPrepared` / `getInstanceInfo` kayıtlı olmayan tip için hata logu
  basıyordu.
- `StateMixin.futurize`: her durumda iki kez bildirim gönderiyordu, üst
  üste çağrılarda eski sonuç yenisinin üzerine yazılabiliyordu, senkron
  hatalar yakalanmıyordu.
- `ScrollMixin`: `onEndScroll`/`onTopScroll` hata verirse bir daha hiç
  tetiklenmiyordu.

## Aşama 3 — Performans

- Listener'lar sıralı bir map'te tutuluyor: abone olma, abonelikten çıkma ve
  Obx'un "zaten abone mi?" kontrolü O(n) yerine O(1).
- Bildirim her seferinde listeyi kopyalamak yerine önbelleğe alınmış bir
  snapshot'ı kullanıyor; snapshot yalnızca listener'lar değişince
  yenileniyor.
- Bir Obx/GetX build'i içinde aynı Rx tekrar tekrar okunduğunda (ör. bir
  `RxList` üzerinde döngü) takip bir kez yapılıyor.
- `RxList` (`insert`, `removeAt`, `removeLast`, `removeRange`, `setRange`,
  `setAll`, `fillRange`, `replaceRange`, `shuffle`, `clear`) ve `RxMap`
  (`addAll`, `addEntries`, `update`, `updateAll`, `removeWhere`) toplu
  işlemleri artık eleman başına değil, işlem başına bir bildirim gönderiyor.
  Örneğin 1000 elemanlı listede tek `insert` önceden 1002 bildirim
  gönderiyordu.

`test/benchmarks/notifier_benchmark_test.dart` ile ölçüm (5 çalıştırmanın en
iyisi, test modunda):

| Ölçüm | Önce | Sonra |
|---|---|---|
| 100 listener'a bildirim × 10 000 | 5272 µs | 2571 µs |
| 1000 listener'a bildirim × 10 000 | 57461 µs | 24930 µs |
| 1000 listener'ı çıkarıp yeniden ekleme | 7957 µs | 551 µs |
| Obx içinde 1000 elemanlı RxList okuma (100 listener) | 10202 µs | 126 µs |
| `RxList.removeAt(0)` × 250, 1000 eleman | 16454 µs | 1002 µs |

Tek listener'lı bildirimde anlamlı fark yok.

## Aşama 4 — GetBuilder / Get.find iyileştirmeleri

Bir önceki sürümdeki "sonraki adım önerileri"nin beşi de uygulandı. Her
düzeltmenin `test/regression/` altında testi var; `Get.find` için
`test/benchmarks/find_benchmark_test.dart` eklendi.

### 1. Build sırasında `update()`

`BindElement.getUpdate()` doğrudan `markNeedsBuild()` çağırıyordu, bu da
build sırasında "setState() or markNeedsBuild() called during build" hatası
veriyordu. Artık Obx/GetX'in kullandığı `scheduleRebuild()` üzerinden
geçiyor: build fazındaysa rebuild bir microtask'a erteleniyor ve o an widget
hâlâ mount'luysa uygulanıyor.

### 2. `Get.find` için tipli hata

Kayıtsız tip için düz `String` yerine `GetInstanceNotFoundError` fırlatılıyor.
`Error` alt sınıfı olduğu için stack trace taşıyor; `type` ve `tag` alanları
programatik olarak okunabiliyor. **Breaking:** eski `String`'i yakalayan kod
etkilenir (paket içinde iki test güncellendi).

### 3. Aynı tipe ikinci `Get.put` uyarısı

Davranış aynı kaldı (ilk instance korunuyor, ikincisi atılıyor) ama artık
debug modda `isError: true` ile log basılıyor; atılan nesnenin hiç
başlatılmadığı/kapatılmadığı sessizce geçmiyor. `Get.lazyPut`'un tekrarı
GetX'te dokümante edilmiş kasıtlı bir no-op olduğu için orada uyarı yok.

### 4. `Get.find` hızlandırma

Kayıtlar artık `'Tip#tag'` string'i yerine `(Type, String? tag)` record'u ile
anahtarlanıyor. Record'lar yapısal `==`/`hashCode` taşıdığı için çağrı başına
string üretimi tamamen kalktı; `find` ayrıca kaydı 3–4 kez aramak yerine tek
kez arayıp `_InstanceBuilderFactory`'yi aşağıya parametre olarak geçiyor
(`_initDependencies`, `_startController`). `delete`/`reload`/`markAsDirty`'nin
dokümante olarak dahili `key:` parametresi uyumluluk için duruyor: verilen
string, kayıtlar üzerinde taranarak çözülüyor (sıcak yollar bu tarafa hiç
girmiyor). `deleteAll`/`reloadAll` doğrudan record anahtarlarını kullanıyor.

`test/benchmarks/find_benchmark_test.dart` ile ölçüm ("önce" = Aşama 2,
`3189261`; 3 çalıştırma × 5 iç tekrarın en iyisi, test modunda):

| Ölçüm | Önce | Sonra | Kazanç |
|---|---|---|---|
| `Get.find<T>()` × 100 000 | 34891 µs (349 ns/çağrı) | 2212 µs (22 ns) | 15,8× |
| `Get.find<T>(tag:)` × 100 000 | 47997 µs (480 ns) | 2681 µs (27 ns) | 17,9× |
| `GetView.controller` × 100 000 | 35136 µs (351 ns) | 2537 µs (25 ns) | 13,8× |
| `Get.isRegistered<T>()` × 100 000 | 11327 µs (113 ns) | 1376 µs (14 ns) | 8,2× |
| 51 kayıt arasından `Get.find<T>()` × 100 000 | 35104 µs (351 ns) | 2458 µs (25 ns) | 14,3× |

Tag'li çağrı daha çok kazanıyor: eskiden `'Tip#tag'` interpolation'ı çağrı
başına 3–4 kez yapılıyordu, artık hiç yapılmıyor.

### 5. `updateAll()`

`update()` id'li `GetBuilder`'ları güncellemiyor (orijinal GetX davranışı,
bilinçli korundu). Yeni `GetxController.updateAll([condition])` hem id'siz
listener'ları hem de bütün id gruplarını bildiriyor. Altında
`ListNotifierGroupMixin.refreshGroupAll()` var; grup map'i bildirim sırasında
bir listener tarafından değiştirilebildiği için (`disposeId`) snapshot
üzerinde geziliyor ve kapatılmış gruplar atlanıyor.

### 6. `update()` ve `GetBuilder` maliyeti

Madde 1'in ilk hali her bildirimde `scheduleRebuild(markNeedsBuild, () =>
mounted)` çağırıyordu; iki closure allocation'ı mount edilmiş `GetBuilder`'ları
bildirme yolunu **2,3× yavaşlatmıştı**. Ölçüm bunu yakaladı ve düzeltildi:

- `scheduleRebuild(cb, cb)` yardımcısı yerine `isBuildingTree` getter'ı; her
  çağıran kendi dalını yazıyor, yani yaygın (build dışı) yolda closure
  allocate edilmiyor. `Obx`/`GetX` de aynı desene geçti.
- `BindElement.getUpdate` zaten `_dirty` ise hemen dönüyor; `ObxElement` de
  `dirty` ise. İki frame arasındaki tekrarlı `update()` çağrıları ek iş
  yapmıyor (davranış aynı: yine tek rebuild, son değerle).

`test/benchmarks/update_benchmark_test.dart` ile ölçüm ("önce" = Aşama 2;
4 çalıştırma × 5 iç tekrarın en iyisi):

| Ölçüm | Önce | Sonra | Kazanç |
|---|---|---|---|
| `update()` → 1 listener'a bildirim × 10 000 | 115 µs | 107 µs | 1,07× |
| `update()` → 100 listener × 10 000 | 3478 µs | 2089 µs | 1,66× |
| `update()` → 1000 listener × 10 000 | 34783 µs | 21539 µs | 1,61× |
| 1000 id arasından `update([id])` × 10 000 | 300 µs | 225 µs | 1,33× |
| `update()` → 1 mount'lu GetBuilder'a bildirim × 10 000 | 164 µs | 86 µs | 1,91× |
| `update()` → 20 mount'lu GetBuilder × 10 000 | 2126 µs | 539 µs | 3,94× |
| `update()` → 100 mount'lu GetBuilder × 10 000 | 10602 µs | 2626 µs | 4,04× |
| `update()` → 1 GetBuilder rebuild (pump) × 200 | 14398 µs | 13776 µs | 1,05× |
| `update()` → 20 GetBuilder rebuild × 200 | 16649 µs | 16707 µs | 1,00× |
| `update()` → 100 GetBuilder rebuild × 200 | 88316 µs | 87048 µs | 1,01× |
| `update([id])` → 100'ün 1'i rebuild × 200 | 7118 µs | 7145 µs | 1,00× |
| 1 GetBuilder mount + unmount × 50 | 13724 µs | 13884 µs | 0,99× |
| 100 GetBuilder mount + unmount × 50 | 33798 µs | 29910 µs | 1,13× |
| 100 id'li GetBuilder mount + unmount × 50 | 28404 µs | 27319 µs | 1,04× |

Okurken dikkat: **rebuild'i içeren satırlar (pump'lı olanlar) ölçüm
gürültüsünün altında.** Aynı kodu tekrar tekrar çalıştırdığımda bu satırlar
%50–100 arası oynuyor (ör. "1 GetBuilder rebuild" 14094–28905 µs), çünkü
maliyeti Flutter'ın build/layout/paint hattı belirliyor, paketin payı değil.
Bu yüzden 1,00× civarındaki değerleri "fark yok" olarak okumak gerekir, ölçülen
bir eşitlik olarak değil. Paketin kendi payını izole eden satırlar
pump'sız olanlar.

Özet: kazanç listener sayısıyla ölçekleniyor. Controller'a tek `GetBuilder`
bağlıysa fark yok denecek kadar az; kalabalık ekranlarda (20–100 abone) 2–4×;
uçtan uca kare süresinde fark ölçülemiyor çünkü orada baskın maliyet Flutter'ın
kendisi.

## Aşama 5 — Obx/GetX takip maliyeti ve listener snapshot'ı

Aşama 4'ten sonra kalan maliyeti keşif amaçlı mikro-benchmark'larla arayınca
en büyük paket kaynaklı kalem çıktı: **takip edilen (Obx/GetX) bir build'in
maliyetinin %77'si**, her rebuild'de bütün abonelikleri bırakıp yeniden
kurmaktan geliyordu. Bir Obx sürekli aynı observable'ları okuduğu için bu
tamamen boşa iş: okuma başına bir closure allocation + iki map mutasyonu.

### A. Abonelikler artık rebuild'ler arasında yaşıyor

`Obx`/`GetX` her build'de `disposers` listesini boşaltıp yeniden dolduruyordu.
Yerine yeni `TrackedBuild` sınıfı (`list_notifier.dart`) kuşak damgalı
işaretle-ve-süpür yapıyor: build sırasında okunan her observable o build'in
kuşağıyla damgalanıyor, build sonunda yalnızca damgalanmamış olanların
aboneliği bırakılıyor. Sürekli durumda (aynı observable'lar tekrar okunuyor)
hiçbir listener listesine dokunulmuyor ve hiç allocation yapılmıyor;
`endBuild` tek bir int karşılaştırmasıyla çıkıyor.

Davranış aynı kalıyor: koşullu okumada artık okunmayan Rx'in aboneliği yine
bırakılıyor, unmount'ta hepsi bırakılıyor, `Rx.bindStream` disposer'ı yine tek
build ömürlü (`extraDisposers`), builder hata fırlatırsa takip durumu yine
temizleniyor.

`_subscriptions` **kimlik tabanlı** (`HashMap.identity()`) olmak zorunda:
`Rx` `==`/`hashCode`'u değeri üzerinden override ediyor ve değeri okumak
yeni bir "okundu" bildirimi tetiklediği için normal bir map, anahtarı ararken
`markRead`'e geri özyineleniyor ve stack overflow veriyor. Bunu
`rx_regression_test.dart` içindeki "reading the same observable twice in one
build subscribes once" testi yakaladı; kimlik map'i kaldırılınca test yine
yığın taşmasıyla düşüyor.

### B. Listener snapshot'ı artımlı güncelleniyor

`_Listeners.add` her abonelikte önbelleğe alınmış snapshot'ı atıyordu, yani
bir sonraki bildirim listeyi baştan kuruyordu. Artık bildirim sürmüyorsa
snapshot'a doğrudan ekleniyor (O(1)). Bildirim sırasında gelen abonelikler
snapshot'ı geçersiz kılıyor ama uçuştaki döngü kendi yerel referansını
kullandığı için "listener'lar bildirim sırasında abone olabilir/çıkabilir"
garantisi korunuyor (`_notifying` sayacı iç içe bildirimleri de doğru
sayıyor). Silmede snapshot hâlâ atılıyor (silme seyrek).

### C. `GetBuilder` mount'unda kayıt araması 3 → 2

`BindElement.initState` `Get.isRegistered` + `Get.isPrepared` yerine mevcut
`Get.getInstanceInfo`'yu kullanıyor (tek aramada iki cevap; `get_view.dart`
zaten böyle yapıyordu). Ölçülebilir bir fark vermiyor, aşağıdaki mount satırı
gürültünün içinde kalıyor.

### Ölçüm

`test/benchmarks/tracking_benchmark_test.dart` ("önce" = Aşama 3, `a7e67f3`;
4 çalıştırma × 5 iç tekrarın en iyisi). Harness her iki ağaçta da o ağacın
`Obx`'inin gerçekten yaptığı şeyi modelliyor: takip durumu element gibi
build'ler arasında yaşıyor, her build tek-seferlik disposer'ları boşaltıyor.

| Ölçüm | Önce | Sonra | Kazanç |
|---|---|---|---|
| 1 observable okuyan takipli build | 303 ns | 53 ns | **5,7×** |
| 5 observable okuyan takipli build | 1454 ns | 207 ns | **7,0×** |
| 20 observable okuyan takipli build | 5644 ns | 748 ns | **7,6×** |
| 50 elemanlı RxList okuyan takipli build | 576 ns | 586 ns | 0,98× |
| 10 listener'a kadar iç içe abone olma + bildirim | 460 ns | 247 ns | 1,9× |
| 100 listener'a kadar | 1493 ns | 338 ns | **4,4×** |
| 500 listener'a kadar | 5785 ns | 804 ns | **7,2×** |
| 10 listener'dan iç içe abonelik bırakma + bildirim | 582 ns | 474 ns | 1,2× |
| 100 listener'dan | 1676 ns | 1030 ns | 1,6× |
| 500 listener'dan | 6181 ns | 3460 ns | 1,8× |

RxList satırının değişmemesi beklenen: `_lastRead` kısayolu aynı Rx'in
tekrarlı okunmasını zaten tek aboneliğe indiriyordu, yani orada churn hiç
yoktu.

Dürüst ölçek: 100 Obx'li bir ekran için kare başına ~26 µs, 16,6 ms bütçenin
%0,16'sı. Asıl fayda throughput değil, kare başına yüzlerce closure ve map
mutasyonunun kalkması (GC baskısı / jank).

Not: "iç içe abone olma + bildirim" ölçümü yapısı gereği O(n²) (n kez bildirim
× büyüyen n listener); B o maliyetin üstündeki sabit çarpanı kaldırıyor,
asimptotu değiştirmiyor.

### Örnek uygulama

`example/lib/phase4_demo.dart` beş maddeyi elle denemek için ayrı bir sayfa
(`Phase4DemoPage`, ana sayfadaki "GetBuilder / Get.find demo" butonundan):
build içinde `update()` çağıran bir `GetBuilder`, `GetInstanceNotFoundError`'ın
`type`/`tag`/stack trace'ini gösteren buton, ikinci `Get.put`'un yakalanmış
uyarı logu, cihaz üzerinde 100 000 `Get.find` ölçümü ve build sayaçlarıyla
`update()` / `update(['a'])` / `updateAll()` karşılaştırması. Testi
`example/test/phase4_demo_test.dart`.

`flutter run` ile denerken 4. maddenin sayılarını release modda
(`flutter run --release`) okuyun; debug modda VM yavaş olduğu için paket
benchmark'ından çok yüksek çıkar.

### Ek

`test/instance/util/matcher.dart` (vendor'lanmış `TypeMatcher` kopyası) son
kullanıcısı madde 2 ile `isA<...>()`'e geçince kaldırıldı.
## Aşama 6 — Sayfa state toolkit'i (GetBuilder + update)

`GetBuilder(init:)` + `update()` akışıyla çalışan, bir sayfanın
loading / empty / error / data durumlarını tutan ve kendi custom state'lerine
izin veren bir katman. `lib/get_state_manager/src/page_state/` altında dört
dosya, `get_state_manager.dart`'tan export ediliyor.

Pakette zaten `StateMixin`/`GetStatus` vardı ve `refresh()` ile bildirim
yaptığı için `GetBuilder` onu şimdiden dinliyordu; eksik olan altyapı değil,
bu akışa uygun katmandı: `.obx()` Obx tabanlı, `GetStatus` sealed değil
(exhaustive switch yok), `CustomStatus` payload taşımıyor ve id'li bölümler
için bir şey yok.

### Sealed hiyerarşi + genişleme noktası

`sealed class PageState<T>` altında `PageIdle`, `PageLoading`, `PageEmpty`,
`PageFailure`, `PageData` ve `PageCustomState`. Dart'ta `sealed` sınıflar
kütüphane dışından extend edilemediği için `PageCustomState` `abstract base`
olarak tanımlandı — kullanıcı kendi state'ini yazabiliyor ve `switch` yine
exhaustive kalıyor. İsimler `Page` önekli, çünkü `get.dart` toplu export
ediyor ve `Data`/`Loading` gibi adlar kullanıcı kodunda çakışırdı.

### Holder ve mixin

`PageStateHolder<T>` tek bir state'i tutup sahibini uyarıyor; `PageStateMixin`
ana sayfa için `update()`, `section(id)` için `update([id])` bağlıyor.
`load()` loading → data/empty/failure geçişini yapıyor, eski çağrının sonucunu
token ile yok sayıyor, senkron fırlatmaları yakalıyor; `retry()`,
`keepDataWhileLoading:` (pull-to-refresh) ve `mapState:` (sonucu kendi
state'ine çevirme) var. Boşluk tespiti `rx_notifier.dart`'taki `_Empty`
mantığının kopyası (orası private, test edilmiş koda dokunulmadı).

### Widget'lar

`PageStateView` ve `PageSectionView` — `GetBuilder` tabanlı, Obx yok. Sadece
`onData` zorunlu; kalan dallar `PageStateDefaults` (uygulama geneli
InheritedWidget) ve sonra sade fallback'lere düşüyor.

### Yol boyunca çıkan tuzak

Örnek sayfa yazarken uygulama **donuyordu**. Sebep: controller'da tanımlanan
`Future<void> refresh()`, `ListNotifier.refresh()`'i sessizce override
ediyordu — Dart'ta `void` top type olduğu için bu geçerli bir override — ve
`update()` → `refresh()` → `load()` → `setLoading()` → `update()` sonsuz
döngüsü oluşuyordu. Aynı tuzak `update()` için de geçerli.

Bunu bulmak yarım saat aldığı için pakete koruma eklendi: `PageStateHolder`
bildirim 20 seviye iç içe geçerse donmak yerine sebebi anlatan bir
`FlutterError` fırlatıyor. `PageStateMixin` dokümantasyonunda ve README'de de
uyarı var. İki regresyon testi (senkron ve `async` biçim) bunu kilitliyor.

## Davranışı değişen noktalar

- `Get.reset()` artık instance'ların `onClose`'unu çağırıyor (`GetxService`
  dahil).
- `global: false` olan `GetX` ve `Bind` unmount'ta kendi controller'ını
  kapatıyor.
- `Get.markAsDirty`: aynı tipin bir sonraki kaydı eski instance'ı kapatıp
  yerine geçiyor.
- Tag'li instance anahtar biçimi `Tip#tag` oldu (yalnızca `delete(key:)` /
  `reload(key:)` ile elle anahtar veren kodu etkiler).
- `RxObjectMixin.firstRebuild` ve `sentToStream` iç alanları kaldırıldı.
- Obx güncellemesi build sırasında değilse hemen işleniyor (önceden hep bir
  microtask sonraya kalıyordu).
- `Get.find` kayıtsız tip için `String` yerine `GetInstanceNotFoundError`
  fırlatıyor (Aşama 4).
- `GetBuilder`'ın güncellemesi build sırasında geldiğinde erteleniyor
  (Aşama 4).
- Aynı tipe ikinci `Get.put` debug modda uyarı logluyor (Aşama 4).
- `Obx`/`GetX` abonelikleri rebuild'ler arasında korunuyor; yalnızca son
  build'de okunmayanlar bırakılıyor (Aşama 5). Gözlemlenebilir semantik aynı,
  ama bir Rx'in listener sırası artık her rebuild'de değişmiyor.
- `NotifyData` yerini `TrackedBuild`'e bıraktı; eski API uyumluluk için
  duruyor ama `disposers` artık yalnızca tek-seferlik disposer'ları tutuyor
  (Aşama 5).

**Bilinçli olarak korunanlar:** Rx koleksiyonlar hiçbir şey değişmese de
bildirim göndermeye devam ediyor (mevcut bir test bu davranışı bekliyor);
`update()` id'li `GetBuilder`'ları güncellemiyor (orijinal GetX davranışı).

## Doğrulama

- Flutter 3.44.1 (CI ile aynı sürüm).
- `flutter analyze`: sorun yok.
- `flutter test`: 183 test geçiyor; `example/` 13 testi geçiyor.
- Aşama 4'ün regresyon testleri düzeltmelerden önceki kodda başarısız oluyor:
  üç "update during build" testi `markNeedsBuild during build` hatası,
  `updateAll` testleri derlenmiyor (metot yok), `refreshGroupAll`'un snapshot'ı
  kaldırılınca `ConcurrentModificationError`.

