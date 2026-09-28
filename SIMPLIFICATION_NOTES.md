# Sadeleştirme, bug fix ve performans notları

Bu fork (GetX 5 RC tabanlı) yalnızca **state management + dependency injection**
kalacak şekilde sadeleştirildi, ardından bulunan bug'lar düzeltildi ve
performans iyileştirildi. Değişiklikler üç ayrı commit halinde:

| Aşama | Commit | Konu |
|---|---|---|
| 1 | `d7a258f` | Paketin sadeleştirilmesi |
| 2 | `3189261` | Bug fix'ler + regresyon testleri |
| 3 | `a7e67f3` | Performans + benchmark |

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

**Bilinçli olarak korunanlar:** Rx koleksiyonlar hiçbir şey değişmese de
bildirim göndermeye devam ediyor (mevcut bir test bu davranışı bekliyor);
`update()` id'li `GetBuilder`'ları güncellemiyor (orijinal GetX davranışı).

## Doğrulama

- Flutter 3.44.1 (CI ile aynı sürüm).
- `flutter analyze`: sorun yok.
- `flutter test`: 87 test geçiyor; `example/` testi geçiyor.

## Sonraki adım önerileri (GetBuilder / Get.find odaklı)

1. Build sırasında `update()` çağrılınca `GetBuilder` "setState during build"
   hatası veriyor; Obx/GetX'teki ertelemenin aynısı uygulanmalı.
2. `Get.find` bulamazsa düz `String` fırlatıyor; tipli bir `Error`
   (stack trace ile) olmalı.
3. Aynı tipe ikinci `Get.put` sessizce yok sayılıyor ve ikinci instance
   hiç başlatılmıyor/kapatılmıyor; debug modda uyarı verilmeli.
4. `Get.find` çağrı başına yaklaşık 410 ns (tag'li ~550 ns); her çağrıda
   string anahtar üretiliyor ve kayıt 3–4 kez aranıyor. `(Type, String?)`
   anahtarı ve tek aramayla hızlandırılabilir; `GetView.controller` her
   erişimde `Get.find` çağırdığı için bu build içinde de hissediliyor.
5. `update()` id'li `GetBuilder`'ları güncellemiyor; hepsini güncelleyen
   ayrı bir `updateAll()` eklenebilir.
