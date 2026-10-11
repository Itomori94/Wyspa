# Teksty w Ustawieniach Wyspy

Spis tekstów widocznych w oknie **Ustawienia Wyspy** (stan na 10 października 2026). Przy zmianie tekstów w kodzie
zaktualizuj też ten plik. Karty okna: **Ogólne · Wyspa · Moduły · Układ · Szybkie akcje**.

## Menu Wyspy (ikona w pasku menu)

- „Ustawienia…” · „Sprawdź aktualizacje…” · „Wersja …” (nieaktywna, zainstalowany commit) · „Wesprzyj autora…” (otwiera suppi.pl/itomori94) · „Zakończ Wyspę”
- Okienka „Sprawdź aktualizacje…”: „Dostępna nowa wersja Wyspy” (… zmian: lista najwyżej 6, „… i … więcej”; „Aktualizacja
  pobierze zmiany, zbuduje i zainstaluje Wyspę (budowanie trwa kilka minut) — potem aplikacja zamknie się i uruchomi
  ponownie sama.”; „Zaktualizuj teraz” / „Później”) · „Masz najnowszą wersję Wyspy” („Zainstalowana wersja: …”) ·
  „Nie udało się sprawdzić aktualizacji”
- Okienko **Aktualizacja Wyspy** (po „Zaktualizuj teraz” z menu albo z ustawień modułu): „Aktualizowanie Wyspy” · „Wyspa
  zbuduje nową wersję, zamknie się i uruchomi ponownie sama — nie trzeba jej wyłączać. Budowanie trwa zwykle kilka
  minut.” · etapy „Pobieranie zmian” / „Budowanie nowej wersji” / „Instalowanie” / „Ponowne uruchamianie” (bieżący
  z czasem trwania) · po błędzie „Aktualizacja się nie udała” + opis (jak w module Aktualizacje), „Pokaż przebieg”, „Zamknij”
- Po ponownym uruchomieniu po aktualizacji: „Wyspa została zaktualizowana” („Masz najnowszą wersję: ….” + „Zmiany:” i lista)
  albo „Aktualizacja się nie udała” („Wyspa uruchomiła się w poprzedniej wersji. Przebieg: ~/Library/Logs/Wyspa/aktualizacja.log.”)

## Ogólne i Wyspa

- Uruchamiaj przy logowaniu · „Zatwierdź w Ustawieniach systemowych…”
- **Skrót klawiszowy**: „Rozwiń lub zwiń wyspę”
- **Ekrany**
  - Pokazuj wyspę: Na wszystkich ekranach / Tylko na ekranie z notchem / Tylko na ekranie głównym
  - Wirtualny notch: Zawsze widoczny / Tylko gdy coś się dzieje
  - „Na monitorach bez notcha wyspa rysuje wirtualny notch pod paskiem menu.”
- **Rozwijanie**
  - Rozwijaj po najechaniu kursorem · Skrzydła ustępują ikonom paska menu („Najechanie na skrzydło wyspy (obok notcha)
    chowa je, żeby odsłonić ikony paska menu pod spodem; wracają, gdy kursor zjedzie z paska. Najechanie na sam notch
    dalej rozwija wyspę.”) · Opóźnienie rozwinięcia · Opóźnienie zwinięcia
  - „Kliknięcie albo przesunięcie dwoma palcami w dół zawsze rozwija wyspę, w górę ją zwija.”
- **Wygląd** (karta Wyspa)
  - Rozmiar rozwiniętej wyspy: Mała / Średnia / Duża
  - Motyw: Klasyczny / Czarna tafla / Szkło / Przezroczysty · przy Szkle „Przyciemnienie szkła” (suwak) · podpowiedź:
    „Czarna wyspa, widżety rozdzielone kreskami.” / „Czarna wyspa z cienką jasną krawędzią, zakładki w kapsule, widżety
    na osobnych kartach.” / „Rozwinięta wyspa i karty z rozmytego szkła; przy samym notchu wyspa zostaje czarna.” /
    „Rozwinięta wyspa i karty z przezroczystego szkła Liquid Glass, jak Centrum sterowania; przy samym notchu wyspa
    zostaje czarna.” (macOS starszy niż 26: „Liquid Glass wymaga macOS 26 — na tym systemie rozwinięta wyspa i karty są
    z rozmytego szkła bez przyciemnienia; przy samym notchu wyspa zostaje czarna.”)
  - Haptyka gładzika przy rozwinięciu · Siła stuknięcia: Delikatna / Średnia / Mocna (wybór od razu stuka próbnie) ·
    „Stuknięcie czuć, gdy palec dotyka gładzika. Średnia i Mocna korzystają z nieoficjalnego interfejsu macOS — gdyby
    przestał działać, Wyspa stuknie delikatnie.”
- **Tryb prywatny**: „Ukrywaj powiadomienia, schowek i odpowiedzi Claude”: Przy udostępnianiu i nagrywaniu ekranu / Zawsze / Nigdy
  - „Przy udostępnianiu albo nagrywaniu ekranu (Zoom, Teams, Meet, nagranie) karty pokazują tylko nazwę aplikacji.”
- **Wsparcie**: „Wesprzyj autora na Suppi” (link) · „Wyspa jest darmowa i open source. Jeśli się przydaje, możesz postawić autorowi kawę.”

## Moduły

- „Wyłączony moduł nie działa w tle i nie prosi o uprawnienia.”
- „Wymaga: …” + przycisk „Otwórz: …” (Dostępność, Kalendarze, Przypomnienia, Kamera, Bluetooth, Lokalizacja)
- Pusty katalog: „Brak modułów” — „Ta wersja Wyspy nie zawiera żadnych modułów.”

| Moduł | Opis |
|---|---|
| Teraz odtwarzane | Okładka, tytuł, pasek przewijania i sterowanie odtwarzaniem — z całego systemu albo tylko z Apple Music. |
| Półka | Przeciągnij plik nad notch, odłóż go na później i wyciągnij, kiedy będzie potrzebny. Z podglądem i AirDrop. |
| Pobierania | Pasek postępu pobieranego pliku w zwiniętej wyspie; po zakończeniu plik ląduje na Półce. |
| Kalendarz | Plan dnia i najbliższe spotkanie w zwiniętej wyspie na 10 minut przed startem, z przyciskiem „Dołącz”. |
| Pogoda | Temperatura i prognoza na kilka dni dla Twojej okolicy (Open-Meteo). Kliknięcie otwiera aplikację Pogoda. |
| Przypomnienia | Przypomnienia na dziś i zaległe; odhaczasz je jednym kliknięciem. |
| Timer | Minutnik, stoper i Pomodoro z odliczaniem widocznym w zwiniętej wyspie. |
| Notatka | Szybka notatka z autozapisem. Kliknij w tekst, żeby pisać; Esc zwija wyspę. |
| Historia schowka | Ostatnio kopiowane teksty, pliki i obrazy z wyszukiwaniem. Hasła z menedżerów haseł są pomijane. Historia jest tylko w pamięci. |
| Skróty | Uruchamia wybrane Skróty macOS jednym kliknięciem z wyspy. |
| Skrypty | Komenda wyspa i adresy wyspa:// — karty („Backup gotowy”) i paski postępu ze skryptów, Skrótów i crona. |
| Szybkie akcje | Zrzut zaznaczenia prosto na Półkę, tekst ze zrzutu do schowka, pipeta koloru (kopiuje HEX), blokada ekranu i „nie usypiaj Maca”. |
| Mikrofon | Wycisza wszystkie mikrofony globalnym skrótem (domyślnie ⌃⌥M). Wyciszony mikrofon to czerwona ikona w zwiniętej wyspie. |
| Aktualizacje | Sprawdza, czy na GitHubie jest nowsza wersja Wyspy, pokazuje listę zmian i aktualizuje jednym przyciskiem. |
| Lusterko | Podgląd z kamery przed rozmową wideo. Kamera włącza się tylko, gdy zakładka jest widoczna; obraz nie jest zapisywany. |
| Powiadomienia | Pokazuje powiadomienia macOS w wyspie zamiast w rogu ekranu. Najechanie zatrzymuje kartę, kliknięcie otwiera aplikację. |
| HUD głośności i jasności | Zamiast systemowego okienka pokazuje głośność, jasność ekranu i podświetlenie klawiatury w wyspie. |
| Zasilanie | Pokazuje podłączenie ładowarki, pełne naładowanie i niski poziom baterii. |
| Bluetooth | Pokazuje podłączenie słuchawek i innych urządzeń Bluetooth z poziomem ich baterii. |
| Claude Code | Sesje Claude Code: czy pracuje, jakiego narzędzia używa, czy czeka na Ciebie. Zatwierdzanie uprawnień z wyspy. |

## Układ (edytor)

- „Wyspa nie ma jeszcze stron” — „Dodaj stronę przyciskiem „+” i przeciągnij na nią widżety z listy poniżej.”
- „Wyspa „…”. Rozmiar zmienisz w karcie Wyspa — szerokości widżetów skalują się razem z nią.”
- **Uporządkuj automatycznie** — „Odtwarzacz, półka i schowek na osobnych stronach, pozostałe moduły po trzy widżety
  na stronę” · „Zastąp bieżący układ” · „Anuluj”
- Dodaj stronę: Strona z widżetami / Pełny widok modułu · „Pusta strona” · „Usuń stronę”
- „Kliknij, żeby edytować. Przeciągnij, żeby zmienić kolejność stron.”
- „Pełny widok: …” · „Przeciągnij tu widżety z listy poniżej” · „Przeciągnij, żeby zmienić szerokość widżetów”
- „… — włącz moduł” · „Usuń z wyspy”
- „Widżety — przeciągnij na wyspę. Przeciągnij widżet z wyspy tutaj, żeby go usunąć.”
- „Przeciągnij na stronę wyspy” · „Włącz moduł „…” w karcie Moduły”

## Ustawienia modułów

- **Teraz odtwarzane**
  - Pokazuj dźwięk z: Cały system / Tylko Apple Music — „Muzyka, filmy i podcasty z innych aplikacji nie będą
    pokazywane w wyspie.”
  - Gdy odtwarzanie nie działa: ostrzeżenie z powodem (np. „Brak plików adaptera w pakiecie aplikacji.”)
- **HUD** — Głośność / Jasność ekranu / Podświetlenie klawiatury
  - „⇧⌥ z klawiszem zmienia poziom drobniejszymi krokami. Sam ⌥ otwiera ustawienia systemowe.”
  - „Niedostępne: brak wbudowanego ekranu albo DisplayServices w tej wersji macOS.”
  - „Niedostępne: brak podświetlanej klawiatury albo CoreBrightness w tej wersji macOS.”
- **Powiadomienia**
  - „Chowaj systemowy baner (zostaje w Centrum powiadomień)” · Pokazuj przez: 3 / 5 / 8 / 10 / 15 s
  - „Podczas skupienia Pomodoro (Timer → „Wstrzymuj powiadomienia podczas skupienia”) karty czekają i przychodzą
    po sesji z podsumowaniem — gdy systemowy baner jest chowany. Bez chowania baner pokazuje system, a wyspa nie
    dubluje go kartą.”
  - „Przyciski z powiadomień (np. „Odpowiedz”) działają tylko w systemowym banerze — kliknięcie karty otwiera
    aplikację. Gdy nowa wersja macOS zmieni budowę banerów, moduł przestanie je widzieć, a powiadomienia działają
    zwyczajnie.”
- **Claude Code**
  - Hooki zainstalowane / Hooki niezainstalowane / Hooki wymagają aktualizacji / Sprawdzanie…
  - Zainstaluj hooki · Zaktualizuj ścieżkę · Odinstaluj… → „Usuń hooki Wyspy” / „Anuluj”
  - „Instalacja dopisuje wpisy Wyspy do ~/.claude/settings.json (z kopią zapasową obok pliku). Twoje inne hooki
    i ustawienia zostają. Gdy Wyspa nie działa albo została usunięta, hook kończy się od razu i nic nie zmienia. Przed usunięciem
    aplikacji kliknij „Odinstaluj…”.”
  - „Czas na decyzję w wyspie: … min” — „Po tym czasie (albo gdy Wyspa nie odpowie) decyzja wraca do zwykłego promptu
    w terminalu.”
  - „Limity planu (5 h i tydzień)”: Pokazuj limity / Wyłącz / „Masz własną linię statusu” — „Limity przekazuje linia
    statusu Claude Code (oficjalne dane planu Pro/Max). W terminalu pojawi się pasek „5h 23% · tydz. 41%”, a znikną
    z niego podpowiedzi klawiszy, np. „esc to interrupt”. Działa od następnej sesji.”
  - „Dźwięk, gdy sesja czeka albo kończy” · „Bez dźwięku, gdy terminal sesji jest na wierzchu”
- **Pobierania** — „Po zakończeniu odkładaj plik na Półkę” · „Działa z Safari, Chrome i innymi przeglądarkami, które
  pokazują postęp na ikonie pliku w Finderze. Na Półkę trafia odnośnik do pliku w Pobranych (wymaga włączonej Półki).”
- **Skrypty** — „Komenda wyspa zainstalowana w ~/.local/bin” + „Usuń komendę” / „Komenda wyspa jest starsza niż aplikacja” +
  „Zaktualizuj” / „Komenda wyspa nie jest zainstalowana.” + „Zainstaluj w ~/.local/bin” / „~/.local/bin/wyspa to inny program —
  Wyspa go nie nadpisze.” · podpowiedź o PATH, przykłady poleceń · „Gdy Wyspa nie działa, komenda kończy się po cichu z kodem 0. …”
- **Mikrofon** — „Dźwięk przy wyciszeniu i włączeniu” · „Wycisz / włącz mikrofon” (skrót) · „„…” nie pozwala się wyciszyć ani zmienić głośności wejścia.” ·
  „Wyciszane są wszystkie mikrofony naraz — także ten, który Zoom, Teams czy Discord wybrały inaczej niż system, i ten
  podłączony w trakcie wyciszenia. Gdy mikrofon nie ma przełącznika wyciszenia, Wyspa ustawia głośność wejścia na zero
  i przywraca ją po włączeniu. Wyspa nie słucha dźwięku z mikrofonu.” · lista mikrofonów (nazwa, „· systemowy”, ikona stanu) · „„…” nie pozwala się wyciszyć ani zmienić głośności wejścia.” ·
  widżet: nazwa mikrofonu albo „Wszystkie mikrofony (…)”
- **Aktualizacje** — „Zainstalowana wersja: … (z niezapisanymi zmianami)” · „Sprawdzanie…” / „Masz najnowszą wersję” /
  „Dostępna nowa wersja: … zmian” + lista (najwyżej 8, „… i … więcej”) / „<etap>… Wyspa uruchomi się ponownie sama.”
  (np. „Budowanie nowej wersji…”) / błędy („Ta kopia Wyspy nie została zbudowana z repozytorium git — nie ma z czym
  porównać.”, „Brak połączenia z GitHubem.”, „GitHub zwrócił nieoczekiwaną odpowiedź.”, „Nie ma katalogu projektu (…) — …”,
  „W katalogu projektu aktywna jest gałąź „…”, a nie master — zaktualizuj ręcznie.”, „W katalogu projektu są niezapisane
  zmiany — …”, „Nie udało się pobrać zmian (git pull): …”, „Nie udało się uruchomić instalacji: …”, „Instalacja nie
  powiodła się na etapie „…” — działa poprzednia wersja. Przebieg: ~/Library/Logs/Wyspa/aktualizacja.log.”, „Nowa wersja
  jest zainstalowana, ale ta kopia Wyspy się nie zamknęła — zamknij ją i uruchom ponownie.”) · „Sprawdź teraz” ·
  „Zaktualizuj teraz” · „GitHub” · „Aktualizacja pobiera zmiany do katalogu projektu (git pull), buduje i instaluje
  Wyspę — aplikacja zamknie się i uruchomi ponownie. Przebieg: ~/Library/Logs/Wyspa/aktualizacja.log. Sprawdzanie: przy
  starcie i co 6 godzin.” · karta w wyspie: „Nowa wersja Wyspy · … zmian”
- **Historia schowka** — „Zapamiętuj … wpisów” · „Wyczyść historię” · „Kliknięcie wkleja do aktywnej aplikacji” ·
  „Wklejanie wymaga uprawnienia Dostępność — bez niego kliknięcie tylko kopiuje.” + „Otwórz: Dostępność” ·
  „Przypięte wpisy (pinezka przy wpisie) nie wypadają z historii i zostają po „Wyczyść”. Cała historia, także przypięta,
  jest tylko w pamięci i znika po zamknięciu Wyspy.”
- **Timer** — „Dzienny cel Pomodoro: brak / … sesji” · „Wstrzymuj powiadomienia podczas skupienia” · „Gdy trwa faza
  skupienia Pomodoro, karty powiadomień w wyspie czekają i przychodzą po jej końcu z podsumowaniem. Działa z włączonym
  modułem Powiadomienia i chowaniem systemowego banera.”
- **Pogoda** — „Temperatura w zwiniętej wyspie” · „Dane z Open-Meteo (bez konta). Wysyłane są tylko współrzędne
  zaokrąglone do ok. 1 km; odświeżanie przy otwarciu wyspy, gdy dane mają ponad 15 minut. Kliknięcie pogody otwiera
  aplikację Pogoda.”
- **Szybkie akcje** (osobna karta; w karcie Moduły: „Kafelki i skróty ustawisz w karcie „Szybkie akcje”.”)
  - „Kafelki w wyspie”: 8 miejsc, w każdym lista akcji (Zrzut na Półkę / Zrzut całego ekranu / Tekst ze zrzutu /
    Nagrywanie ekranu / Pipeta koloru / Generator hasła / Tryb ciemny (przełącz) / Ikony na biurku (przełącz) /
    Zablokuj ekran / Nie usypiaj (przełącz)) i przełącznik · „Wybór akcji, która jest już w innym miejscu, zamienia je
    miejscami. Najmniej 2 kafelki muszą zostać włączone.”
  - „Skróty klawiszowe” (wszystkie akcje) · „Skróty działają w całym systemie, także przy zwiniętej wyspie.”
  - Moduł wyłączony: „Szybkie akcje są wyłączone” — „Włącz moduł „Szybkie akcje” w karcie Moduły.”
- **Skróty** — „Nie masz jeszcze żadnych skrótów. Utwórz je w aplikacji Skróty.” · „Ulubione (pokazywane w wyspie;
  bez ulubionych widać wszystkie)” · „Uruchom skrót „…”” · „Odśwież”
