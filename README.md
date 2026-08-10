# app_template

Plantilla base (Base Starter Template) en Flutter para desarrollar y publicar aplicaciones Android en Google Play con rapidez.

Trae preconfigurado lo que todas las apps repiten: monetización (AdMob + compra "quitar anuncios"), consentimiento GDPR, permisos de Android 12+, reseñas in-app, tema Material 3 claro/oscuro, navegación declarativa, localización es/en y el pipeline de release (ofuscación, R8, firma, flavors).

> **Para agentes de IA y para cualquiera que toque el código: leer [`CLAUDE.md`](CLAUDE.md) primero.** Explica la arquitectura, las reglas y el porqué de cada decisión.

---

## Qué incluye

| Área | Implementación |
|---|---|
| Estado | Riverpod 3 (`Provider` / `NotifierProvider` / `AsyncNotifierProvider`) |
| Navegación | `go_router` con rutas tipadas y deep links (`apptemplate://`) |
| Anuncios | `AdsService`: banner adaptativo, interstitial con pacing, rewarded con callback |
| Consentimiento | UMP SDK (incluido en `google_mobile_ads`) + "Opciones de privacidad" en Ajustes |
| Compras | `in_app_purchase`: producto no consumible `premium_remove_ads` + restaurar compras |
| Permisos | `permission_handler`: Bluetooth scan/connect, ubicación, notificaciones, con diálogos explicativos |
| Reseñas | `in_app_review` con guardas (5 acciones, 3 días de antigüedad, 120 días entre solicitudes) |
| Tema | Material 3 desde un único seed color, claro/oscuro/sistema persistido |
| Almacenamiento | `shared_preferences` (flags) + `flutter_secure_storage` (entitlement) |
| Localización | `gen-l10n` con `app_es.arb` / `app_en.arb` |

---

## Empezar

```bash
flutter pub get
flutter run --flavor dev --dart-define=APP_ENV=dev
```

> El proyecto define los flavors `dev` y `prod`, así que **`flutter run` a secas falla**: hay que pasar `--flavor`.

Antes de cerrar cualquier cambio:

```bash
dart format lib test && flutter analyze && flutter test
```

---

## Adaptar la plantilla a una app nueva

El checklist completo está en [`CLAUDE.md` §11](CLAUDE.md). En resumen:

1. `pubspec.yaml` → `name`, `description`, `version`.
2. `android/app/build.gradle.kts` → `namespace`, `applicationId` y `manifestPlaceholders["appName"]` de cada flavor.
3. `lib/core/config/ad_config.dart` → IDs de producción de AdMob (los de prueba ya están puestos).
4. `android/app/src/main/AndroidManifest.xml` → App ID de AdMob de producción.
5. `lib/core/config/billing_config.dart` → ID del producto de Play Console.
6. `lib/core/theme/app_colors.dart` → `seed`.
7. `lib/l10n/*.arb` → textos.

**Los anuncios usan exclusivamente los IDs oficiales de prueba de Google.** Los IDs de producción solo se activan en un build `--release --flavor prod`, para que nunca se genere tráfico inválido desde desarrollo.

---

## Publicar

```bash
flutter clean && flutter pub get
flutter build appbundle --release --flavor prod --dart-define=APP_ENV=prod \
  --obfuscate --split-debug-info=build/symbols/1.0.0
```

Antes hay que crear `android/key.properties` a partir de `android/key.properties.example`
(ese archivo y el `.jks` están en `.gitignore`; **nunca** se commitean).

Guardar `build/symbols/<versión>` fuera del repositorio: sin esos símbolos los crashes son ilegibles.
