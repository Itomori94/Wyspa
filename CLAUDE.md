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
- **Kliknięcia i przeciąganie**: `IslandContainerView.hitTest` zwraca nil poza wyspą, a w jej obrębie przekazuje
  wszystko do `IslandHostingView` (SwiftUI, `acceptsFirstMouse = true`). Kliknięcie zwiniętej wyspy to `onTapGesture`
  na kształcie wyspy.
- **Upuszczanie**: jeden `DropDelegate` na całej wyspie (`IslandDropDelegate`), żeby przejścia między strefami
  nie wyglądały jak opuszczenie wyspy. Moduły implementują `IslandDropHandling` i oznaczają strefy
  `.islandDropZone("<id modułu>.<strefa>")`; ramki stref zbiera preferencja `DropZoneKey`, trafienie wybiera
  najmniejsza strefa pod kursorem. `ModuleRegistry.performDrop` kieruje upuszczenie do właściciela strefy.
  Podświetlenie strefy: `@Environment(\.islandDropTarget)`. Po upuszczeniu `resyncPointer()` przywraca śledzenie
  kursora (AppKit wstrzymuje je podczas przeciągania). `IslandDragSession.isDraggingOut` blokuje upuszczenie
  elementów wyciąganych z wyspy z powrotem na nią.
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

## Półka (moduł `WyspaShelf`)

- `ShelfStore` (`@MainActor`): indeks `shelf.json` + kopie w `Items/<uuid>/` w `~/Library/Application Support/Wyspa/Shelf`.
  Zapis po każdej zmianie (atomowo). Uszkodzony indeks = pusta półka, bez awarii.
- Pliki z dysku jako **bookmarki** (śledzą przeniesienia, nieaktualny bookmark odświeżany przy odczycie);
  treści bez pliku (obraz z przeglądarki, link → `.webloc`, tekst → `.txt`, obietnice plików) jako **kopie**.
  Usunięcie z półki kasuje tylko kopie, nigdy oryginały. Nazwy plików są oczyszczane (`sanitizedFileName`).
- `IngestPlan.choose` wybiera sposób wczytania po typach: plik → obraz → link → tekst → inne dane.
- Mysz na kafelkach w AppKit (`TileMouseView`): klik/⌘/⇧, dwuklik, menu kontekstowe i przeciąganie
  **wielu plików naraz** (`beginDraggingSession`); SwiftUI `onDrag` obsługuje tylko jeden element.
- Quick Look: `QLPreviewPanel` z ustawionym bezpośrednio `dataSource` (panel wyspy nie jest kluczowy), aplikacja aktywowana.
- AirDrop: `NSSharingService(named: .sendViaAirDrop)`; treści bez pliku trafiają do katalogu tymczasowego.
- Wyłączenie modułu zwalnia pamięć, zawartość półki zostaje na dysku.

## HUD, Zasilanie, Bluetooth (etap 4)

- **HUD** (`WyspaHUD`, wymaga Dostępności): `CGEventTap` (`.cgSessionEventTap`, `.defaultTap`) na `NX_SYSDEFINED` (typ 14),
  podtyp 8, `data1` = kod klawisza (bity 16–31) + stan (0x0A/0x0B) + powtórzenie (bit 0). Callback C dekoduje zdarzenie
  i przekazuje do głównego aktora tylko wartości `Sendable`. Decyzję podejmuje czysty `HUDKeyRouter`:
  obsłużone klawisze są pochłaniane (system nie pokazuje swojego HUD), nieobsłużone i niedostępne wracają do systemu,
  sam ⌥ zostaje dla systemu, ⇧⌥ = krok 1/64. Tap wyłączony przez system (timeout) jest włączany ponownie.
  Głośność: CoreAudio `VirtualMainVolume` + `Mute` domyślnego wyjścia; urządzenia bez sterowania → klawisz do systemu.
- **Zasilanie** (`WyspaPower`): `IOPSNotificationCreateRunLoopSource` (bez odpytywania), `PowerEventDetector`
  (ładowarka, naładowana, progi 20 i 10% raz na rozładowanie). Priorytet aktywności `.alert` na 3 s.
- **Bluetooth** (`WyspaBluetooth`, wymaga zgody na Bluetooth): `IOBluetoothDevice.register(forConnectNotifications:)`
  i powiadomienia o rozłączeniu per urządzenie; poziom baterii odświeżany raz po 2 s od połączenia.
- `ModuleRegistry.retryInactiveModules()` po powiadomieniu `com.apple.accessibility.api` — HUD startuje sam po nadaniu
  Dostępności, bez ponownego przełączania modułu.
- `LiveActivity.wingWidth`: szersze skrzydła dla pasków i procentów (HUD 70, zasilanie/Bluetooth 46),
  przycinane do `IslandLayout.maxWingWidth`. Rama panelu liczona z najszerszego możliwego stanu
  (`panelSize(expanded:notch:shadowMargin:)` z maksymalnym skrzydłem), więc żadna aktywność nie wyjdzie poza okno.
- Skrzydła w zwiniętej wyspie wypełniają bieżącą, animowaną szerokość (`maxWidth: .infinity`), zawartość wyspy jest
  przycinana do `IslandShape`, a zmiana aktywności to nowy widok (`.id(activity.id)`) z wygaszeniem. Identyfikatory
  `matchedGeometryEffect` zawierają id aktywności (`ActivityGeometryID`), żeby nie dopasowywać różnych aktywności.

## Prywatne API — rejestr

| API | Gdzie | Ryzyko | Tryb awaryjny |
|---|---|---|---|
| MediaRemote przez mediaremote-adapter (`/usr/bin/perl`) | `WyspaMedia` | Apple może zablokować Perla albo usunąć go z systemu | `test` adaptera → AppleScript (Muzyka, Spotify) |
| `DisplayServicesGet/SetBrightness` (DisplayServices) | `DisplayBrightnessControl` | symbol może zniknąć | `make()` → nil, klawisze jasności wracają do systemu |
| `KeyboardBrightnessClient` (CoreBrightness) | `KeyboardBacklightControl` | klasa/selektory mogą się zmienić | `responds(to:)`; brak → klawisze do systemu |
| `IOBluetoothDevice.batteryPercent*` | `BluetoothMonitor` | selektory mogą zniknąć | `responds(to:)`; brak → urządzenie bez poziomu baterii |

Ładowanie funkcji C wyłącznie przez `PrivateSymbol.load` (dlopen/dlsym, log przy braku). Selektory Objective-C zawsze
za `responds(to:)` — `value(forKey:)` bez tej kontroli rzuca wyjątek, którego Swift nie złapie.

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
