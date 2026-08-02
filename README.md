<div align="center">

<img src="assets/banner.png" alt="PROJECT: PLAYTIME Downgrader" width="100%">

<br>

![Windows](https://img.shields.io/badge/Windows-10%20%7C%2011-0078D4?style=for-the-badge&logo=windows11&logoColor=white)
![PowerShell](https://img.shields.io/badge/PowerShell-5.1%2B-5391FE?style=for-the-badge&logo=powershell&logoColor=white)
![Wersja](https://img.shields.io/badge/wersja-1.0.0-D42E33?style=for-the-badge)
![Licencja](https://img.shields.io/badge/licencja-MIT-ECB524?style=for-the-badge)

**Instalator starszych kompilacji gry PROJECT: PLAYTIME.**
Pobiera wybraną wersję prosto z serwerów Steam, podmienia pliki
i sprawia, że **przycisk „Graj” uruchamia ją zamiast pobierać aktualizację**.

Jeden plik do kliknięcia. Zero konfiguracji, zero zależności do zainstalowania.

</div>

---

## Interfejs

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

Menu obsługiwane strzałkami, ekran diagnostyki z animowaną listą kroków,
pasek postępu o rozdzielczości ósmej części znaku, pomiar przepustowości
i czasu pozostałego, przewijany dziennik pobieranych plików.

---

## Uruchomienie

> **Pobierz repozytorium i kliknij dwukrotnie `Start.bat`.**
> DepotDownloader pobierze się sam przy pierwszym uruchomieniu.

Albo z konsoli:

```bash
powershell -ExecutionPolicy Bypass -File .\src\PJPT-Downgrader.ps1
```

---

## Przycisk „Graj” — sedno sprawy

Poradniki krążące po sieci kończą się radą: _nie naciskaj „Graj” w Steam,
uruchamiaj grę z pliku `.exe`_. Nie jest to konieczne.

Klient Steam **nie sprawdza zawartości katalogu gry**. Decydując o aktualizacji,
porównuje wyłącznie metadane z pliku `appmanifest_1961460.acf` z informacjami
pobranymi z serwera. Sumy kontrolne plików liczy dopiero po ręcznym uruchomieniu
opcji _Sprawdź spójność plików gry_.

Program zapisuje więc w appmanifest stan „instalacja kompletna i aktualna”,
podczas gdy na dysku leżą pliki starszej kompilacji:

| Wpis | Wartość | Znaczenie |
|:--|:--|:--|
| `buildid` | bieżąca kompilacja publiczna | Steam uznaje instalację za aktualną |
| `StateFlags` | `4` | stan „w pełni zainstalowana” |
| `TargetBuildID` | `0` | brak zaplanowanej kompilacji docelowej |
| `AutoUpdateBehavior` | `1` | brak aktualizacji w tle |
| `ScheduledAutoUpdate` | `0` | usunięcie zaplanowanego zadania |

Efekt: **Graj** uruchamia grę natychmiast, bez pobierania czegokolwiek.

W przypadku tej gry rozwiązanie jest wyjątkowo trwałe. Ostatnia publiczna
aktualizacja PROJECT: PLAYTIME miała miejsce **30 października 2023** (build
`12576441`). Dopóki nie pojawi się nowa kompilacja, identyfikator się nie zmienia
i konfiguracja obowiązuje bezterminowo. Po ewentualnej łatce wystarczy pozycja
menu _Napraw przycisk „Graj”_ — program odpyta `api.steamcmd.net` o aktualny
identyfikator i zapisze go ponownie.

> [!WARNING]
> Jedyna operacja cofająca cały zabieg to **Sprawdź spójność plików gry**
> w kliencie Steam. Wykrywa różnicę i pobiera wersję aktualną.

---

## Funkcje

| Pozycja menu | Opis |
|:--|:--|
| **Zainstaluj starszą wersję** | Pobranie kompilacji i podmiana plików wraz z kopią zapasową |
| **Napraw przycisk „Graj”** | Ponowne zapisanie metadanych, gdy Steam zaplanował aktualizację |
| **Przywróć wersję z kopii zapasowej** | Powrót do stanu sprzed operacji |
| **Kopie zapasowe** | Przegląd i usuwanie kopii w celu zwolnienia miejsca |
| **Diagnostyka** | Wykrycie Steam, biblioteki, kompilacji i wolnego miejsca |

## Dostępne kompilacje

| Wersja | Manifest |
|:--|:--|
| Faza 2 · Incineration — bez EasyAntiCheat | `1265526790874008598` |
| Faza 2 · Incineration — z EasyAntiCheat | `1362072626294775891` |

W menu można podać dowolny inny identyfikator. Pełna lista kompilacji wraz
z datami: [SteamDB — depot 1961461](https://steamdb.info/depot/1961461/manifests/).

<div align="center">

| App ID | Depot ID | Rozmiar pobierania |
|:--:|:--:|:--:|
| `1961460` | `1961461` | ~12 GB |

</div>

---

## Wymagania

- Windows 10 lub 11
- Windows PowerShell 5.1 (element systemu) albo PowerShell 7
- Konto Steam z grą w bibliotece — gra jest darmowa, wystarczy ją dodać
- Gra zainstalowana przez klienta Steam, aby istniał plik `appmanifest`
- Około 14 GB wolnego miejsca (pobranie plus kopia zapasowa)

## Logowanie

Uwierzytelnianie realizuje [DepotDownloader](https://github.com/SteamRE/DepotDownloader)
(projekt SteamRE). Hasło i kod Steam Guard wpisywane są bezpośrednio w oknie tego
narzędzia — repozytorium nie zawiera kodu obsługującego hasła i nigdzie ich nie zapisuje.

| Tryb | Postęp | Uwagi |
|:--|:--|:--|
| **Nazwa użytkownika i hasło** | pełny interfejs | Zalecany. Logowanie w osobnym kroku |
| **Kod QR** | tryb tekstowy | Bez hasła, potwierdzenie w Steam Mobile |

Różnica wynika z ograniczenia DepotDownloadera: hasło czytane jest przez
`Console.ReadKey`, co przy przekierowanym wejściu kończy się wyjątkiem. Nie da się
więc jednocześnie obsłużyć logowania i przechwytywać wyjścia na potrzeby paska
postępu. Tryb z nazwą użytkownika rozdziela oba etapy na dwa uruchomienia,
tryb QR musi zmieścić się w jednym.

---

## Struktura repozytorium

```
Start.bat                    punkt wejścia
src/
  PJPT-Downgrader.ps1        przebieg aplikacji i ekrany
  Tui.ps1                    ramki, menu, paski postępu, animacje
  Steam.ps1                  wykrywanie instalacji, appmanifest, podmiana katalogu
  Depot.ps1                  DepotDownloader, logowanie, parsowanie postępu
assets/                      logo i grafika repozytorium
docs/
  JAK-TO-DZIALA.md           szczegóły techniczne
tools/                       DepotDownloader (pobierany automatycznie)
logs/                        dzienniki sesji
```

Więcej o mechanizmie manifestów, pomiarze przepustowości i zabezpieczeniach
operacji na plikach: **[docs/JAK-TO-DZIALA.md](docs/JAK-TO-DZIALA.md)**.

---

## Metoda alternatywna — konsola Steam

Bez narzędzi zewnętrznych. Wolniejsze, bez podglądu postępu i z ręczną podmianą katalogu:

```
steam://open/console
```

```
download_depot 1961460 1961461 1265526790874008598
```

Pliki trafiają do `steamapps\content\app_1961460\depot_1961461`.

---

## Uwagi

- Rozgrywka sieciowa wymaga tej samej kompilacji u wszystkich uczestników.
- Klient Steam musi działać w tle, aby gra rozpoznała konto.
- Program nie modyfikuje plików gry ani nie omija zabezpieczeń — pobiera wyłącznie
  zawartość udostępnianą przez Steam dla posiadanego konta.

## Licencja

[MIT](LICENSE)

<div align="center">
<sub>Projekt niezależny, niepowiązany z Mob Entertainment ani Valve.<br>
Logo jest oryginalną grafiką wektorową stworzoną na potrzeby tego repozytorium.</sub>
</div>
