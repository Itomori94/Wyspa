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
scripts/install.sh         # buduje i instaluje /Applications/Wyspa.app, uruchamia ją
```

`dev-cert.sh` tworzy samopodpisany certyfikat „Wyspa Development” w pęku kluczy logowania.
Dzięki niemu macOS pamięta przyznane zgody po każdym ponownym zbudowaniu aplikacji.
Bez certyfikatu `build-app.sh` podpisze aplikację ad-hoc, a zgody trzeba będzie nadawać od nowa.

Przy pierwszym podpisie macOS może zapytać, czy `codesign` może użyć klucza — wybierz „Zawsze pozwalaj”.

## Obsługa

- **Najechanie** na notch: wyspa lekko się powiększa, po chwili rozwija (opóźnienie w ustawieniach).
- **Kliknięcie** albo **przesunięcie dwoma palcami w dół**: rozwija od razu. Kliknięcie aktywności (okładki, timera,
  Claude) otwiera stronę jej modułu — także w nagłówku rozwiniętej wyspy. Gdy moduł nie ma strony w układzie,
  jego widok pokazuje się doraźnie (np. prośba Claude o zgodę zawsze ma gdzie się wyświetlić). Gdy pod notchem wisi karta (powiadomienie, odpowiedź Claude), kliknięcie trafia do karty.
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
| Lokalizacja | **Pogoda** (okolica do ok. 1 km). Pytanie pojawia się przy włączeniu modułu |
| Dostępność | **HUD głośności i jasności** (przechwytywanie klawiszy) oraz **Powiadomienia** (odczyt banerów). Po nadaniu w Ustawieniach systemowych moduł startuje sam |
| — | **Zasilanie** nie wymaga uprawnień |
| Bluetooth | **Bluetooth** (podłączenie urządzeń i poziom baterii słuchawek) |
| Kalendarze | **Kalendarz** |
| Przypomnienia | **Przypomnienia** |
| Kamera | **Lusterko** (tylko gdy zakładka jest otwarta) |
| — | **Timer**, **Notatka**, **Historia schowka**, **Skróty** nie wymagają uprawnień |
| — | **Claude Code** nie wymaga uprawnień systemowych; instalacja hooków zmienia `~/.claude/settings.json` (z kopią zapasową) |
| Automatyzacja: Terminal, iTerm2 | **Claude Code**: przejście do właściwej karty terminala (system pyta przy pierwszym użyciu) |
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

Przy utworze z Apple Music w odtwarzaczu jest przycisk **AirPlay**: wybór głośników (MacBook, Apple TV, HomePod),
dźwięk przechodzi wyłącznie na wybrany głośnik.

Muzyka grająca przez AirPlay (np. na Apple TV) nie jest widoczna dla MediaRemote — wtedy wyspa bierze dane wprost
z aplikacji Muzyka (AppleScript, bez odpytywania). Przy pierwszym razie macOS zapyta o zgodę na sterowanie Muzyką.
Utwory z subskrypcji Apple Music nie mają wtedy okładki na dysku — Wyspa szuka jej w katalogu iTunes
(itunes.apple.com, wysyłane są tylko wykonawca i tytuł; najwyżej jedno zapytanie na utwór).

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
systemowego okienka: ikona po lewej stronie notcha, procent po prawej, a jeden pasek poziomu wysuwa się
wyśrodkowany tuż pod notchem. ⇧⌥ z klawiszem zmienia poziom drobniejszymi krokami, sam ⌥ otwiera ustawienia systemowe jak zwykle.
Każdy rodzaj można wyłączyć osobno w ustawieniach modułu. Urządzenia audio bez regulacji głośności (np. część
wyjść HDMI) zostają obsługiwane przez system.

### Zasilanie

Krótka aktywność w wyspie po podłączeniu i odłączeniu ładowarki, po pełnym naładowaniu i przy 20% oraz 10% baterii.
Zakładka z poziomem baterii i szacowanym czasem ładowania albo pracy.

### Bluetooth

Krótka aktywność po podłączeniu i odłączeniu urządzenia: ikona (AirPods, słuchawki, klawiatura, mysz…) i poziom baterii.
Zakładka z listą połączonych urządzeń i baterią lewej i prawej słuchawki oraz etui.
Gdy bateria urządzenia spadnie do 20%, wyspa pokazuje czerwone ostrzeżenie — raz na rozładowanie (ponownie po
naładowaniu powyżej 30%). Poziom jest odczytywany co 5 minut, tylko gdy podłączone jest urządzenie podające baterię.
Baterii iPhone'a macOS nie udostępnia publicznie, więc Wyspa jej nie pokazuje.

### Układ wyspy

Ustawienia → Układ to graficzny edytor rozwiniętej wyspy, podobny do NotchNook:

- **Strony**: wyspa ma jedną albo kilka stron. Strona z widżetami pokazuje kilka modułów obok siebie
  (np. odtwarzacz, kalendarz i timer), a strona z pełnym widokiem — jeden moduł na całą szerokość (np. półka).
  Między stronami przełączasz się przesunięciem w poziomie albo ikonami w nagłówku wyspy.
- **Podgląd w skali**: edytor rysuje wyspę w Twoim rozmiarze, z zaznaczonym notchem i prawdziwymi widżetami.
- **Przeciąganie**: moduł z listy poniżej przeciągnij na stronę; widżety przeciągaj, żeby zmienić kolejność albo
  przenieść na inną stronę (upuść na nazwie strony u góry); przeciągnij widżet z powrotem na listę, żeby go usunąć.
- **Szerokość**: przeciągnij uchwyt między widżetami — szerokość zmienia się płynnie, a w trakcie widać procent.
  Każdy widżet ma minimalną szerokość; edytor nie pozwoli zwęzić go bardziej.
- Odtwarzacz na dużej szerokości (np. sam na stronie) wygląda jak pełny odtwarzacz z paskiem przewijania.
- Nowo włączony moduł dołącza do ostatniej strony z widżetami (najwyżej trzy na stronę), a odtwarzacz, półka
  i schowek dostają własne strony. **Uporządkuj automatycznie** układa wszystko od nowa według tych reguł.

### Kalendarz i Przypomnienia

Plan dnia z przyciskiem „Dołącz” dla Meet, Zoom, Teams, Webex, Whereby, Jitsi i FaceTime. Na 10 minut przed spotkaniem
zwinięta wyspa pokazuje odliczanie. Przypomnienia: zaległe i na dziś, odhaczane jednym kliknięciem.

### Timer

Minutnik (gotowe 1–60 min albo dowolny czas), stoper i Pomodoro (25 min skupienia, 5 min przerwy, 15 min co 4 sesje).
Odliczanie widać w zwiniętej wyspie; koniec sygnalizuje dźwięk i rozwinięcie wyspy. Timer przetrwa restart aplikacji.
W trybie Pomodoro widać dzisiejszy wynik: kropki ukończonych sesji skupienia i minuty (liczą się tylko fazy
dobiegnięte do końca); dzienny cel ustawiasz w ustawieniach modułu.

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

### Powiadomienia

Wyłączony domyślnie, wymaga Dostępności. Powiadomienia macOS pojawiają się jako karta pod notchem: ikona i nazwa
aplikacji, tytuł, treść. Karta znika po kilku sekundach (czas w ustawieniach), najechanie ją zatrzymuje, kliknięcie
otwiera aplikację, kolejne powiadomienia czekają w kolejce („+2”). Systemowy baner jest domyślnie chowany
(do wyłączenia w ustawieniach) — powiadomienie i tak zostaje w Centrum powiadomień.

### Claude Code

Podgląd sesji Claude Code w wyspie: projekt, stan (pracuje, używa narzędzia, prosi o zgodę, czeka na Ciebie, skończyła)
i ostatnie narzędzia. Kilka sesji naraz.

- **Instalacja**: Ustawienia → Moduły → Claude Code → *Zainstaluj hooki*. Wyspa dopisuje swoje wpisy do
  `~/.claude/settings.json`, robiąc obok kopię zapasową; Twoje inne hooki zostają. *Odinstaluj* usuwa tylko wpisy Wyspy.
  Po przeniesieniu aplikacji (np. do /Applications) kliknij *Zaktualizuj ścieżkę*.
- **Zgody z wyspy**: prośba o uprawnienie rozwija wyspę i pokazuje narzędzie z podglądem (polecenie, diff edycji,
  początek nowego pliku). *Zezwól*, *Odrzuć* albo *W terminalu*. Brak decyzji w ustalonym czasie (domyślnie 5 min)
  albo wyłączona Wyspa = zwykły prompt w terminalu, jak bez Wyspy.
- **Dźwięk i pulsowanie**, gdy sesja czeka albo kończy; cisza, gdy terminal tej sesji jest na wierzchu.
- **Podgląd odpowiedzi**: po zakończeniu pracy pod notchem pojawia się karta z początkiem odpowiedzi Claude;
  kliknięcie przenosi do terminala, najechanie zatrzymuje kartę. Na liście sesji widać, od kiedy sesja pracuje.
- **Kliknięcie sesji** przenosi do jej terminala: właściwa karta w Terminalu i iTerm2, właściwe okno w VS Code i Cursor;
  w innych terminalach aplikacja przechodzi na wierzch.

### Pogoda

Temperatura, opis i prognoza na 4 dni dla Twojej okolicy z Open-Meteo (darmowy serwis bez konta). Wymaga zgody na
lokalizację; do serwisu trafiają tylko współrzędne zaokrąglone do ok. 1 km. Dane odświeżają się przy otwarciu wyspy,
gdy mają ponad 15 minut — bez zegara w tle. Kliknięcie pogody otwiera aplikację Pogoda. Opcjonalnie temperatura
w zwiniętej wyspie (domyślnie wyłączona).

### Szybkie akcje

Strona albo widżet z czterema przyciskami:
- **Zrzut na Półkę**: zaznaczasz obszar ekranu, zrzut ląduje na Półce (gdy Półka jest wyłączona — w schowku).
  Przy pierwszym użyciu macOS zapyta o zgodę na nagrywanie ekranu dla Wyspy.
- **Pipeta koloru**: systemowa pipeta, kod HEX koloru trafia do schowka.
- **Zablokuj ekran**: od razu blokuje Maca.
- **Nie usypiaj**: Mac i ekran nie zasypiają (jak `caffeinate -d`), dopóki nie klikniesz ponownie albo nie wyłączysz modułu.

Każdej akcji możesz przypisać globalny skrót klawiszowy w ustawieniach modułu (domyślnie brak); skróty działają
tylko przy włączonym module.

## Znane ograniczenia

- **Powiadomienia**: Wyspa czyta banery z drzewa Dostępności — Apple go nie dokumentuje, więc nowa wersja macOS może
  to zepsuć (wtedy powiadomienia po prostu wracają do zwykłych banerów). Przyciski akcji („Odpowiedz”, „Zaakceptuj”)
  działają tylko w systemowym banerze. Aplikację do otwarcia rozpoznajemy po nazwie wśród działających aplikacji —
  jeśli nie działa, kliknięcie tylko zamyka kartę. Tryb Skupienia nie jest odczytywany (wymagałby pełnego dostępu
  do dysku), ale wyciszone powiadomienia i tak nie pokazują banera, więc nie trafiają do wyspy.

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
Spis tekstów okna ustawień: [docs/teksty-ustawien.md](docs/teksty-ustawien.md).
