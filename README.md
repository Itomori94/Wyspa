# Wyspa

Natywna aplikacja macOS, która zamienia notch MacBooka w interaktywną wyspę w stylu Dynamic Island.
Prywatny projekt, dystrybucja poza App Store.

## Wymagania

- macOS 14 Sonoma lub nowszy, Apple Silicon albo Intel.
- Xcode (do budowania; wystarczy zainstalowany, budujemy z terminala).

## Instalacja

```bash
git clone <repo> Wyspa && cd Wyspa
scripts/dev-cert.sh        # jednorazowo, lokalny certyfikat do podpisu
scripts/build-app.sh       # buduje build/Wyspa.app
cp -R build/Wyspa.app /Applications/
open /Applications/Wyspa.app
```

`dev-cert.sh` tworzy samopodpisany certyfikat „Wyspa Development” w pęku kluczy logowania.
Dzięki niemu macOS pamięta przyznane zgody po każdym ponownym zbudowaniu aplikacji.
Bez certyfikatu `build-app.sh` podpisze aplikację ad-hoc, a zgody trzeba będzie nadawać od nowa.

Przy pierwszym podpisie macOS może zapytać, czy `codesign` może użyć klucza — wybierz „Zawsze pozwalaj”.

## Obsługa

- **Najechanie** na notch: wyspa lekko się powiększa, po chwili rozwija (opóźnienie w ustawieniach).
- **Kliknięcie** albo **przesunięcie dwoma palcami w dół**: rozwija od razu.
- **Przesunięcie w górę** albo zjechanie kursorem: zwija.
- **Przesunięcie w poziomie** w rozwiniętej wyspie: zmienia zakładkę modułu.
- **⌃⌥W** (domyślnie, do zmiany w ustawieniach): rozwija lub zwija wyspę na ekranie z kursorem.
- Ikona w pasku menu: ustawienia i zamknięcie aplikacji.

## Uprawnienia

Każdy moduł wymagający uprawnienia jest domyślnie wyłączony i prosi o nie dopiero przy pierwszym włączeniu.
Wyłączony moduł nie działa w tle.

| Uprawnienie | Kto go używa |
|---|---|
| — | Fundament wyspy nie wymaga żadnych uprawnień |
| — | **Teraz odtwarzane** przez mediaremote-adapter nie wymaga uprawnień |
| — | **Półka** nie wymaga uprawnień |
| Dostępność | **HUD głośności i jasności** (przechwytywanie klawiszy). Po nadaniu w Ustawieniach systemowych moduł startuje sam |
| — | **Zasilanie** nie wymaga uprawnień |
| Bluetooth | **Bluetooth** (podłączenie urządzeń i poziom baterii słuchawek) |
| Kalendarze | **Kalendarz** |
| Przypomnienia | **Przypomnienia** |
| Kamera | **Lusterko** (tylko gdy zakładka jest otwarta) |
| — | **Timer**, **Notatka**, **Historia schowka**, **Skróty** nie wymagają uprawnień |
| Automatyzacja: Muzyka, Spotify | **Teraz odtwarzane** w trybie awaryjnym AppleScript (system pyta przy pierwszym użyciu) |

Tabela rośnie wraz z kolejnymi modułami.

## Moduły

### Teraz odtwarzane

Okładka, tytuł, wykonawca, pasek przewijania i sterowanie dla dowolnej aplikacji odtwarzającej dźwięk
(Muzyka, Spotify, przeglądarki, podcasty). W zwiniętej wyspie: miniatura okładki i wizualizer w kolorze okładki.

W Ustawieniach → Moduły → Teraz odtwarzane wybierasz:

- **Pokazuj dźwięk z**: *Cały system* (każda aplikacja, w tym przeglądarki) albo *Tylko Apple Music*.
  W trybie *Tylko Apple Music* wyspa pokazuje Muzykę wtedy, gdy to ona jest bieżącym odtwarzaczem w systemie;
  gdy gra inna aplikacja, wyspa zachowuje się, jakby nic nie grało.
- **Źródło danych**: adapter MediaRemote albo AppleScript. Tam też widać, które źródło jest aktywne i dlaczego.

### Półka

Przeciągnij plik, obraz, link albo tekst nad notch: wyspa się rozwinie i pokaże półkę. Upuść na półkę, żeby odłożyć,
albo na pole AirDrop, żeby od razu wysłać.

- Klik zaznacza, ⌘-klik dodaje do zaznaczenia, ⇧-klik zaznacza zakres, dwuklik otwiera.
- Przeciągnij kafelek poza wyspę, żeby wyciągnąć plik (całe zaznaczenie naraz).
- Ikona oka: podgląd Quick Look zaznaczonych elementów. Prawy przycisk: Otwórz, Podgląd, Pokaż w Finderze, Usuń.
- Pliki z dysku zostają na swoim miejscu (półka trzyma tylko odnośnik i nadąża za przeniesieniem pliku).
  Obrazy i linki przeciągnięte z przeglądarki są kopiowane do `~/Library/Application Support/Wyspa/Shelf`.
- Półka przetrwa restart aplikacji i komputera. Usunięcie z półki nigdy nie kasuje Twoich oryginałów.

### HUD głośności i jasności

Klawisze głośności, wyciszenia, jasności ekranu i podświetlenia klawiatury pokazują poziom w wyspie zamiast
systemowego okienka. ⇧⌥ z klawiszem zmienia poziom drobniejszymi krokami, sam ⌥ otwiera ustawienia systemowe jak zwykle.
Każdy rodzaj można wyłączyć osobno w ustawieniach modułu. Urządzenia audio bez regulacji głośności (np. część
wyjść HDMI) zostają obsługiwane przez system.

### Zasilanie

Krótka aktywność w wyspie po podłączeniu i odłączeniu ładowarki, po pełnym naładowaniu i przy 20% oraz 10% baterii.
Zakładka z poziomem baterii i szacowanym czasem ładowania albo pracy.

### Bluetooth

Krótka aktywność po podłączeniu i odłączeniu urządzenia: ikona (AirPods, słuchawki, klawiatura, mysz…) i poziom baterii.
Zakładka z listą połączonych urządzeń i baterią lewej i prawej słuchawki oraz etui.

### Zakładki w wyspie

Ustawienia → Zakładki: przeciągnij moduły, żeby ustalić kolejność, i wyłącz zakładki, których nie chcesz widzieć
po najechaniu (moduł działa dalej, np. pokazuje aktywności w zwiniętej wyspie). Jeśli zakładek jest więcej, niż mieści
nagłówek, pozostałe są w menu ⋯; zakładka wybrana z menu pojawia się w pasku.

### Kalendarz i Przypomnienia

Plan dnia z przyciskiem „Dołącz” dla Meet, Zoom, Teams, Webex, Whereby, Jitsi i FaceTime. Na 10 minut przed spotkaniem
zwinięta wyspa pokazuje odliczanie. Przypomnienia: zaległe i na dziś, odhaczane jednym kliknięciem.

### Timer

Minutnik (gotowe 1–60 min albo dowolny czas), stoper i Pomodoro (25 min skupienia, 5 min przerwy, 15 min co 4 sesje).
Odliczanie widać w zwiniętej wyspie; koniec sygnalizuje dźwięk i rozwinięcie wyspy. Timer przetrwa restart aplikacji.

### Notatka

Kliknij w tekst, żeby pisać — dopiero wtedy wyspa przejmuje klawiaturę. Zapis automatyczny. Esc zwija wyspę i oddaje
klawiaturę poprzedniej aplikacji.

### Historia schowka

Ostatnie teksty, pliki i obrazy z wyszukiwaniem (bez rozróżniania polskich znaków). Kliknięcie kopiuje ponownie.
Hasła z menedżerów haseł (oznaczone jako poufne) i treści tymczasowe nie są zapisywane. Historia jest tylko w pamięci —
znika po wyłączeniu modułu albo aplikacji.

### Skróty i Lusterko

Skróty: ulubione Skróty macOS jako przyciski (wybór w ustawieniach modułu). Lusterko: podgląd z kamery;
kamera działa tylko, gdy zakładka Lusterka jest widoczna.

## Znane ograniczenia

- **MediaRemote (prywatne API)**: od macOS 15.4 Apple blokuje je zwykłym aplikacjom. Wyspa korzysta z
  [mediaremote-adapter](https://github.com/ungive/mediaremote-adapter) (BSD-3-Clause), który uruchamia je przez
  systemowy `/usr/bin/perl`. Kolejna wersja macOS może to zablokować albo usunąć Perla. Wtedy test adaptera nie przejdzie,
  a moduł sam przełączy się na AppleScript (tylko Muzyka i Spotify, bez przeglądarek). Aplikacja się nie wywali.
  Przetestowano na macOS 27.2 (26B5091g).
- **Prywatne API w HUD i Bluetooth**: jasność ekranu (DisplayServices), podświetlenie klawiatury (CoreBrightness)
  i bateria słuchawek (`IOBluetoothDevice.batteryPercent*`). Gdy nowa wersja macOS je usunie, odpowiednia funkcja
  się wyłączy (klawisze wrócą do systemowego HUD, urządzenie pokaże się bez poziomu baterii). Aplikacja się nie wywali.
- HUD jasności działa tylko dla wbudowanego ekranu (monitory zewnętrzne zostają przy systemie).
- Tryb skupienia nie jest obsługiwany (wymagałby pełnego dostępu do dysku).
- Półka: element, którego oryginał został usunięty, zostaje na półce wyszarzony, dopóki go nie usuniesz.
- Quick Look i AirDrop przenoszą Wyspę na pierwszy plan (systemowe okna potrzebują aktywnej aplikacji).
- Wizualizer w zwiniętej wyspie pokazuje rytm odtwarzania, nie rzeczywisty poziom dźwięku.

- Na monitorach bez notcha wyspa rysuje wirtualny notch. W trybie „Tylko gdy coś się dzieje”
  jest niewidoczna, dopóki nie najedziesz kursorem na środek górnej krawędzi ekranu.
- Haptyka działa tylko na gładzikach Force Touch i tylko wtedy, gdy palec dotyka gładzika.
- Start przy logowaniu najlepiej działa, gdy aplikacja leży w `/Applications`.

## Licencje zewnętrzne

- mediaremote-adapter © Jonas van den Berg i współtwórcy, BSD-3-Clause.
  Pełny tekst: `Vendor/mediaremote-adapter/LICENSE`, w pakiecie aplikacji `Contents/Resources/mediaremote-adapter/LICENSE`.

## Rozwój

Szczegóły architektury i komendy: [CLAUDE.md](CLAUDE.md).
