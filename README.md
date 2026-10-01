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

## Znane ograniczenia

- **MediaRemote (prywatne API)**: od macOS 15.4 Apple blokuje je zwykłym aplikacjom. Wyspa korzysta z
  [mediaremote-adapter](https://github.com/ungive/mediaremote-adapter) (BSD-3-Clause), który uruchamia je przez
  systemowy `/usr/bin/perl`. Kolejna wersja macOS może to zablokować albo usunąć Perla. Wtedy test adaptera nie przejdzie,
  a moduł sam przełączy się na AppleScript (tylko Muzyka i Spotify, bez przeglądarek). Aplikacja się nie wywali.
  Przetestowano na macOS 27.2 (26B5091g).
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
