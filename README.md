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
| — | Fundament wyspy (etap 1) nie wymaga żadnych uprawnień |

Tabela rośnie wraz z kolejnymi modułami.

## Znane ograniczenia

- Na monitorach bez notcha wyspa rysuje wirtualny notch. W trybie „Tylko gdy coś się dzieje”
  jest niewidoczna, dopóki nie najedziesz kursorem na środek górnej krawędzi ekranu.
- Haptyka działa tylko na gładzikach Force Touch i tylko wtedy, gdy palec dotyka gładzika.
- Start przy logowaniu najlepiej działa, gdy aplikacja leży w `/Applications`.

## Rozwój

Szczegóły architektury i komendy: [CLAUDE.md](CLAUDE.md).
