# Bildgenerator

Eine App zum Erstellen von Bildern aus Textbeschreibungen – mit optionalen
Referenzbildern, wählbarer Bildgröße, Qualität und transparentem Hintergrund.
Eine Codebasis (Flutter) für **Windows, Android, iOS und Web**.

## Funktionen

- **Text → Bild**: Bildbeschreibung (Prompt) eingeben, Bild generieren.
- **Mehrere Referenzbilder** (bis zu 16): eigene Fotos/Bilder als Vorlage
  mitgeben – das Ergebnis orientiert sich daran (Provider OpenAI).
- **Bildgröße/Seitenverhältnis wählbar**: Quadrat, Quer-, Hochformat
  (OpenAI) bzw. 9 Seitenverhältnisse von 21:9 bis 9:21 (Stability AI).
- **Qualität wählbar**: Auto / Niedrig / Mittel / Hoch.
- **Transparenter Hintergrund** (für Logos & Icons, PNG/WebP) – mit
  Schachbrett-Vorschau.
- **Profi-Features**:
  - Zwei Provider: **OpenAI gpt-image-1** und **Stability AI Stable Image Core**
  - Ausgabeformat PNG / JPEG / WebP inkl. Kompressionsgrad
  - Batch-Generierung (1–4 Bilder pro Anfrage)
  - Negativ-Prompt, Seed (reproduzierbare Bilder) und 16 Style-Presets
    (Stability AI)
  - Stil-Vorlagen per Klick (fotorealistisch, Ölgemälde, Logo, 3D-Render …)
  - Generierte Bilder als neue Referenz übernehmen (iteratives Verfeinern)
  - Galerie/Verlauf mit Prompt, Parametern und „Erneut verwenden“
  - Bilder speichern, teilen bzw. herunterladen
  - API-Schlüssel werden **verschlüsselt lokal** gespeichert (Keychain /
    Keystore / DPAPI), dunkles & helles Design

## Voraussetzung: API-Schlüssel

Die Bilder werden von einem KI-Provider erzeugt. Dafür wird ein eigener
API-Schlüssel benötigt (nutzungsbasierte Kosten beim Anbieter, grob
0,01–0,25 $ pro Bild je nach Qualität):

- **OpenAI** (empfohlen, alle Funktionen): <https://platform.openai.com/api-keys>
  – für `gpt-image-1` muss die Organisation einmalig verifiziert werden
  (platform.openai.com → Settings → Organization → Verify).
- **Stability AI** (Alternative): <https://platform.stability.ai/account/keys>

Den Schlüssel in der App unter **Einstellungen** eintragen – er bleibt
ausschließlich auf dem Gerät und wird nur an den gewählten Provider gesendet.

## So testest du die App

Bei jedem Push baut GitHub Actions automatisch alle Varianten
(Reiter **Actions** → neuester „Build“-Lauf → Abschnitt **Artifacts**):

### Android (empfohlen zum Testen)

1. Auf dem Handy im Browser: GitHub → Repository → **Actions** → neuester
   „Build“-Lauf → Artifact **`bildgenerator-android-apk`** herunterladen
   (Anmeldung bei GitHub erforderlich).
2. Die ZIP entpacken und `app-release.apk` antippen. Beim ersten Mal fragt
   Android nach der Erlaubnis, Apps „aus unbekannten Quellen“ zu
   installieren – bestätigen.
3. App öffnen → Einstellungen → API-Schlüssel eintragen → losgenerieren.

### Windows

1. Artifact **`bildgenerator-windows`** herunterladen und entpacken.
2. `bildgenerator.exe` starten (keine Installation nötig).

### iPhone / iPad

- **Sofort testbar als Web-App (PWA):**
  1. Einmalig: Repository → **Settings → Pages** → Source **„GitHub
     Actions“** auswählen.
  2. Workflow **„Web-Version veröffentlichen (GitHub Pages)“** unter
     Actions per „Run workflow“ starten (läuft bei Pushes auf `main`
     später automatisch).
  3. Die App ist dann unter
     `https://<benutzername>.github.io/<repository-name>/` erreichbar –
     in Safari öffnen → Teilen → **„Zum Home-Bildschirm“** → sie verhält
     sich wie eine installierte App.
- **Nativ (App Store / TestFlight):** iOS-Apps können nur auf einem Mac
  mit Xcode (oder einem CI-Dienst wie Codemagic) signiert werden und
  benötigen ein Apple-Developer-Konto. Das Projekt ist dafür vorbereitet:
  `flutter build ipa` auf einem Mac genügt.

> Hinweis zur Web-Version: Der Verlauf gilt dort nur für die aktuelle
> Sitzung, und einzelne Provider können Browser-Anfragen per CORS
> einschränken (OpenAI funktioniert im Browser). Die nativen Apps sind
> davon nicht betroffen und speichern den Verlauf dauerhaft.

## Entwicklung

```bash
flutter pub get
flutter run                # auf angeschlossenem Gerät/Emulator
flutter run -d chrome      # im Browser
flutter build apk          # Android-APK
flutter build windows      # Windows (auf einem Windows-PC)
flutter build ipa          # iOS (auf einem Mac)
flutter test               # Tests
```

Verwendete Flutter-Version: 3.47.2 (stable).

## Architektur

```
lib/
├── main.dart                  # App-Shell, Navigation, Theme
├── models/models.dart         # Anfrage/Ergebnis/Verlauf + Auswahloptionen
├── screens/                   # Generator, Galerie, Detailansicht, Einstellungen
├── services/
│   ├── generators.dart        # OpenAI- & Stability-Anbindung (austauschbar)
│   ├── settings_service.dart  # Einstellungen + sichere Schlüsselablage
│   ├── history_service.dart   # Verlauf (Dateisystem nativ, In-Memory im Web)
│   └── exporter.dart          # Speichern/Teilen/Download je Plattform
└── widgets/common.dart        # Schachbrett-Transparenzvorschau u. a.
```

Weitere Provider lassen sich über das `ImageGenerator`-Interface in
`lib/services/generators.dart` ergänzen.
