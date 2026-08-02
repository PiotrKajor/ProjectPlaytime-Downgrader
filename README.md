# PROJECT: PLAYTIME — Downgrader

Instalator starszych kompilacji gry PROJECT: PLAYTIME z interfejsem tekstowym.
Pobiera wybraną wersję bezpośrednio z serwerów Steam, podmienia pliki gry
i konfiguruje klienta tak, aby **przycisk „Graj" uruchamiał starszą wersję
zamiast pobierać aktualizację**.

Jeden plik do uruchomienia, zero konfiguracji, zero zależności do zainstalowania.

```
════════════════════════════════════════════════════════════════════
  PROJECT: PLAYTIME  ·  DOWNGRADER                          v1.0.0
════════════════════════════════════════════════════════════════════
  Pobieranie zawartości

  Faza 2 · Incineration  (bez EasyAntiCheat)
  manifest 1265526790874008598   ·   depot 1961461

  [████████████████████████████▊░░░░░░░░░░░░░░░░░░░░░]   43,72 %

    Pobrano   5,24 GB / 12,01 GB     Prędkość  18,4 MB/s
    Czas      00:04:51               Pozostało 00:06:15

  ⠹  Poppy/Content/Paks/pakchunk3-WindowsNoEditor.pak

  ┌─ Dziennik ──────────────────────────────────────────────────┐
  │ Poppy/Content/Paks/pakchunk1-WindowsNoEditor.sig            │
  │ Poppy/Content/Paks/pakchunk2-WindowsNoEditor.pak            │
  └─────────────────────────────────────────────────────────────┘
```

## Uruchomienie

Pobierz repozytorium i kliknij dwukrotnie **`Start.bat`**. To wszystko.

DepotDownloader zostanie pobrany automatycznie przy pierwszym uruchomieniu.

## Przycisk „Graj" — jak to działa

Standardowe poradniki kończą się radą „nie naciskaj Graj w Steam, uruchamiaj
grę z pliku .exe". Nie jest to konieczne.

Klient Steam **nie sprawdza zawartości katalogu gry**. Aby zdecydować, czy
potrzebna jest aktualizacja, porównuje wyłącznie metadane z pliku
`appmanifest_1961460.acf` z informacjami o grze pobranymi z serwera. Weryfikacja
plików na dysku następuje dopiero po ręcznym uruchomieniu opcji
_Sprawdź spójność plików gry_.

Program zapisuje więc w appmanifest stan „instalacja kompletna i aktualna",
podczas gdy na dysku znajdują się pliki starszej kompilacji:

| Wpis | Wartość | Znaczenie |
|---|---|---|
| `buildid` | bieżąca kompilacja publiczna | Steam uznaje instalację za aktualną |
| `StateFlags` | `4` | stan „w pełni zainstalowana" |
| `TargetBuildID` | `0` | brak zaplanowanej aktualizacji docelowej |
| `AutoUpdateBehavior` | `1` | brak aktualizacji w tle |
| `ScheduledAutoUpdate` | `0` | usunięcie zaplanowanego zadania |

Efekt: przycisk **Graj** uruchamia grę natychmiast, bez pobierania czegokolwiek.

W przypadku tej konkretnej gry rozwiązanie jest wyjątkowo trwałe — ostatnia
publiczna aktualizacja PROJECT: PLAYTIME miała miejsce **30 października 2023**
(build `12576441`). Dopóki nie pojawi się nowa kompilacja, identyfikator się nie
zmienia i konfiguracja pozostaje ważna bezterminowo. Gdyby gra kiedyś dostała
łatkę, wystarczy użyć pozycji _Napraw przycisk „Graj"_ — program odpyta
`api.steamcmd.net` o aktualny identyfikator i zapisze go ponownie.

**Jedyne, czego nie wolno zrobić:** uruchomić w Steam opcji _Sprawdź spójność
plików gry_. Wykrywa ona różnicę i pobiera wersję aktualną.

## Funkcje

| Pozycja menu | Opis |
|---|---|
| Zainstaluj starszą wersję | Pobranie kompilacji i podmiana plików wraz z kopią zapasową |
| Napraw przycisk „Graj" | Ponowne zapisanie metadanych, gdy Steam zaplanował aktualizację |
| Przywróć wersję z kopii zapasowej | Powrót do stanu sprzed operacji |
| Kopie zapasowe | Przegląd i usuwanie kopii w celu zwolnienia miejsca |
| Diagnostyka | Wykrycie Steam, biblioteki, kompilacji i wolnego miejsca |

## Dostępne kompilacje

| Wersja | Manifest |
|---|---|
| Faza 2 · Incineration (bez EasyAntiCheat) | `1265526790874008598` |
| Faza 2 · Incineration (z EasyAntiCheat) | `1362072626294775891` |

W menu można także podać dowolny inny identyfikator. Pełna lista kompilacji wraz
z datami: [SteamDB — depot 1961461](https://steamdb.info/depot/1961461/manifests/).

## Wymagania

- Windows 10 lub 11
- Windows PowerShell 5.1 (element systemu) albo PowerShell 7
- Konto Steam z grą w bibliotece — gra jest darmowa, wystarczy ją dodać
- Gra zainstalowana przez klienta Steam, aby istniał plik `appmanifest`
- Około 14 GB wolnego miejsca (pobranie plus kopia zapasowa)

## Logowanie

Uwierzytelnianie realizuje [DepotDownloader](https://github.com/SteamRE/DepotDownloader)
(projekt SteamRE). Hasło i kod Steam Guard wpisywane są bezpośrednio w oknie tego
narzędzia — repozytorium nie zawiera kodu obsługującego hasła i nigdzie ich nie
zapisuje.

Dostępne są dwa tryby:

- **Nazwa użytkownika i hasło** — zalecany. Logowanie odbywa się raz, w osobnym
  kroku, dzięki czemu właściwe pobieranie może działać z pełnym interfejsem
  postępu.
- **Kod QR** — bez wpisywania hasła, potwierdzenie w aplikacji Steam Mobile.
  W tym trybie postęp wyświetlany jest w formie tekstowej, ponieważ kod QR
  i pobieranie muszą odbyć się w jednym procesie.

## Struktura repozytorium

```
Start.bat                    punkt wejścia
src/
  PJPT-Downgrader.ps1        przebieg aplikacji i ekrany
  Tui.ps1                    ramki, menu, paski postępu, animacje
  Steam.ps1                  wykrywanie instalacji, appmanifest, podmiana katalogu
  Depot.ps1                  DepotDownloader, logowanie, parsowanie postępu
docs/
  JAK-TO-DZIALA.md           szczegóły techniczne
tools/                       DepotDownloader (pobierany automatycznie)
logs/                        dzienniki sesji
```

## Metoda alternatywna — konsola Steam

Bez żadnych narzędzi zewnętrznych. Wolniejsze, bez podglądu postępu i wymaga
ręcznej podmiany katalogu:

```
steam://open/console
```

```
download_depot 1961460 1961461 1265526790874008598
```

Pliki trafiają do `steamapps\content\app_1961460\depot_1961461`.

## Uwagi

- Rozgrywka sieciowa wymaga tej samej kompilacji u wszystkich uczestników.
- Klient Steam musi działać w tle, aby gra rozpoznała konto.
- Program nie modyfikuje plików gry ani nie omija zabezpieczeń — pobiera
  wyłącznie zawartość udostępnianą przez Steam dla posiadanego konta.

## Licencja

MIT
