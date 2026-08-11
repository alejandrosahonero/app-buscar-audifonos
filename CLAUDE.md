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
│   │   ├── data/             # BluetoothScanService, GeigerSounder
│   │   ├── domain/           # DiscoveredDevice, Proximity, ScanFilter
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
| `/` | `ScannerScreen` — lista de dispositivos, FAB Escanear/Detener, banner |
| `/radar/:deviceId` | `RadarScreen` — radar animado + sonido Geiger |

`AppRoutes.radarDeviceIdParam` es el id (MAC en Android, UUID en iOS). El radar
**no** recibe el dispositivo por `extra`: lo relee del stream por id, porque la
lectura tiene que seguir cambiando mientras el usuario camina.

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

### Conversión RSSI → cercanía (`domain/proximity.dart`)

Rango útil **-100 dBm → -30 dBm** mapeado a 0-100 %. **No se muestra distancia en
metros**: el RSSI depende de cuerpos, paredes y potencia del emisor, así que se
enseña una cercanía relativa que el usuario "escala" caminando.
Bandas: `far` (<40 %) rojo, `near` (40-72 %) ámbar, `veryNear` (≥72 %) verde,
resueltas en un solo sitio (`proximityColor` en `signal_strength_icon.dart`).

### Sonido Geiger (`data/geiger_sounder.dart`)

`audioplayers` con dos assets WAV **sintéticos** generados por script
(`dart run tool/generate_audio_assets.dart`) — no hay binarios opacos en el repo.

- **Clics** (gratis): intervalo de 1100 ms a 90 ms según cercanía, en curva
  (el oído resuelve mejor los cambios en un tren rápido). `PlayerMode.lowLatency`
  → SoundPool en Android, imprescindible para repetir cada 90 ms.
- **Tono continuo** (`radarContinuousLocked`): se desbloquea con **vídeo
  recompensado** y dura **solo la sesión**. `rewardedContinuousModeProvider` **no
  se persiste** a propósito: si sobreviviera al reinicio, el rewarded se
  convertiría en una compra única. Premium lo tiene incluido
  (`continuousModeUnlockedProvider`).

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
- **Rewarded:** desbloqueo del tono continuo. La recompensa se concede **solo**
  dentro de `onUserEarnedReward`.
- **Interstitial:** al salir del radar con la flecha de la AppBar (transición
  natural). El back del sistema **no** lo dispara, para no romper la animación de
  *predictive back*.
- **Reseña:** al alcanzar la banda `veryNear` — el usuario acaba de encontrar lo
  que había perdido. Una vez por pantalla, nunca tras un error.

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

**IDs.** `core/config/ad_config.dart` mantiene dos juegos: los **IDs oficiales de prueba de Google** y los de producción (vacíos hasta que existan). La selección es automática:

```dart
AppConfig.useProductionAds  // == isProd && kReleaseMode
```

Un ID vacío **desactiva** ese formato en vez de romper. **Nunca** usar IDs de producción en debug: es causa directa de baneo por tráfico inválido.

El App ID de prueba también está declarado en `android/app/src/main/AndroidManifest.xml`
(`ca-app-pub-3940256099942544~3347511713`).

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

**Banner.** `AdaptiveBannerAd` (anchored adaptive, no 320x50 fijo) se coloca desde `BaseScreen` **debajo** del contenido dentro de un `Column`, nunca superpuesto. Si no hay anuncio o el usuario es premium ocupa **cero** altura.
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
- **Flavors `dev` / `prod`** con `applicationIdSuffix = ".dev"`, para tener ambas instaladas a la vez.
- El nombre visible viaja como **manifest placeholder** (`${appName}`), no como `resValue`: AGP 9 desactiva la build feature `resValues` por defecto y un `resValue` en un flavor rompe la configuración del proyecto.

> ⚠️ **Con flavors, `flutter run` a secas falla.** Hay que indicar el flavor:
> ```bash
> flutter run --flavor dev --dart-define=APP_ENV=dev
> ```

---

## 10. Comandos

```bash
# Desarrollo
flutter run --flavor dev --dart-define=APP_ENV=dev

# Calidad (obligatorio antes de cerrar una tarea)
dart format lib test && flutter analyze && flutter test

# Release para Play (AAB, ofuscado, símbolos archivados por versión)
flutter clean && flutter pub get
flutter build appbundle --release --flavor prod --dart-define=APP_ENV=prod \
  --obfuscate --split-debug-info=build/symbols/1.0.0

# Auditoría de tamaño (objetivo: AAB < 15 MB)
flutter build appbundle --release --flavor prod --analyze-size
```

**Guardar `build/symbols/<versión>` fuera del repo.** Sin esos símbolos los crashes son ilegibles.

---

## 11. Pasar a producción — checklist del template

1. `pubspec.yaml`: `name`, `description`, `version`.
2. `android/app/build.gradle.kts`: `namespace` y `applicationId` definitivos (formato `com.empresa.app`).
3. Renombrar el paquete Kotlin en `android/app/src/main/kotlin/...` acorde.
4. `android/app/build.gradle.kts` → `manifestPlaceholders["appName"]` de cada flavor con el nombre visible real.
5. `core/config/ad_config.dart`: rellenar `_prodBanner`, `_prodInterstitial`, `_prodRewarded`.
6. `AndroidManifest.xml`: sustituir el App ID de prueba de AdMob por el de producción.
7. `core/config/billing_config.dart`: ID del producto (debe coincidir con Play Console).
8. `core/theme/app_colors.dart`: `seed`.
9. `lib/l10n/*.arb`: textos reales.
10. Iconos adaptativos (`flutter_launcher_icons`) y splash nativo (`flutter_native_splash`) — **no incluidos** en la plantilla porque necesitan assets reales; añadirlos por app.
11. Crash reporting (Crashlytics o Sentry) — **pendiente**, obligatorio desde la v1. Enganchar en `AppLogger.error` y en `bootstrap`.
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
