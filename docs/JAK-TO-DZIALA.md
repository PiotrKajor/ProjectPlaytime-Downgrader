# Jak to działa

## Skąd biorą się starsze wersje

Steam przechowuje każdą kompilację gry jako osobny **manifest depotu** —
listę plików wraz z sumami kontrolnymi i identyfikatorami fragmentów danych.
Manifesty nie są usuwane po wydaniu łatki. Klient Steam pobiera zawsze manifest
bieżącej kompilacji, ale protokół pozwala zażądać dowolnego innego.

Z tej możliwości korzysta [DepotDownloader](https://github.com/SteamRE/DepotDownloader) —
narzędzie projektu SteamRE oparte na bibliotece SteamKit2. Loguje się na konto
użytkownika, pobiera klucz depotu i ściąga wskazany manifest.

Dla PROJECT: PLAYTIME:

| Parametr | Wartość |
|---|---|
| App ID | `1961460` |
| Depot ID | `1961461` |
| Rozmiar | około 12 GB |

## Dlaczego przycisk „Graj" zwykle psuje downgrade

Po podmianie plików katalog gry zawiera starą zawartość, ale plik
`steamapps\appmanifest_1961460.acf` nadal opisuje instalację. Klient Steam
przy każdym uruchomieniu porównuje zapisany w nim `buildid` z identyfikatorem
bieżącej kompilacji gałęzi publicznej, pobranym z serwera. Różnica oznacza
zaplanowanie aktualizacji — i naciśnięcie **Graj** przywraca wersję aktualną.

Typowe porady z internetu obchodzą problem:

| Porada | Dlaczego zawodzi |
|---|---|
| `AutoUpdateBehavior` na `1` | Blokuje aktualizacje w tle, ale nie przy uruchomieniu — a to właśnie robi przycisk Graj |
| Plik appmanifest tylko do odczytu | Steam potrafi wymusić zapis albo utknąć w pętli „aktualizacja w kolejce" |
| Uruchamianie gry z pliku `.exe` | Działa, ale przycisk Graj pozostaje pułapką |

## Rozwiązanie zastosowane w tym programie

Skoro Steam ocenia stan instalacji **wyłącznie na podstawie metadanych**,
a zawartość katalogu sprawdza dopiero po ręcznym uruchomieniu opcji
_Sprawdź spójność plików gry_, wystarczy zapisać w appmanifest stan
odpowiadający wersji aktualnej:

```
"StateFlags"          "4"          instalacja kompletna
"buildid"             "12576441"   bieżąca kompilacja publiczna
"TargetBuildID"       "0"          brak kompilacji docelowej
"AutoUpdateBehavior"  "1"          brak aktualizacji w tle
"ScheduledAutoUpdate" "0"          brak zaplanowanego zadania
```

Steam widzi grę kompletną i aktualną, więc przycisk **Graj** od razu uruchamia
plik wykonywalny — którym są pliki starszej kompilacji.

Wartość `buildid` nie jest wpisana na stałe. Program odpytuje publiczne API
`api.steamcmd.net/v1/info/1961460` o identyfikator kompilacji gałęzi `public`
i zapisuje wartość odczytaną w danej chwili. Przy braku łączności używana jest
wartość zapasowa `12576441`.

### Trwałość rozwiązania

Ostatnia publiczna aktualizacja gry: **30 października 2023**, build `12576441`.
Dopóki wydawca nie opublikuje nowej kompilacji, identyfikator się nie zmienia
i konfiguracja pozostaje ważna bez ograniczeń czasowych. Po ewentualnej łatce
wystarczy pozycja menu _Napraw przycisk „Graj"_.

### Czego to nie przetrwa

Opcja _Sprawdź spójność plików gry_ liczy sumy kontrolne wszystkich plików
na dysku i porównuje je z manifestem bieżącej kompilacji. Wykrywa różnicę
i pobiera wersję aktualną. To jedyna operacja cofająca cały zabieg — dlatego
program tworzy kopię zapasową i pozwala wrócić do stanu wyjściowego.

## Dlaczego logowanie odbywa się w dwóch krokach

DepotDownloader czyta hasło i kod Steam Guard przez `Console.ReadKey`, czyli
bezpośrednio ze sterownika konsoli. Przy przekierowanym strumieniu wejściowym
wywołanie to kończy się wyjątkiem, więc nie da się jednocześnie obsłużyć
logowania i przechwytywać wyjścia w celu narysowania paska postępu.

Program rozdziela zatem oba etapy:

1. **Logowanie** — DepotDownloader działa w zwykłej konsoli i ma pełny dostęp
   do klawiatury. Parametr `-filelist` wskazuje listę z wzorcem, który nie
   pasuje do żadnego pliku, więc narzędzie tylko się uwierzytelnia, potwierdza
   dostęp do depotu i zapisuje token sesji (`-remember-password`). Nie pobiera
   przy tym żadnych danych.
2. **Pobieranie** — dzięki zapisanemu tokenowi żadne pytania się nie pojawiają.
   Proces uruchamiany jest z przekierowanym wyjściem, a jego wiersze trafiają
   do kolejki `ConcurrentQueue` obsługiwanej przez `Register-ObjectEvent`.
   Pętla renderująca odczytuje kolejkę i odświeża ekran około ośmiu razy na sekundę.

Tryb kodu QR nie zapisuje tokenu pod znaną nazwą konta, dlatego korzysta
z pojedynczego przebiegu w trybie tekstowym.

## Pomiar prędkości

DepotDownloader raportuje wyłącznie procent ukończenia i nazwę bieżącego pliku:

```
 43,72% Poppy/Content/Paks/pakchunk3-WindowsNoEditor.pak
```

Przepustowość nie jest podawana, więc program mierzy ją samodzielnie —
co dwie sekundy sumuje rozmiary plików w katalogu docelowym i dzieli przyrost
przez czas. Surowy pomiar mocno skacze, dlatego wynik jest wygładzany
wykładniczo (`0,6 × poprzedni + 0,4 × bieżący`). Rozmiar całkowity szacowany
jest z proporcji: `pobrane_bajty × 100 / procent`, a czas pozostały —
z tempa dotychczasowego postępu.

## Bezpieczeństwo operacji na plikach

- Biblioteki Steam na odłączonych dyskach są pomijane. Wykorzystanie
  `System.IO.Path.Combine` i `System.IO.File.Exists` zamiast `Join-Path`
  i `Test-Path` zapobiega wyjątkowi `DriveNotFound`, który przerywał
  wykrywanie na pierwszej niedostępnej pozycji z `libraryfolders.vdf`.
- Katalog pobierania tworzony jest w tej samej bibliotece co gra, dzięki czemu
  podmiana to przeniesienie w obrębie wolumenu — operacja natychmiastowa,
  bez kopiowania 12 GB.
- Przed podmianą klient Steam jest zamykany poleceniem `steam.exe -shutdown`,
  które pozwala mu zapisać konfigurację. Program czeka na faktyczne zakończenie
  procesu i przerywa działanie, jeśli ten nadal żyje.
- Nieudane przeniesienie pobranych plików powoduje automatyczne przywrócenie
  kopii zapasowej.
- Nazwa katalogu gry nie jest zgadywana. Odczytywana jest z wpisu `installdir`
  w appmanifest, ponieważ nie odpowiada tytułowi gry — w praktyce jest to
  `Poppy Playtime - Multiplayer`.
