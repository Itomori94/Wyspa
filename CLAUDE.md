# Wyspa — notatki dla Claude Code

Natywna aplikacja macOS (agent, LSUIElement) zamieniająca notch w interaktywną wyspę.
Prywatny użytek, dystrybucja poza App Store, bez sandboxa.

## Komendy

```bash
scripts/test.sh                 # wszystkie testy jednostkowe (Swift Testing) — przed każdym commitem
scripts/build-app.sh            # build/Wyspa.app, universal (arm64 + x86_64), release
scripts/build-app.sh --native --debug   # szybki build tylko na bieżącą architekturę
scripts/dev-cert.sh             # jednorazowo: lokalny certyfikat „Wyspa Development”
scripts/update-mediaremote-adapter.sh v0.7.8   # aktualizacja adaptera MediaRemote (jedna komenda)
open build/Wyspa.app            # uruchomienie
log stream --predicate 'subsystem == "pl.net.kurant.wyspa"' --info   # logi
```

Ostrzeżenie „x86_64 architecture is deprecated” przy buildzie universal jest kosmetyczne:
binarka ma `minos 14.0` dla obu architektur (sprawdź: `vtool -arch x86_64 -show-build …`).

## Architektura

| Warstwa | Target | Zawartość |
|---|---|---|
| App | `WyspaApp` (executable) | start, `ScreenCoordinator` (wyspa na ekran), `IslandWindowController`, panel, status item, okno ustawień, skrót |
| Core | `WyspaCore` | geometria, wybór ekranów, maszyna stanów, gesty, ustawienia, uprawnienia, protokół i rejestr modułów |
| UI | `WyspaUI` | `IslandShape`, `IslandView`, animacje, komponenty |
| Features | `WyspaFeatures` + target na moduł | `ModuleCatalog.all` — jedyne miejsce rejestracji modułów |

## Decyzje

- **Moduły** implementują `IslandModule` (`Sources/WyspaCore/Modules/IslandModule.swift`).
  Instancja powstaje dopiero po włączeniu i przyznaniu uprawnień; wyłączenie woła `deactivate()` i porzuca instancję.
  Przy starcie aplikacji brakujące uprawnienia nie wywołują dialogów (tylko przy ręcznym włączeniu).
  Nowy moduł: target `Sources/Features/<Nazwa>` zależny tylko od `WyspaCore`/`WyspaUI`, wpis w `Package.swift` i w `ModuleCatalog`.
  Moduły nie importują siebie nawzajem.
- **Live activity**: arbiter w `ModuleRegistry.currentActivity` wybiera najwyższy `ActivityPriority`
  (HUD > uwaga agenta > timer > wydarzenie > media > status).
- **Stany wyspy**: czysty reducer `IslandStateMachine` (hidden / collapsed / peek / expanded).
  Opóźnienia to efekty `.schedule/.cancel`, wykonywane w `IslandWindowController` jako jednorazowe `Task.sleep`.
  Każda zmiana zachowania wyspy = nowy przypadek w reducerze + test.
- **Zdarzenia bez timerów**: panel ma stały rozmiar (największy stan + cień). Przezroczyste piksele przepuszczają
  kliknięcia (okno `isOpaque = false`). `IslandContainerView` śledzi kursor `NSTrackingArea` tylko nad wyspą
  i zwraca nil z `hitTest` poza nią. Brak globalnych monitorów myszy.
  Ukryta wyspa (wirtualny notch bez aktywności) ma alfę 0.01, żeby okno wciąż dostawało najechanie.
- **Gesty**: lokalny monitor `scrollWheel` filtrowany do panelu → `SwipeRecognizer` (jeden kierunek na gest).
- **Skrót globalny**: Carbon `RegisterEventHotKey` (bez Accessibility).
- **Panel**: poziom `mainMenu + 3`, `canJoinAllSpaces`, `fullScreenAuxiliary`, `nonactivatingPanel`, `canBecomeKey = false`.
- **Podpis**: certyfikat „Wyspa Development” (stały designated requirement → zgody TCC przetrwają rebuild).
  Bez hardened runtime (nie notaryzujemy; runtime wymagałby entitlements dla kamery i Apple Events).
- **Swift 6 language mode**: callbacki C (Carbon, event tap) wchodzą na MainActor przez `MainActor.assumeIsolated`.
- **Ustawienia**: `SettingsStore` (UserDefaults, `@Observable`); moduły dostają `ModuleSettings` z prefiksem `module.<id>.`.
- **Obserwacja**: `observeChanges` (Observation, re-rejestracja po każdej zmianie) zamiast timerów i Combine.

## Media (moduł `WyspaMedia`)

- **Źródło systemowe**: [mediaremote-adapter](https://github.com/ungive/mediaremote-adapter), BSD-3-Clause,
  vendorowany **w całości i bez zmian** w `Vendor/mediaremote-adapter`, przypięty w `Vendor/mediaremote-adapter.version`
  (tag, commit, SHA-256 archiwum). Od macOS 15.4 MediaRemote jest zablokowany dla zwykłych aplikacji;
  adapter działa, bo `/usr/bin/perl` ma uprawnienie systemowe i ładuje `MediaRemoteAdapter.framework` przez DynaLoader.
- **Budowanie bez CMake**: `scripts/build-mediaremote-adapter.sh` kompiluje framework i klienta testowego `clang`-iem,
  listę źródeł czyta z bloku `ADAPTER_SOURCES` w `CMakeLists.txt` adaptera. Wywoływany z `build-app.sh`.
- **Pakiet**: `Contents/Frameworks/MediaRemoteAdapter.framework`, `Contents/Helpers/MediaRemoteAdapterTestClient`,
  `Contents/Resources/mediaremote-adapter/{mediaremote-adapter.pl, LICENSE, mediaremote-adapter.version}`.
  Framework wołamy zawsze ścieżką bezwzględną (względna nie ładuje się w Perlu).
- **Warstwa Swift**: protokół `NowPlayingSource` (`AdapterNowPlayingSource`, `AppleScriptNowPlayingSource`).
  Moduł zna tylko protokół; nowe źródło = nowa implementacja + przypadek w `MediaSourceKind`.
- **Wybór źródła** (`MediaSourceSelector`): Automatycznie → `test` adaptera (kod 0) → adapter, inaczej AppleScript.
  W trakcie działania przejście na AppleScript, gdy adapter padnie 3 razy z rzędu albo milczy ≥ 4 s,
  choć Muzyka/Spotify zgłaszają odtwarzanie (`SilentAdapterDetector`). Aktywne źródło i powód widać w ustawieniach modułu.
- **Bez odpytywania**: adapter `stream --no-diff --micros --debounce=100` wysyła dane tylko przy zmianach;
  AppleScript odświeża się po powiadomieniach rozproszonych `com.apple.Music.playerInfo` / `com.spotify.client.PlaybackStateChanged`.
  Pozycja odtwarzania jest liczona lokalnie z `elapsedTime + (teraz − timestamp) × playbackRate`.
- **Wizualizer**: `CALayer` + `CABasicAnimation` (animacje w serwerze okien, nie na głównym wątku); wyłączony przy „Ogranicz ruch”.
  To wizualizacja rytmu, nie analiza audio.

### Aktualizacja adaptera

```bash
scripts/update-mediaremote-adapter.sh v0.7.8   # pobiera wydanie, podmienia Vendor/, zapisuje przypięcie
scripts/test.sh && scripts/build-app.sh        # build + test adaptera z pakietu:
APP=$PWD/build/Wyspa.app/Contents
/usr/bin/perl $APP/Resources/mediaremote-adapter/mediaremote-adapter.pl \
  $APP/Frameworks/MediaRemoteAdapter.framework $APP/Helpers/MediaRemoteAdapterTestClient test; echo $?   # 0 = działa
```

## Budżet wydajności

W spoczynku < 1% CPU, żadnych ciągłych timerów. Wyjątek zaakceptowany: moduł schowka (polling `changeCount`),
tylko gdy jest włączony. Pomiar: `top -l 6 -s 2 -pid $(pgrep -x Wyspa) -stats pid,cpu` i `sample <pid> 10`.

## Prywatne API

Każde wywołanie prywatnego API przez `dlopen`/`dlsym` z bezpiecznym trybem awaryjnym (funkcja się wyłącza).
Lista z ryzykiem utrzymywana w README.md, sekcja „Znane ograniczenia”.

## Decyzje produktowe użytkownika

- Wyspa domyślnie na wszystkich ekranach, wybór w ustawieniach.
- Tryb skupienia pomijamy (bez Full Disk Access).
- Historia schowka pomija `org.nspasteboard.ConcealedType` i `org.nspasteboard.TransientType`, ma limit wpisów i czyszczenie.
- Hook uprawnień Claude Code: timeout ~1 s na połączenie z gniazdem, długi (konfigurowalny, domyślnie 5 min) na decyzję;
  powrót do promptu w terminalu tylko, gdy aplikacja nie odpowiada albo minie długi timeout.
- Przed etapem 2 potwierdzić wersję systemu (`sw_vers`) i na niej testować MediaRemote.
