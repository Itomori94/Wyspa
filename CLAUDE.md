# Wyspa — notatki dla Claude Code

Natywna aplikacja macOS (agent, LSUIElement) zamieniająca notch w interaktywną wyspę.
Prywatny użytek, dystrybucja poza App Store, bez sandboxa.

## Komendy

```bash
scripts/test.sh                 # wszystkie testy jednostkowe (Swift Testing) — przed każdym commitem
scripts/build-app.sh            # build/Wyspa.app, universal (arm64 + x86_64), release
scripts/build-app.sh --native --debug   # szybki build tylko na bieżącą architekturę
scripts/install.sh              # build + instalacja do /Applications (zamyka działającą kopię)
swift scripts/make-icon.swift   # odtworzenie Resources/AppIcon.icns (ikona rysowana kodem)
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
- **Panel**: poziom `mainMenu + 3`, `canJoinAllSpaces`, `fullScreenAuxiliary`, `nonactivatingPanel`.
  Klawiatura: `canBecomeKey` tylko w rozwiniętej wyspie + `becomesKeyOnlyIfNeeded`, więc fokus przechodzi do wyspy
  wyłącznie po kliknięciu pola tekstowego (przyciski go nie zabierają). Podczas pisania (`IslandState.isEditing`)
  zjechanie kursorem nie zwija wyspy; po zwinięciu klawiatura wraca do poprzedniej aplikacji. Esc zwija.
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
  choć Muzyka/Spotify zgłaszają odtwarzanie (`SilentAdapterDetector`). Wybór źródła nie jest pokazywany w ustawieniach (decyzja użytkownika z 2.10.2026); ustawienia pokazują tylko błąd, gdy żadne źródło nie działa. Aktywne źródło jest w logu (`media`).
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
- Zawartość wyspy: najpierw `.frame` o rozmiarze wyspy, potem `.clipShape(IslandShape)` — sam `clipShape` przycina
  do granic treści, które przy przepełnieniu rosną razem z nią.
- Nagłówek rozwiniętej wyspy: lewa połowa | przerwa pod notchem | prawa połowa, każda połowa to `ViewThatFits`
  z wariantami od najbogatszego; ostatni wariant mieści się zawsze. Prawa połowa: zakładki ze skrzydłem →
  kompaktowe ze skrzydłem → same zakładki → przewijany pasek (zakładki mają pierwszeństwo przed ozdobnym skrzydłem).
- **Układ wyspy** (`WyspaCore/Board/IslandBoard.swift`, niemutowalny, testowany): strony z widżetami obok siebie
  albo pełnym widokiem modułu. Szerokości płynne w 120 jednostkach wnętrza wyspy (120 dzieli się przez 1–6, więc
  równy podział jest dokładny); starszy zapis w dwunastkach przeliczany przy odczycie (`unitScale`). Minimalna
  szerokość z `ModuleDescriptor.widgetMinWidth` (punkty → jednostki). Wstawianie bierze wolne miejsce, a gdy go brak —
  równy podział; dzielnik przesuwa szerokości płynnie, suma pary bez zmian; usunięcie oddaje miejsce pozostałym.
  Zapis w `SettingsStore.board`; bez zapisu `ModuleRegistry.board` = `arrangedBoard` (układ automatyczny:
  odtwarzacz, półka i schowek na pełnych stronach, pozostałe widżety po 3 na stronę). Nowo włączony moduł dołącza
  do ostatniej strony z widżetami (`appendingWidget`); „Uporządkuj automatycznie” w edytorze zastępuje układ automatycznym.
  Pasek stron w edytorze zawija się (`FlowLayout`) — nic w edytorze nie może być szersze niż okno. `ModuleRegistry.pages` pomija wyłączone moduły i puste strony.
- **Edytor układu** (`WyspaApp/Settings/BoardEditorView.swift`, karta „Układ”): podgląd wyspy w skali z prawdziwymi
  widżetami (bez interakcji), przeciąganie z palety, między stronami i z powrotem na paletę (usuwa), uchwyty dzielników
  (gest liczony we współrzędnych wiersza, nie dzielnika — inaczej punkt odniesienia skacze i podgląd miga; w trakcie
  przeciągania tylko lokalny szkic, zapis raz po puszczeniu), strony przeciągane w pasku. Każda zmiana przez `apply { … }` — błąd `BoardError` jako komunikat.
- Pasek stron w nagłówku: `TabStripPlan` (czysta funkcja) — pełny → kompaktowy → bez skrzydła → część + menu „⋯”.
- **Pułapka kompilatora (Swift 6.4)**: ścieżka klucza do statycznej właściwości na `any IslandModule.Type`
  (`catalog.map(\.descriptor.id)`) wywala `swift-frontend` (SILGen). Używaj zamknięcia `{ $0.descriptor.id }`.
- Test wizualny `WyspaUITests/IslandOverflowTests`: renderuje wyspę poza ekranem (fazy × rozmiary × 0–10 zakładek ×
  szerokości skrzydeł) i wymaga braku jasnych pikseli poza kształtem. Podgląd klatek:
  `WYSPA_RENDER_DIR=/katalog swift test --filter IslandOverflowTests`.

## Produktywność (etap 5)

| Moduł | Target | Uprawnienie | Uwagi |
|---|---|---|---|
| Kalendarz | `WyspaCalendar` | Kalendarze | `UpcomingEventPolicy`: aktywność od 10 min przed startem do 5 min po; jedno zaplanowane wybudzenie na następną granicę albo północ |
| Przypomnienia | `WyspaReminders` | Przypomnienia | zaległe + dziś, odhaczanie `EKEventStore.save` |
| Timer | `WyspaTimer` | — | niemutowalna `TimerSession` liczona z dat (przetrwa restart), jedno zadanie do końca odliczania, Pomodoro 25/5/15 × 4 |
| Notatka | `WyspaNotes` | — | plik `Application Support/Wyspa/Notes/notatka.md`, autozapis po 0,6 s, zapis przy wyłączeniu |
| Historia schowka | `WyspaClipboard` | — | `changeCount` co 0,75 s tylko gdy włączony (zaakceptowany wyjątek); pomija Concealed/Transient; limit 10–500; tylko w pamięci; wyszukiwanie z „ł”→„l” |
| Skróty | `WyspaShortcuts` | — | `/usr/bin/shortcuts list/run`, nazwy jako argumenty procesu (bez powłoki), ulubione w ustawieniach |
| Lusterko | `WyspaMirror` | Kamera | sesja AVCapture tylko gdy widok zakładki jest w oknie |

## Monitor Claude Code (etap 6, moduł `WyspaClaudeMonitor`)

- **Hook** `wyspa-hook` (target `WyspaHook`, tylko Foundation + `WyspaHookKit`) w `Contents/Helpers`. Claude Code uruchamia go
  bez powłoki (`args`). Wejście hooka ze stdin → jedna linia JSON przez gniazdo Unix
  `~/Library/Application Support/Wyspa/claude.sock` (prawa 0600). Połączenie ~1 s (nieblokujący connect + poll);
  brak Wyspy = natychmiastowe wyjście, kod 0, pusty stdout (Claude Code działa jak bez hooka).
- **PermissionRequest** czeka na odpowiedź do `--decision-timeout` (ustawienie modułu, domyślnie 5 min; timeout hooka
  w settings.json = decyzja + 15 s). `allow`/`deny` → `hookSpecificOutput.decision.behavior`; `ask`, brak odpowiedzi,
  zamknięcie Wyspy → pusty stdout = zwykły prompt w terminalu. Zamknięcie połączenia przez hook zgłasza `onClosed`.
- **Instalacja** (`HookInstaller`, czyste przekształcenia + plik): kopia `settings.json.wyspa-backup-<data>` przed każdym
  zapisem, nieczytelny plik nie jest nadpisywany, wpisy Wyspy rozpoznawane po `wyspa-hook` w ścieżce, deinstalacja
  przywraca stan sprzed instalacji (test). Zapis sortuje klucze (`.sortedKeys`) — kolejność kluczy w pliku może się zmienić.
- **Stan sesji**: czysty reducer `SessionStore` (SessionStart/UserPromptSubmit/PreToolUse/PostToolUse/PermissionRequest/
  Notification/Stop/SessionEnd). Martwe sesje (proces Claude Code zniknął bez SessionEnd) usuwane przez `kill(pid, 0)`.
- **Terminal**: `__CFBundleIdentifier` z środowiska hooka → aplikacja; TTY procesu Claude z `sysctl` → karta w Terminal/iTerm2
  (AppleScript), VS Code/Cursor przez `vscode://file/<cwd>` / `cursor://file/<cwd>`.
- Testy integracyjne uruchamiają prawdziwy helper na gnieździe tymczasowym (`WYSPA_SOCKET_PATH`, działa tylko w debug);
  `scripts/test.sh` buduje `wyspa-hook` przed testami. W testach procesów używaj `terminationHandler`, nie
  `waitUntilExit` (to drugie potrafi przegapić koniec procesu poza głównym wątkiem i zawiesić test).
- **Bezpieczeństwo gniazda**: katalog 0700 (wymuszane przy starcie), gniazdo 0600 nadawane między `bind` a `listen` (bez `umask` — to ustawienie
  całego procesu), serwer sprawdza `getpeereid` (ten sam
  użytkownik), limit 64 połączeń; połączenia mają rosnące identyfikatory (decyzja nie trafi do innego hooka przy
  ponownym użyciu numeru fd). Hook sprawdza, że gniazdo jest gniazdem tego użytkownika, i czeka ≤ 2 s na potwierdzenie
  (`{"ack":true}`) wysyłane z głównego wątku Wyspy — zawieszona aplikacja oddaje decyzję terminalowi po 2 s.
- Hooki i linia statusu wskazują `HookShim` (`~/.local/share/wyspa/bin/wyspa-hook`, bez spacji): `exec` pomocnika z bieżącej
  Wyspa.app albo ciche wyjście 0, gdy aplikacji nie ma. Wyspa odświeża pośrednika przy każdym starcie modułu.
- Instalator rozpoznaje wpisy po nazwie pliku `wyspa-hook` (dokładnie), odrzuca nieoczekiwaną strukturę `hooks`,
  zapisuje przez dowiązania, zachowuje prawa pliku, trzyma 5 ostatnich kopii; zmiana czasu decyzji zapisuje hooki po 0,8 s.
- Sesje znikają po zakończeniu procesu Claude Code (`DispatchSource.makeProcessSource(.exit)`), bez odpytywania.

## Mikrofon (moduł `WyspaMicrophone`)

- CoreAudio, domyślne wejście: `Mute` (zakres wejścia), a bez niego `VolumeScalar` (element główny albo kanały 1…n)
  ustawiane na 0; głośność sprzed wyciszenia zapamiętana per UID urządzenia (`restoreVolumes`), przy braku — 75%.
- Zmiany urządzenia, wyciszenia i głośności przez `AudioObjectAddPropertyListenerBlock` na kolejce głównej (bez odpytywania).
  Nie czytamy dźwięku, więc bez `NSMicrophoneUsageDescription` i zgody TCC.
- Aktywność „wyciszony” ma priorytet 52 (nad mediami i spotkaniem, pod pobieraniem i timerem); przełączenie pokazuje
  na 1,5 s komunikat z priorytetem `.alert`. Skrót domyślny ⌃⌥M (`StoredShortcut` odróżnia „bez skrótu” od domyślnego).

## Skrypty (moduł `WyspaScripts`)

- Adresy `wyspa://notify|progress|done` (Info.plist `CFBundleURLTypes`) → `AppDelegate.application(_:open:)` →
  czysty parser `ScriptCommand(url:)` w WyspaCore → `ScriptCommandCenter.shared` (jeden odbiorca, bufor 5 poleceń sprzed
  startu modułu) → `ScriptsModule`. Stan to niemutowalny `ScriptsState` (kolejka kart, limit postępów, przedawnienie 15 min).
- Adres może otworzyć każda aplikacja i strona WWW: polecenia wyłącznie pokazują tekst (bez plików, procesów, skutków
  ubocznych), teksty bez znaków sterujących i przycięte, identyfikatory tylko `[A-Za-z0-9._-]`, karta podpisana „Skrypt”.
- Komenda `wyspa` = `Resources/wyspa` (POSIX sh, kodowanie procentowe przez `/usr/bin/perl`, `open -g`, ciche wyjście 0
  bez działającej Wyspy) w `Contents/Resources` (nie w `Helpers` — skrypt nie ma własnego podpisu). `CommandInstaller`
  kopiuje ją do `~/.local/bin/wyspa` tylko na przycisk; plik bez znacznika `wyspa-cli` nigdy nie jest nadpisywany ani usuwany.
- Bez zegarów w spoczynku: jedno zadanie na kartę, jedno na najbliższe przedawnienie, jedno na znikające „Gotowe”.

## Powiadomienia

- `NotificationBannerWatcher`: `AXObserver` na procesie `com.apple.notificationcenterui` (zdarzenia `AXWindowCreated`,
  `AXCreated`, `AXLayoutChanged`, bez odpytywania); po restarcie NotificationCenter podpina się ponownie
  (`didLaunchApplicationNotification`).
- Budowa banera (macOS 27.2): grupa o subroli `AXNotificationCenterBanner`, `Identifier` = UUID (deduplikacja),
  `Description` = „aplikacja, tytuł, podtytuł, treść”, dzieci `AXStaticText` z identyfikatorami `title`/`subtitle`/`body`.
  Parsowanie w czystym `BannerParser` (testy).
- Chowanie oryginału: przesunięcie okna banerów poza ekran (`kAXPositionAttribute`). Na macOS 27.2 to okno ma rozmiar
  całego ekranu i otwiera się w nim też Centrum powiadomień, więc gdy banerów już nie ma (`AXUIElementDestroyed`),
  okno wraca na zapamiętane miejsce. Akcja banera „Zamknij” odrzucona: może usuwać powiadomienie z Centrum.
- Okno jest schowane tylko na czas karty w wyspie: gdy kolejka pustoszeje, `releaseHiddenWindow()` je przywraca
  (alert w stylu „Alerty” pojawia się wtedy w rogu, jak ustawił użytkownik). Bezpiecznik: najwyżej 60 s.
  Na żywo sprawdzone dla banerów (okno schowane w trakcie karty, potem system je zamyka); stylu „Alerty” nie testowano
  na żywo (wymagałby zmiany ustawień powiadomień albo przypomnienia synchronizowanego przez iCloud).
- Karta pod notchem (`IslandState.hasCard`): najechanie i kliknięcie nie rozwijają wyspy — klik obsługuje karta.
- Karta: `LiveActivity` z `detail` (karta pod skrzydełkami, `IslandLayout.detailWidth`/`maxDetailHeight`), priorytet `.alert`,
  kolejka `NotificationQueue` (niemutowalna, limit 10 czekających), najechanie wstrzymuje odliczanie.
- Diagnostyka: `open -n build/Wyspa.app --args --dump-notification-ax` (60 s, `~/Library/Logs/Wyspa/notification-ax.txt`,
  0600 — plik zawiera treść powiadomień, usuwać po analizie) oraz `--probe-notification-banner`.

- **Przerwanie sesji**: po Esc/odrzuceniu narzędzia Claude Code nie wysyła Stop. Dla pracujących sesji obserwujemy
  zapis (`transcript_path`, `DispatchSource` na pliku) i czytamy ostatnie 32 KB: jeśli ostatnia wiadomość rozmowy to
  „[Request interrupted by user…”, sesja wraca do bezczynności (`TranscriptTail`, testy).

## Zrzuty ekranu

`scripts/screenshots.sh` → `docs/screenshots/*.png`: test `WyspaScreenshotTests` (pomijany bez `WYSPA_SCREENSHOTS_DIR`)
renderuje prawdziwe widoki modułów z danymi demonstracyjnymi (`showDemo` w modułach, tylko `#if DEBUG`). Nigdy nie
wrzucaj prawdziwych zrzutów ekranu do publicznego repo. Po zmianie wyglądu odśwież zrzuty.

## Tryb prywatny

- `ModuleDescriptor.content` (`.personal`/`.neutral`) bez wartości domyślnej — nowy moduł musi się zadeklarować.
- `ModuleRegistry.gated` owija każdy widok modułu osobistego (`resolve`, `widgetView`, `standaloneView`) w `PrivacyGate`:
  w trybie prywatnym `makePrivateView(compact:)` modułu albo zasłona. Karty live activity: `masked()` →
  `withPrivateDetail` albo brak karty.
- Test `PrivacyCoverageTests` przechodzi po całym `ModuleCatalog` (lista modułów osobistych jest jawna w teście).

## Wyjątki od „bez zegarów w spoczynku”

- Historia schowka: odpytywanie schowka tylko przy włączonym module (decyzja użytkownika).
- Bluetooth: odczyt baterii co 5 min tylko, gdy podłączone jest urządzenie podające baterię (system nie powiadamia
  o zmianie poziomu); jednorazowe zadanie planowane po każdym odczycie, anulowane w `deactivate()`.
- Powiadomienia: jednorazowe sprawdzenie 8 s po schowaniu banera (przywrócenie okna, gdyby system nie zgłosił zniknięcia).

## Prywatne API — rejestr

| API | Gdzie | Ryzyko | Tryb awaryjny |
|---|---|---|---|
| MediaRemote przez mediaremote-adapter (`/usr/bin/perl`) | `WyspaMedia` | Apple może zablokować Perla albo usunąć go z systemu | `test` adaptera → AppleScript (Muzyka, Spotify) |
| `DisplayServicesGet/SetBrightness` (DisplayServices) | `DisplayBrightnessControl` | symbol może zniknąć | `make()` → nil, klawisze jasności wracają do systemu |
| `KeyboardBrightnessClient` (CoreBrightness) | `KeyboardBacklightControl` | klasa/selektory mogą się zmienić | `responds(to:)`; brak → klawisze do systemu |
| `IOBluetoothDevice.batteryPercent*` | `BluetoothMonitor` | selektory mogą zniknąć | `responds(to:)`; brak → urządzenie bez poziomu baterii |
| `SACLockScreenImmediate` (login.framework) | `QuickActionsModule.lockScreen` | symbol może zniknąć | `pmset displaysleepnow` (blokuje, gdy hasło jest wymagane od razu po uśpieniu) |
| `SLSRegisterNotifyProc` typy 1502/1503 (SkyLight) | `ScreenCaptureDetector.observe` | numery typów ustalone eksperymentem na 27.2, mogą się zmienić | rejestracja nieudana → sprawdzanie przy rozwinięciu, nowej karcie i zmianie aplikacji; ustawienia to pokazują |
| `SLSIsScreenWatcherPresent` (SkyLight) | `ScreenCaptureDetector` (tryb prywatny) | symbol może zniknąć | `isAvailable == false` → tryb automatyczny nic nie chowa, ustawienia to mówią; tryb „Zawsze” działa |
| Drzewo Dostępności banerów NotificationCenter (nieudokumentowane) | `NotificationBannerWatcher` | nowy macOS zmieni subrolę/identyfikatory | baner nie zostaje rozpoznany ani schowany — powiadomienia działają systemowo |

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
