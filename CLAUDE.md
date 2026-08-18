# CLAUDE.md — Guía del proyecto para agentes de IA

> **Contexto obligatorio.** Este repositorio es una **plantilla base (Base Starter Template)** de Flutter para publicar apps Android en Google Play con monetización freemium (AdMob + IAP "quitar anuncios").
>
> La fuente de verdad arquitectónica es `GUIA_ESTANDAR_FLUTTER_ANDROID.md` (documento del usuario, fuera del repo). Este archivo explica **qué** hay implementado, **cómo** funciona y **por qué** se decidió así. Ante cualquier duda o conflicto, manda la guía estándar.

---

## 0. Reglas no negociables

1. **Stack fijo:** Flutter stable, Dart 3.x, target **Android**. iOS no se implementa salvo orden explícita.
2. **Nunca fijar versiones de paquetes de memoria.** Usar `flutter pub add <paquete>` para que pub resuelva la última estable compatible.
3. **Ninguna dependencia nueva sin justificación** de peso e impacto en el arranque, escrita en el `pubspec.yaml`.
4. **Idioma:** código y comentarios en **inglés**; UI en **español + inglés** (archivos `.arb`).
5. **Antes de cerrar cualquier tarea**, en este orden:
   ```bash
   dart format lib test && flutter analyze && flutter test
   ```
   `flutter analyze` debe terminar con *No issues found!*.
6. **Prohibido:** `print`, `setState` en widgets con lógica no trivial, `FutureBuilder` anidado, JSON pesado en el isolate principal, imágenes sin `cacheWidth`/`cacheHeight`, `ListView(children: [...])` con colecciones dinámicas.
7. **`const` siempre que sea posible.**

---

## 1. Arquitectura

**Clean Architecture simplificada de 3 capas + feature-first.**

```
lib/
├── main.dart                 # solo llama a bootstrap(); sin lógica
├── bootstrap.dart            # init asíncrono dentro de runZonedGuarded
├── app.dart                  # MaterialApp.router (tema + rutas + l10n)
├── core/
│   ├── config/               # AppConfig, AdConfig, BillingConfig
│   ├── theme/                # colores, spacing, ThemeData, ThemeModeController
│   ├── routing/              # go_router: rutas y navigator key
│   ├── errors/               # AppException sellada
│   ├── extensions/           # BuildContextX (theme, l10n, snackbars)
│   ├── utils/                # AppLogger
│   └── widgets/              # BaseScreen, AdaptiveBannerAd, SectionCard,
│                             # EmptyState, ErrorView, AppLoader,
│                             # PermissionFlow (diálogos de permisos)
├── features/
│   ├── bluetooth_finder/     # ⭐ FEATURE PRINCIPAL — radar RSSI (ver §1.1)
│   │   ├── data/             # BluetoothScanService, GeigerSounder,
│   │   │                     # advertisement_mapper (plugin → dominio)
│   │   ├── domain/           # DiscoveredDevice, Proximity, ScanFilter,
│   │   │                     # DeviceIdentity + BluetoothRegistry (ver §1.2),
│   │   │                     # FavoriteDevice (ver §1.3)
│   │   └── presentation/     # ScannerScreen (home), RadarScreen, providers
│   ├── home/presentation/    # feature de ejemplo de la plantilla (HUÉRFANA:
│   │                         # ya no está enrutada, ver §1.1)
│   ├── settings/presentation/
│   └── premium/presentation/ # paywall
├── services/
│   ├── ads/                  # AdsService + ConsentService (UMP) + providers
│   ├── billing/              # PremiumService + PremiumController + estado
│   ├── permissions/          # PermissionService + providers
│   ├── review/               # ReviewService + providers
│   └── storage/              # KeyValueStore (prefs) + SecureStore + providers
└── l10n/                     # app_es.arb (plantilla) + app_en.arb
```

**Regla de dependencia:** `presentation` → `domain` → `data`. `domain` no conoce a nadie.
**`domain/` solo se crea cuando la feature tiene lógica de negocio real.** Las features de la plantilla son triviales, por eso solo tienen `presentation/`. No crear carpetas vacías.

**Cada feature es autocontenida y borrable.** Si un helper solo lo usa una feature, vive dentro de esa feature, nunca en `core/utils/`.

---

## 1.1 Feature principal — `bluetooth_finder` (radar RSSI)

Localizador de audífonos y dispositivos Bluetooth. Es la única feature con las
tres capas (`data` / `domain` / `presentation`), porque es la única con lógica
de negocio real.

**La ruta `/` apunta a `ScannerScreen`,** no a la `HomeScreen` de la plantilla.
`lib/features/home/` quedó huérfana (no la importa nadie): es andamiaje de
demo y puede borrarse. Sus integraciones (interstitial tras acción de valor y
`requestReviewAfterSuccess`) ya están portadas a esta feature.

### Rutas

| Ruta | Pantalla |
|---|---|
| `/` | `ScannerScreen` — favoritos + lista de dispositivos, botón Escanear/Detener en la AppBar, banner |
| `/radar/:deviceId` | `RadarScreen` — radar animado + sonido Geiger |

`AppRoutes.radarDeviceIdParam` es el id (MAC en Android, UUID en iOS). El radar
**no** recibe el dispositivo por `extra`: lo relee del stream por id, porque la
lectura tiene que seguir cambiando mientras el usuario camina.

**El radar se garantiza su propio escaneo.** Entrar a un dispositivo es pedir una
lectura fresca *de ese* dispositivo, así que `RadarScreen` arranca el escaneo si
estaba detenido (con la misma secuencia agrupada de permisos que el botón) y lo
vuelve a detener al salir, por las dos salidas: la flecha y el back del sistema.

Decisiones que conviene no deshacer:

- **`_RadarBacking` distingue "hay escaneo" de "hay lectura".** El servicio
  reemite el último paquete a cada nuevo oyente — eso es lo que evita que la
  lista se quede en blanco al volver del radar — pero ese paquete es de *antes*
  de pulsar Detener. Pintarlo dejaba un porcentaje con pinta de vivo que no se
  movía nunca. Con el escaneo parado o imposible (permisos denegados, radio
  apagada) la lectura se descarta: 0 %, radar inactivo y mensaje.
- **El sonido se silencia con la lectura.** Un tren de clics al último
  `closeness` conocido es la mitad audible del mismo engaño, y por eso encender
  el sonido sin señal tampoco suena.
- **Tres estados de texto, no dos**: `radarSearching*` mientras se reanuda el
  escaneo y `radarSignalLost*` («puede estar apagado… asegúrate de que está
  encendido») cuando ya se le dio la oportunidad de contestar. Acusar de apagado
  a un dispositivo al que aún no se ha escuchado es dar por perdido lo que el
  usuario está buscando.

### `BluetoothScanService` (`data/`)

Envuelve `flutter_blue_plus`; lógica pura, **sin `BuildContext`** (los permisos
los pide `ScannerScreen` con `PermissionFlow.ensureAll` antes de llamar a
`start()`, igual que la separación `PermissionService` / `PermissionFlow`).

| Decisión | Por qué |
|---|---|
| `continuousUpdates: true`, `continuousDivisor: 1` | Sin esto el plugin reporta cada dispositivo **una vez** y el radar se congela en la primera lectura |
| `removeIfGone: 12 s` | La lista refleja la realidad sin parpadear por paquetes perdidos |
| `androidUsesFineLocation: false` | La ubicación ya se pidió agrupada con Bluetooth; dejar que el plugin la pida otra vez sería un segundo diálogo fuera de contexto |
| Media móvil (EMA, factor 0,35) en el servicio | El RSSI crudo oscila 10-15 dBm en reposo. Se suaviza **una vez** en el servicio, así lista y radar comparten el mismo valor |
| Escaneo detenido en `onPause` (`AppLifecycleListener`) | Un scan `lowLatency` es de lo más caro que puede hacerle una app a la batería |

> ⚠️ **Solo BLE.** `flutter_blue_plus` escanea *Low Energy*; no hay API para leer
> el RSSI de un descubrimiento clásico (BR/EDR). Los auriculares modernos
> anuncian por BLE aunque el audio vaya por clásico, que es lo que hace que el
> radar funcione con ellos. Un manos libres solo-clásico **no** aparecerá.

> ⚠️ **`flutter_blue_plus` está fijado a `1.36.8` a propósito.** La 2.0.0 abandonó
> BSD-3 por una licencia que exige pago para uso comercial (esta app lo es). No
> subir a `^2` sin comprar la licencia. Ver el comentario en `pubspec.yaml`.

## 1.2 Identificación de dispositivos (`domain/device_identity.dart`)

Cada anuncio BLE se traduce a un `DeviceIdentity`: **qué** es el dispositivo, de
**quién** es la marca, **cuánta** batería anuncia y qué sabe hacer. Es lo que
alimenta el icono, el nombre y los chips de cada fila.

**Regla de privacidad del feature:** la lista muestra hechos accionables y
**nunca los identificadores que hay debajo**. La MAC / UUID (`DiscoveredDevice.id`)
sirve para enrutar al radar y para keyear la lista, y **no se pinta en ninguna
pantalla**. Tampoco se exponen payloads crudos ni identificadores rotatorios: son
números largos que no le dicen nada a una persona.

| Archivo | Qué hace |
|---|---|
| `domain/advertisement_facts.dart` | Vista del anuncio **sin tipos del plugin** (DTO de entrada). No incluye la dirección: así no puede filtrarse a la UI por accidente |
| `data/advertisement_mapper.dart` | Único sitio que toca `AdvertisementData` de `flutter_blue_plus`. Descarta los UUID de 128 bits (privados, no etiquetables) |
| `domain/bluetooth_registry.dart` | Tablas curadas: company IDs → marca, appearance GAP → categoría, UUIDs de servicio → categoría/rasgo, modelos Apple, palabras clave del nombre |
| `domain/device_identity.dart` | Resuelve y fusiona la identidad |
| `domain/device_taxonomy.dart` | `DeviceCategory` (19) y `DeviceTrait` |
| `presentation/widgets/device_identity_view.dart` | Icono, etiquetas y chips. Única fuente de verdad de cómo se llama un dispositivo |

**Orden de resolución de la categoría** (de más fiable a menos, en
`DeviceIdentity.resolve`). No reordenar sin motivo:

1. **Appearance GAP** — valor que el fabricante eligió de la lista del SIG.
2. **Manufacturer data** — Apple y Microsoft describen sus propios dispositivos.
3. **UUIDs de servicio** — estándar, pero cada dispositivo anuncia lo que quiere.
4. **Nombre anunciado** — heurística, por eso va última.

Decisiones que conviene no deshacer:

- **`mergedWith` hace la identidad "pegajosa".** BLE reparte la descripción entre
  el anuncio y el scan response, que llegan en paquetes distintos: resolver cada
  paquete aislado haría parpadear la fila entre dos medias identidades. Los
  valores conocidos se mantienen y los rasgos se acumulan; un escaneo nuevo
  parte de cero.
- **Los fabricantes de chips están excluidos de la tabla de marcas** (CSR,
  Realtek, Bluetrum, Actions). Es el chip de dentro, no la marca de la caja:
  etiquetar unos auriculares genéricos como "Qualcomm" sería mentir con
  seguridad.
- **Find My nunca pisa una categoría ya resuelta.** Un AirPod perdido emite en la
  red Find My exactamente igual que un AirTag, y sigue siendo un auricular.
- **La batería solo sale del Battery Service estándar** (`0x180F`). Apple cifra
  parte del registro de batería en firmware reciente: un porcentaje equivocado es
  peor que ninguno.
- **Los IDs de modelo de Apple no son públicos.** La tabla es la comunitaria y se
  limita a los modelos con consenso amplio; lo que no reconoce degrada a
  "Auriculares de Apple", nunca a un nombre incorrecto. **Verificar contra
  hardware real antes de ampliarla.**
- **`ScanFilter.hideUnidentified` sustituyó a `hideUnnamed`.** Unos AirPods en su
  estuche cerrado emiten sin nombre pero sí identifican su modelo: ocultarlos
  rompería el caso de uso principal. A la inversa, marca sola **no** basta
  (`isIdentified`): todos los iPhone de la sala anuncian "Apple" y nada más.

### La pantalla principal

- **El escaneo se controla desde la AppBar** (lupa Bluetooth ⇄ stop). Mientras la
  lista está vacía hay además un botón grande en el centro, que es donde el
  usuario está mirando; en cuanto arranca el escaneo desaparece con su texto y
  solo queda el indicador de carga, porque la invitación ya se aceptó.
- **Con el escaneo detenido no hay lectura en ninguna fila.** El servicio sigue
  reemitiendo el último paquete —eso es lo que evita que la lista se vacíe al
  volver del radar—, pero es de antes de pulsar Detener: las filas se quedan
  (siguen siendo la forma de reabrir lo que acabas de ver, y abrirlo re-escanea,
  §1.1) y pierden el porcentaje, el indicador de señal y los chips. Es la misma
  regla del radar aplicada a la lista: **lo que un dispositivo *es* sobrevive al
  silencio; lo que se *oye* de él, no.**
- **Todas las filas miden lo mismo, tengan chips o no.** La línea de chips se
  reserva siempre (`deviceMetaChipHeight`), y cuando no hay nada que poner ahí
  va un `DeviceMetaChip` sin tinta, **no** un hueco vacío.

  > ⚠️ La razón no es el alto del hueco, es la **línea base**: `ListTile` coloca
  > título y subtítulo a partir de sus baselines, y un subtítulo sin texto no
  > tiene ninguna. El fallback (su alto completo) los junta hasta que el tile se
  > pasa a su *layout* compacto —`2·padding + título + subtítulo` en vez de los
  > 88 dp— y esa era exactamente la tarjeta más baja que aparecía en las filas
  > sin chips. Un `SizedBox` de la misma altura **no** lo arregla.

- **La barra de filtros es una sola fila que se desplaza**, no un `Wrap`: una
  segunda línea de chips empuja la lista hacia abajo justo en los móviles que
  menos alto tienen. Al tocar un chip se le hace `Scrollable.ensureVisible`
  **después del frame** — el chip cambia de ancho al ganar o perder su marca de
  selección, y centrarlo en su posición anterior lo dejaría cortado por esa
  misma diferencia.

### Conversión RSSI → cercanía (`domain/proximity.dart`)

Rango útil **-100 dBm → -30 dBm** mapeado a 0-100 %. **No se muestra distancia en
metros**: el RSSI depende de cuerpos, paredes y potencia del emisor, así que se
enseña una cercanía relativa que el usuario "escala" caminando.
Bandas: `far` (<40 %) rojo, `near` (40-72 %) ámbar, `veryNear` (≥72 %) verde,
resueltas en un solo sitio (`proximityColor` en `signal_strength_icon.dart`).

### Sonido Geiger (`data/geiger_sounder.dart`)

`audioplayers` con un asset WAV **sintético** generado por script
(`dart run tool/generate_audio_assets.dart`) — no hay binarios opacos en el repo.

- **Clics**: intervalo de 1100 ms a 90 ms según cercanía, en curva (el oído
  resuelve mejor los cambios en un tren rápido que un cambio de volumen).
  `PlayerMode.lowLatency` → SoundPool en Android, imprescindible para repetir
  cada 90 ms.

> El **tono continuo** de rewarded se eliminó: el vídeo recompensado paga ahora
> el alta de un favorito (§1.3), que es una recompensa que el usuario entiende
> sin explicación y que le sigue sirviendo mañana. Con él se fueron
> `assets/audio/tone.wav`, el segundo `AudioPlayer` y
> `continuous_mode_controller.dart`.

> ⚠️ **Dos trampas de `audioplayers` que dejan el radar mudo sin dar ningún error:**
>
> 1. **Nunca `seek()` sobre el reproductor de clics.** En `PlayerMode.lowLatency`
>    el backend es SoundPool, que no emite `onSeekComplete`: el `Future` se queda
>    colgado hasta el timeout de 30 s del plugin y el clic no suena jamás. Para
>    repetir el disparo va `stop()` y luego `resume()` — SoundPool tampoco emite
>    evento de fin, así que el plugin sigue creyendo que reproduce y **ignora** un
>    `resume()` suelto.
> 2. **Toda llamada al plugin va serializada** en una única cola (`_enqueue`). Son
>    asíncronas: si una transición pausa el tono mientras la siguiente lo arranca,
>    la pausa puede llegar después y lo apaga.
>
> El contexto de audio es `mixWithOthers`: con el foco por defecto, el `stop()` de
> cada clic lo abandonaría once veces por segundo y el audio ajeno haría duck.

### Monetización enganchada aquí

- **Banner:** `ScannerScreen` usa `BaseScreen` con `showBanner: true` (pantalla de
  lista → placement permitido). `RadarScreen` lleva `showBanner: false`.
- **Rewarded:** alta de un favorito (§1.3). La recompensa se concede **solo**
  dentro de `onUserEarnedReward`.
- **Interstitial:** al salir del radar con la flecha de la AppBar (transición
  natural). El back del sistema **no** lo dispara, para no romper la animación de
  *predictive back*.
- **Reseña:** al alcanzar la banda `veryNear` — el usuario acaba de encontrar lo
  que había perdido. Una vez por pantalla, nunca tras un error.

---

## 1.3 Favoritos

Dispositivos que el usuario ancla arriba del todo de la lista. El caso de uso es
el del auricular **apagado o fuera de alcance**: el que hay que encontrar es
justo el que no se oye, así que un favorito **se pinta siempre**. Sin lectura, su
icono de categoría se sustituye por un Bluetooth tachado y la fila se queda sin
chips: es el mismo hecho dicho en el sitio donde ya se está mirando, y vuelve al
icono de siempre en cuanto se le oye.

| Archivo | Qué hace |
|---|---|
| `domain/favorite_device.dart` | El modelo y su (de)serialización a JSON |
| `presentation/providers/favorites_controller.dart` | Lista persistida + `isFavoriteProvider` |
| `presentation/widgets/favorite_device_tile.dart` | Fila que se suscribe al stream por id |
| `presentation/widgets/device_tile.dart` | Fila común: acepta `device: null` = fuera de alcance |

Decisiones que conviene no deshacer:

- **Alta con vídeo recompensado, baja gratis.** El diálogo lo avisa antes de
  lanzar el anuncio y la recompensa se concede **solo** en `onUserEarnedReward`.
  Premium se salta el vídeo (pagó por no ver anuncios) y `AdShowResult.disabled`
  también concede: si los anuncios están apagados para ese usuario, cobrarle uno
  sería una puerta cerrada. `notReady` **no** concede — hay inventario, solo está
  frío — y muestra el snackbar de siempre.
- **El favorito se puede renombrar, y solo el favorito.** Dos auriculares del
  mismo modelo anuncian la misma cadena, así que el nombre anunciado es justo lo
  que no distingue el tuyo. `customName` es lo único de esta feature que escribe
  el usuario: gana a cualquier nombre resuelto (`deviceDisplayName`, que sigue
  siendo la única fuente de verdad), **sobrevive a un re-pin** (`add` lo relee
  antes de refrescar la descripción) y se borra dejando el campo vacío. Un
  dispositivo no anclado no tiene dónde guardarlo, y por eso no se ofrece.
- **Las dos acciones viven tras una pulsación larga**, en un `SimpleDialog`:
  «Editar nombre» y «Quitar favorito», y la segunda entra en el aviso de siempre
  (volver a anclarlo cuesta otro vídeo). La fila no gasta espacio en controles
  que se usan una vez cada mucho, y una acción destructiva pegada al área que se
  toca para abrir el radar es como se pierde un favorito sin querer.
- **El radar titula con el nombre elegido** (`favoriteCustomNameProvider`, en
  `watch`): si al abrirlo volviera al nombre anunciado, renombrar no habría
  servido para nada.
- **El favorito guarda su propia descripción,** no solo el id: sin anuncio no hay
  identidad que resolver y la fila quedaría como «Dispositivo Bluetooth». Se
  guarda solo la mitad estable de `DeviceIdentity` (nombre, modelo, marca,
  categoría); batería, rasgos y `connectable` describen **ese** paquete, y un
  «80 %» junto a un dispositivo que nadie oye sería mentira.
- **La lectura viva gana campo a campo** (`favorite.identity.mergedWith(live)`),
  no en bloque: los primeros paquetes de un escaneo nuevo llegan anónimos y la
  fila parpadearía al nombre genérico.
- **La categoría se serializa por `name`, nunca por índice.** La taxonomía va a
  crecer y un índice reetiquetaría en silencio todo lo guardado.
- **Un favorito no aparece dos veces:** `unpinnedDevicesProvider` lo quita de la
  lista de abajo. Y la sección de favoritos se construye desde el almacén, no
  desde `visibleDevicesProvider`, que es lo que le permite enseñar un dispositivo
  que los filtros habrían descartado.
- **El id (MAC/UUID) sigue sin pintarse en ninguna pantalla.** Se persiste en
  `shared_preferences` (almacenamiento privado de la app) porque es la única
  forma de reconocer el dispositivo en el siguiente escaneo.

---

## 2. Gestión de estado — Riverpod

Estándar único: **Riverpod 3** (`flutter_riverpod`).

| Necesidad | Provider a usar |
|---|---|
| Servicio / dependencia | `Provider` |
| Estado síncrono mutable | `NotifierProvider` |
| Estado asíncrono mutable | `AsyncNotifierProvider` |
| Lectura asíncrona de solo lectura | `FutureProvider` (con `isAutoDispose: true`) |

Convenciones aplicadas en el repo:

- **Estados de UI con `sealed class`**, nunca booleanos sueltos. Ver `services/billing/premium_state.dart` (`PurchaseFlow` → `PurchaseIdle` / `PurchasePending` / `PurchaseFailed`). La dimensión carga/error la aporta `AsyncValue`.
- **`ref.read` dentro de callbacks; `ref.watch` solo en `build`.** Ejemplo: `AdsService` recibe `isPremium: () => ref.read(isPremiumProvider)`.
- **`select` para observar solo lo que se pinta**: `homeControllerProvider.select((s) => s.credits)`.
- **`autoDispose`**: en Riverpod 3 se activa con `isAutoDispose: true`. Los providers de servicios (`adsServiceProvider`, `premiumControllerProvider`, `routerProvider`) son **keepAlive a propósito** y cada uno lleva el comentario que lo justifica (mantienen anuncios precargados, la suscripción al `purchaseStream` y la pila de navegación).

### ⚠️ Desviación conocida: sin `riverpod_generator` / `riverpod_lint`

La guía pide codegen con `build_runner`. **No se pudo instalar**: con Flutter 3.44.9 / Dart 3.12.2, `riverpod_generator` y `riverpod_lint` exigen versiones de `analyzer` incompatibles con las que `flutter_test` fija (`matcher` / `test_api`), y `pub` no resuelve.

Por eso **los providers están escritos a mano** con la API declarativa de Riverpod 3, que es equivalente y totalmente soportada. Cuando el ecosistema se actualice:

```bash
flutter pub add dev:build_runner dev:riverpod_generator dev:riverpod_lint dev:custom_lint
```

y migrar los providers a `@riverpod`. Añadir entonces `custom_lint` al `analysis_options.yaml`.

---

## 3. Monetización

### 3.1 Modelo económico

- Núcleo gratuito completo y usable (apps de "funcionalidad mínima" se retiran).
- **Rewarded = formato principal** (mayor eCPM, aceptación voluntaria).
- **Interstitial = secundario**, solo en transiciones naturales.
- **Banner = opcional**, solo en pantallas de lista/consulta.
- **IAP no consumible "quitar anuncios"** = conversión principal.

### 3.2 AdMob (`google_mobile_ads`)

**IDs.** `core/config/ad_config.dart` mantiene dos juegos: los **IDs oficiales de prueba de Google** y los de producción (ya rellenos). La selección es automática:

```dart
AppConfig.useProductionAds  // == kReleaseMode
```

Un ID vacío **desactiva** ese formato en vez de romper (`canShowBanner` /
`canShowInterstitial` / `canShowRewarded`, que devuelven `disabled`, no
`notReady`).

> ⚠️ **El App ID es la excepción y conviene entender por qué.** Vive en
> `AndroidManifest.xml`, que **no** puede conmutar según el modo de build, así
> que el de producción (`ca-app-pub-4073049276319773~8873347767`) va en **todos**
> los builds, debug incluido. Es el montaje que documenta Google y es seguro
> *porque* los unit id sí conmutan: un debug se identifica con la app real pero
> solo pide creatividades de prueba.
>
> Lo que sí banea cuentas es un build **release** en el móvil del desarrollador
> con anuncios reales en pantalla. Antes de hacer eso, meter el dispositivo en
> `AdConfig.testDeviceIds` (el id sale en logcat en la primera petición).

**`AdsService` (`services/ads/ads_service.dart`)** — punto único de entrada. Se llama `AdsService` porque así lo nombra la guía estándar; existe el alias `typedef AdService = AdsService` para quien busque ese nombre. Responsabilidades:

| Regla | Dónde |
|---|---|
| Premium nunca ve anuncios | `adsEnabled` (getter del servicio, **no** en cada pantalla) |
| Consentimiento antes del primer anuncio | `initialize()` llama a `ConsentService.gatherConsent()` |
| Interstitial cada N acciones **y** con intervalo mínimo | `registerActionAndMaybeShowInterstitial()` |
| Caducidad ~1 h de anuncios full screen | `_isExpired()` + `AppConfig.fullScreenAdTtl` |
| Reintentos con backoff exponencial (4s, 8s, 16s, 32s, máx. 4) | `_scheduleRetry()` |
| Precargar el siguiente rewarded al cerrar uno | `onAdDismissedFullScreenContent` |
| Nunca bloquear al usuario por falta de inventario | devuelve `AdShowResult.notReady`; la UI degrada |

**Pacing del interstitial:** deben cumplirse **las dos** condiciones —
`AppConfig.interstitialEveryNActions` (3) **y** `AppConfig.minIntervalBetweenInterstitials` (3 min).
No añadir atajos que salten el pacing.

**Flujo rewarded correcto** (implementado en `features/home/.../rewards_card.dart`):
1. Diálogo previo explicando la recompensa → el usuario acepta.
2. `AdsService.showRewarded(...)`.
3. La recompensa se entrega **solo** dentro de `onUserEarnedReward`.
4. Se persiste inmediatamente (`HomeController.addCredits`).
5. Si no hay anuncio → snackbar informativo, nunca un callejón sin salida.

**Consentimiento (UMP).** `services/ads/consent_service.dart` usa el UMP SDK que ya incluye `google_mobile_ads` (sin dependencia extra):
`requestConsentInfoUpdate` → `loadAndShowConsentFormIfRequired` → `canRequestAds()`.
En Ajustes hay una fila **"Opciones de privacidad"** que reabre el formulario, visible solo cuando `getPrivacyOptionsRequirementStatus() == required`.

**Banner.** `AdaptiveBannerAd` (anchored adaptive, no 320x50 fijo) se coloca desde `BaseScreen` **debajo** del contenido, nunca superpuesto. Si no hay anuncio o el usuario es premium ocupa **cero** altura.

> ⚠️ **El banner viaja en `bottomNavigationBar`, no en un `Column` bajo el body.**
> Un `FloatingActionButton` se posiciona a partir de la geometría del `Scaffold`,
> y esa geometría **solo** descuenta la barra inferior. Con el banner dentro del
> body, el FAB flotaba **encima** del anuncio y dejaba el dedo a un resbalón de
> un clic accidental — que es exactamente lo que suspende cuentas de AdMob.
> `ScannerScreen` ya no tiene FAB (el control de escaneo está en la AppBar,
> junto a los resultados y lejos del anuncio), pero la regla sigue en pie para
> cualquier pantalla que añada uno. Si algún día hay `bottomBar`, va debajo del
> banner dentro del mismo slot.
Poner `showBanner: false` en pantallas con controles densos, formularios, onboarding o acciones destructivas cerca del borde inferior (así están `SettingsScreen` y `PaywallScreen`).

**Mediación:** no activarla en el lanzamiento. A partir de ~10k usuarios activos, 2–3 redes.

### 3.3 IAP (`in_app_purchase`)

- Producto **gestionado no consumible**: `premium_remove_ads` (`core/config/billing_config.dart`). Debe existir y estar **activo** en Play Console y requiere una versión subida a un canal de pruebas.
- `PremiumService` = plomería del store; `PremiumController` (`AsyncNotifier`) = estado.
- **`purchaseStream` se escucha desde el arranque**, no desde el paywall: una compra puede completarse fuera de la sesión.
- **`completePurchase()` siempre**, incluso en compras rechazadas o con error: si no, Google reembolsa automáticamente a los 3 días.
- Entitlement cacheado en `flutter_secure_storage` + `restorePurchases()` al arrancar para verificar contra el store. Nunca confiar solo en un flag de `shared_preferences`.
- **Botón "Restaurar compras" obligatorio y visible** en Ajustes (y también en el paywall). Su ausencia es motivo de rechazo.
- Verificación local del token (app sin backend). Con servidor: validar contra la Google Play Developer API en `PremiumService.isValidPurchase`.
- **Paywall tras un momento de valor**, nunca en el primer arranque. Puntos de entrada: enlace discreto en Home, fila en Ajustes, deep link `buscaraudifonos://premium`.

### 3.4 Política

- **Data Safety form** debe declarar exactamente lo que recogen AdMob y los SDKs (ID de publicidad, datos de uso). Declaración incompleta = rechazo.
- El permiso `com.google.android.gms.permission.AD_ID` está declarado explícitamente en el manifiesto para que no se olvide en el formulario.
- Si la app se dirige a menores: poner `AdConfig.isChildDirected = true` y aplicar Families Policy.

---

## 4. Permisos (`permission_handler`)

`services/permissions/permission_service.dart` es **lógica pura sin `BuildContext`**; los diálogos viven en `core/widgets/permission_dialogs.dart` (`PermissionFlow`). Esta separación permite testear el servicio y llamarlo desde código en background.

- Enum propio `AppPermission` (bluetoothScan, bluetoothConnect, location, notifications) para que el plugin no se filtre a la UI y para que añadir un permiso sea una decisión consciente.
- Resultado normalizado `PermissionOutcome`: `granted` / `denied` / `permanentlyDenied` / `unsupported`.
- `PermissionFlow.ensure(...)`: comprueba → muestra explicación si el SO lo pide (`shouldShowRequestRationale`) → solicita → si está bloqueado permanentemente ofrece **abrir ajustes**.
- `PermissionFlow.ensureAll(...)`: para grupos que van juntos (Bluetooth scan + connect) — una sola explicación y una sola secuencia de diálogos, porque encadenar diálogos dispara la tasa de rechazo.
- **Nunca pedir permisos al arrancar.** Siempre tras un toque explícito del usuario.
- Manifiesto: `BLUETOOTH_SCAN` con `usesPermissionFlags="neverForLocation"` (quitarlo solo si la app deriva ubicación de dispositivos cercanos) y `BLUETOOTH`/`BLUETOOTH_ADMIN` con `maxSdkVersion="30"` para Android 11 e inferiores.
- `ACCESS_BACKGROUND_LOCATION` **no** está incluido: requiere revisión adicional en Play Console.

---

## 5. Reseñas in-app (`in_app_review`)

`services/review/review_service.dart`. Google limita el diálogo silenciosamente: si se gasta la cuota en un mal momento, el usuario no lo vuelve a ver en meses. Por eso hay tres guardas (`AppConfig`):

- `reviewMinSuccessfulActions` = 5 acciones de valor completadas.
- `reviewMinAppAge` = 3 días desde la instalación.
- `reviewMinInterval` = 120 días entre solicitudes.

`requestReviewAfterSuccess()` se llama **solo tras un éxito** (`TaskCard._completeTask`). Nunca al arrancar, nunca tras un error, nunca desde Ajustes.
Para el botón explícito "Valorar la aplicación" de Ajustes se usa `openStoreListing()`, que no consume la cuota del diálogo nativo.

---

## 5.1 Crash reporting (Firebase Crashlytics)

`services/crash/crash_reporter.dart`. **Se engancha en `AppLogger.error`,** no se
llama desde las features: ninguna feature importa Firebase, y cambiar de
proveedor toca este archivo y `bootstrap.dart` y nada más.

| Decisión | Por qué |
|---|---|
| `AppLogger` habla con un `CrashSink` (callback), no con Firebase | `core/utils/` lo alcanza lógica pura sin plataforma detrás; un import de Firebase ahí rompería los tests |
| **`fatal: true` solo en los tres handlers globales** de `bootstrap.dart` | Un `try/catch` que degradó una función **no** es un crash. Contarlo como tal hunde el *crash-free rate* que Play mira en Android Vitals |
| `Firebase.initializeApp()` va **después** del primer frame | Presupuesto de arranque (§8). No es un agujero: el SDK nativo se instala solo por ContentProvider al arrancar el proceso, así que un crash nativo/JVM previo sí se captura |
| Colección **apagada en debug** (`!kDebugMode`) | Tus propios crashes de desarrollo ensucian el panel y falsean la métrica |
| El plugin de Gradle se aplica **solo si existe `android/app/google-services.json`** | El plugin `google-services` no degrada: **rompe el build** si falta el archivo. Sin esa condición, nadie podría compilar el proyecto sin tener antes un proyecto de Firebase |
| Nunca se llama a `setUserIdentifier` ni se ponen custom keys | Un informe no puede reatarse a una persona con nada que ponga esta app |

> ⚠️ **La ofuscación de Dart y Crashlytics no se entienden solas.** El plugin de
> Crashlytics sube el mapping de R8, así que la mitad Kotlin/Java del stack se
> lee bien en la consola. Las líneas **Dart** llegan ofuscadas por
> `--obfuscate`: se descifran a mano con los símbolos que §10 manda archivar.
>
> ```bash
> flutter symbolize -i traza.txt -d build/symbols/1.0.0/app.android-arm64.symbols
> ```
>
> Por eso perder `build/symbols/<versión>` deja los crashes de esa versión
> ilegibles para siempre.

**Qué datos recibe** (todo automático; la app no añade nada): UUID de instalación
de Crashlytics (pseudónimo, se regenera al reinstalar o borrar datos), marca /
modelo / orientación / RAM y disco libres / si está rooteado, versión de Android
y API level, `applicationId` y versión de la app, timestamp y duración de la
sesión, y la traza con tipo y mensaje de la excepción. **No** recoge nombre,
correo, ID de publicidad ni ubicación. Hay que declararlo en el Data Safety form
como *Crash logs* y *Diagnostics*.

---

## 6. Tema y diseño (Material 3)

- Un **único seed color** (`AppColors.seed`) genera los esquemas claro y oscuro con `ColorScheme.fromSeed`. Rebrandear una app nueva = cambiar esa constante.
- `AppTheme.light([scheme])` / `AppTheme.dark([scheme])` aceptan un `ColorScheme` externo: si algún día se quiere Material You (colores del fondo de pantalla), se inyecta ahí sin tocar el resto del tema.
- Colores semánticos (success/warning) vía `ThemeExtension<AppSemanticColors>`, accesibles con `context.semanticColors`.
- **Tokens de espaciado y radios** en `AppSpacing` / `AppRadius`. Prohibido escribir paddings a pelo.
- `ThemeModeController` persiste claro/oscuro/sistema en `shared_preferences` de forma **síncrona** (las prefs ya están cargadas en `bootstrap`), así el primer frame no parpadea con el brillo equivocado.
- Widgets base: `BaseScreen`, `SectionCard`, `AppLoader`, `EmptyState`, `ErrorView`, `AdaptiveBannerAd`.

**Toda pantalla nueva debe construirse sobre `BaseScreen`**, no sobre un `Scaffold` pelado: así la política de colocación del banner vive en un solo sitio.

---

## 7. Navegación (`go_router`)

- Rutas declarativas en `core/routing/app_router.dart`, constantes en `app_routes.dart`. **Nunca escribir un path literal en una pantalla.**
- Navegación por nombre: `context.goNamed(AppRoutes.settingsName)`.
- `rootNavigatorKey` disponible para código fuera del árbol (callbacks de anuncios, stream de compras) en vez de guardar un `BuildContext` obsoleto.
- Deep links activos desde el día 1: esquema `buscaraudifonos://` en el manifiesto + `flutter_deeplinking_enabled`. App Links (`https`, `autoVerify`) están comentados: activarlos requiere publicar `assetlinks.json` en el dominio.
- `errorBuilder` → `RouteErrorScreen`, para que un deep link de campaña obsoleto no crashee.

---

## 8. Arranque (`bootstrap.dart`)

Objetivo: **primer frame < 2 s en gama media**.

Antes de `runApp` solo se permite:
1. `WidgetsFlutterBinding.ensureInitialized()`
2. cargar `SharedPreferences` (unos ms, y evita parpadeos de tema/contadores)

Todo lo demás arranca **después del primer frame** (`addPostFrameCallback`), en este orden y con `try/catch` individual:
1. `premiumControllerProvider` — el entitlement debe conocerse **antes** de pedir anuncios.
2. `AdsService.initialize()` (RequestConfiguration → consentimiento → `MobileAds.initialize()` → precarga).
3. `adsInitializedProvider.markInitialized()` — hace que los banners aparezcan sin esperar a un rebuild ajeno.

Todo va dentro de `runZonedGuarded`, con `FlutterError.onError` y `PlatformDispatcher.instance.onError` enrutados a `AppLogger`.

`main.dart` no contiene lógica. **No añadir nada ahí.**

---

## 9. Configuración Android

`android/app/build.gradle.kts`:

- `compileSdk = 37` — **obligatorio**, lo exigen `permission_handler 13` y `flutter_secure_storage 11`. No bajarlo.
- `minSdk = 24`, `targetSdk = flutter.targetSdkVersion`.
- `applicationId = com.alejandrosahonero.buscaraudifonos` — **no se puede cambiar nunca** tras publicar.
- Release: `isMinifyEnabled = true`, `isShrinkResources = true`, `proguard-rules.pro`.
- **Firma:** lee `android/key.properties` (git-ignored). Si no existe, cae a la firma de debug para no romper builds locales. Antes de publicar, verificar que `key.properties` existe y que el AAB **no** va firmado con debug.
- El nombre visible se declara directo en `AndroidManifest.xml` (`android:label`).

> ⚠️ **Sin flavors y sin entornos, a propósito. No reintroducirlos.**
>
> Había un split `dev` / `prod` con `applicationIdSuffix` y un `--dart-define=APP_ENV`.
> Obligaba a arrastrar `--flavor` en **cada** comando y hacía que un `flutter run`
> a secas fallara, a cambio de una sola garantía real: no pedir IDs de anuncios
> de producción desde desarrollo. Esa garantía la da ahora `kReleaseMode` en
> `AppConfig.useProductionAds`, y no se puede romper por olvidar un argumento.

---

## 9.1 Icono y splash

Sin `flutter_launcher_icons` ni `flutter_native_splash`: los recursos están
escritos a mano en `android/app/src/main/res/`, son cuatro archivos y así no hay
un paso de generación que pueda sobrescribirlos.

**Icono**: adaptativo (`mipmap-anydpi-v26/ic_launcher.xml`) = color
`@color/ic_launcher_background` + vector `@drawable/ic_launcher_foreground`, más
`monochrome` para los iconos temáticos de Android 13.

**Splash** — hay que tocar **dos** mecanismos, y esto es lo que se olvida:

| Android | Qué se pinta | Archivo |
|---|---|---|
| ≤ 11 | `android:windowBackground` del `LaunchTheme` | `drawable-v21/launch_background.xml` |
| 12+ (API 31) | Splash Screen del sistema; **ignora `windowBackground`** | `values-v31/styles.xml` y `values-night-v31/styles.xml` |

- Tocar solo el layer-list deja a Android 12+ con el splash por defecto de la
  plataforma. Es el fallo típico y no da ningún error.
- **`values-night-v31` hace falta de verdad**: sin él, en un móvil oscuro con
  Android 12, `values-night` gana sobre `values-v31` y se lleva por delante los
  atributos del splash.
- **En el layer-list el icono va como `android:drawable` + `android:gravity`,
  nunca dentro de un `<bitmap>`**: el foreground es un vector y `<bitmap>` solo
  acepta bitmaps de verdad.
- **288dp** es el lienzo que Android 12 da a un icono de splash sin fondo
  propio; usar el mismo tamaño en el layer-list es lo que hace que el logo se
  vea igual en todas las versiones. El arte ocupa ~40 % de ese lienzo, así que
  entra de sobra en los 192dp de zona segura.
- El splash mantiene el color del icono también en modo oscuro: se abre desde un
  lanzador que lo muestra así pase lo que pase.

---

## 10. Comandos

```bash
# Desarrollo
flutter run

# Calidad (obligatorio antes de cerrar una tarea)
dart format lib test && flutter analyze && flutter test

# Release para Play (AAB, ofuscado, símbolos archivados por versión)
flutter clean && flutter pub get
flutter build appbundle --release \
  --obfuscate --split-debug-info=build/symbols/1.0.0

# Auditoría de tamaño (objetivo: AAB < 15 MB)
flutter build appbundle --release --analyze-size
```

**Guardar `build/symbols/<versión>` fuera del repo.** Sin esos símbolos los crashes son ilegibles.

---

## 11. Pasar a producción — checklist del template

1. `pubspec.yaml`: `name`, `description`, `version`.
2. `android/app/build.gradle.kts`: `namespace` y `applicationId` definitivos (formato `com.empresa.app`).
3. Renombrar el paquete Kotlin en `android/app/src/main/kotlin/...` acorde.
4. `AndroidManifest.xml` → `android:label` con el nombre visible real.
5. `core/config/ad_config.dart`: rellenar `_prodBanner`, `_prodInterstitial`, `_prodRewarded`.
6. `AndroidManifest.xml`: sustituir el App ID de prueba de AdMob por el de producción.
7. `core/config/billing_config.dart`: ID del producto (debe coincidir con Play Console).
8. `core/theme/app_colors.dart`: `seed`.
9. `lib/l10n/*.arb`: textos reales.
10. Icono adaptativo y splash: **hechos a mano, sin `flutter_launcher_icons` ni `flutter_native_splash`** (ver §9.1).
11. Crash reporting: **integrado** (Firebase Crashlytics, §5.1). Falta solo crear el proyecto en la consola de Firebase y dejar caer `google-services.json` en `android/app/`; sin ese archivo la app compila y funciona, pero no reporta nada.
12. Política de privacidad publicada en una URL accesible (obligatoria por usar AdMob).
13. Data Safety form, content rating (IARC), público objetivo, declaración "contiene anuncios".
14. Testing interno → closed testing (**12 testers / 14 días** para cuentas personales creadas después de nov-2023) → producción con rollout escalonado 10–20 %.
15. Vigilar Android Vitals: crash rate > 1,09 % o ANR > 0,47 % penalizan la visibilidad → parar el rollout.

---

## 12. Definición de "hecho" para cada release

- [ ] `flutter analyze` sin issues y `dart format` aplicado.
- [ ] Tests pasando.
- [ ] Probado en dispositivo físico de gama baja en **modo release** (R8 rompe cosas que en debug funcionan).
- [ ] Sin IDs de prueba de AdMob ni logs de debug en el build de producción.
- [ ] `versionCode` incrementado.
- [ ] Símbolos de ofuscación archivados y subidos al crash reporting.
- [ ] Tamaño del AAB verificado, sin regresión.
- [ ] Compra premium y restauración probadas con cuenta de tester licenciado.
- [ ] Notas de la versión en todas las localizaciones.

---

## 13. Rendimiento — recordatorios al escribir código

- Listas: `ListView.builder` / `SliverList` siempre.
- Extraer widgets propios en vez de métodos `_buildX()`, para acotar rebuilds.
- `RepaintBoundary` en animaciones y elementos que se repintan solos.
- Imágenes: WebP para bitmaps, SVG para iconografía, `cacheWidth`/`cacheHeight` obligatorios.
- Liberar recursos en `dispose()`: controllers, streams, timers (`AdsService.disposeAds` y `AdaptiveBannerAd.dispose` ya lo hacen).
- Trabajo pesado fuera del isolate principal (`compute()` / `Isolate.run()`).
- Perfilar en **modo profile en dispositivo físico**, nunca en debug ni emulador.
