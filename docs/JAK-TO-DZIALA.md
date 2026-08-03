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

## Po co w ogóle wersja bazowa

Sam pobrany depot to komplet plików gry — do uruchomienia niczego więcej nie brakuje.
Klient Steam wymaga jednak, aby gra miała **wpis `appmanifest_1961460.acf`**
w katalogu `steamapps`. Bez niego pozycja nie pojawi się w bibliotece, przycisk
„Graj” nie istnieje, a katalog w `steamapps\common` jest dla Steam niewidoczny.

Wpis powstaje wyłącznie po stronie klienta, w chwili **zakolejkowania pobierania** —
nie po jego zakończeniu. Steam zapisuje wtedy `appid`, `installdir`, `StateFlags`
oraz pola postępu i dopiero zaczyna ściągać dane. To pozwala rozdzielić dwie rzeczy,
które zwykle idą w parze:

| Potrzebne | Kosztuje |
|:--|:--|
| wpis `appmanifest` | zero bajtów transferu |
| pliki wersji bieżącej | około 12 GB |

Skoro pliki wersji bieżącej i tak zostaną zastąpione starszą kompilacją, ich
pobieranie jest czystą stratą. Program otwiera więc `steam://install/1961460`,
czeka aż wpis się pojawi, zamyka klienta (co przerywa transfer), usuwa zawartość
`steamapps\downloading\1961460` i przechodzi do pobierania właściwej kompilacji.
Łącznie na dysk trafia około 12 GB zamiast 24 GB.

Wariant pełny pozostaje dostępny dla osób, które wolą, aby wszystko przebiegło
konwencjonalnie. Jego postęp odczytywany jest z pól `BytesDownloaded`
i `BytesToDownload` w appmanifest, aktualizowanych przez klienta na bieżąco.

### StateFlags jako pole bitowe

O kompletności instalacji decyduje bit o wartości `4` (`StateFullyInstalled`).
Wpis utworzony przez zakolejkowanie pobierania ma typowo `1026`, czyli
„wymagana aktualizacja”, i bitu tego nie zawiera. Sprawdzenie musi więc być
maskowaniem (`$flagi -band 4`), a nie porównaniem do liczby — `6` również oznacza
instalację kompletną.

Rozróżnienie ma praktyczne znaczenie: przed podmianą program tworzy kopię
zapasową katalogu gry, ale robi to **wyłącznie dla kompletnej instalacji**.
Archiwizowanie kilkunastu gigabajtów szczątków po przerwanym pobieraniu nie
miałoby wartości, więc taki katalog jest usuwany, a zwolnione miejsce raportowane.

Osobny przypadek: po odinstalowaniu gry Steam usuwa wpis, lecz potrafi zostawić
katalog z plikami. Taki osierocony katalog jest wykrywany, jego rozmiar
raportowany, a zawartość zastępowana.

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

## Dlaczego potrzebne jest osobne logowanie

Pytanie pojawia się naturalnie: klient Steam działa i jest zalogowany, więc czemu
program prosi o dane po raz drugi.

DepotDownloader nie jest wtyczką ani nakładką na klienta. To **niezależna
implementacja protokołu Steam** oparta na bibliotece SteamKit2, nawiązująca własne
połączenie z serwerami CM Valve. Sesja klienta Steam jest zaszyfrowana i związana
z jego procesem — nie ma udokumentowanego mechanizmu jej współdzielenia. Aby
odszyfrować zawartość depotu, narzędzie musi samo uzyskać klucz depotu, a serwer
wyda go wyłącznie sesji uwierzytelnionej na koncie z licencją na daną grę.

Okno instalacji otwierane wcześniej przez program to zupełnie inna operacja:
klient Steam pobiera wtedy wersję bieżącą, aby powstał wpis `appmanifest`.
Dwa pobierania, dwa różne programy, dwie niezależne sesje.

### Jednorazowość

Parametr `-remember-password` zapisuje token sesji w pliku `account.config`
w katalogu roboczym narzędzia. Program zapamiętuje dodatkowo nazwę konta, więc
przy kolejnym uruchomieniu w menu pojawia się pozycja _Kontynuuj jako …_,
a etap logowania przebiega bez żadnego pytania.

### Kolizja identyfikatorów sesji

Steam przypisuje każdej sesji `LoginID` i **zrywa połączenie, gdy dwie sesje tego
samego konta zgłoszą identyczną wartość**. Domyślnie DepotDownloader użyłby
wartości kolidującej z działającym klientem, co wyrzuciłoby użytkownika ze Steam
w trakcie pobierania. Dlatego każde wywołanie narzędzia otrzymuje jawny
parametr `-loginid` o stałej, odrębnej wartości.

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

## Odporność na uszkodzenia

Program wykonuje operacje nieodwracalne na cudzej instalacji gry, więc każde
założenie o środowisku jest traktowane jako możliwe do złamania.

### Konsola może nie istnieć

Uruchomienie z potoku, jako zadanie w tle albo z przekierowanym wyjściem sprawia,
że `SetCursorPosition`, `ReadKey` i `Clear` rzucają wyjątkiem, a `WindowWidth`
zwraca wartość pustą. Ta ostatnia w arytmetyce staje się zerem i rozlewa się dalej
na ujemne szerokości, a powtórzenie znaku ujemną liczbę razy to kolejny wyjątek —
jedna niedostępna właściwość potrafiła w ten sposób wywrócić cały program.

Każdy odczyt wymiaru przechodzi więc przez funkcję z wartością zastępczą
i zakresem, powtórzenia znaków mają własną osłonę, a odczyt klawisza zwraca
wartość pustą zamiast rzucać. Menu traktuje ją jako rezygnację, dzięki czemu brak
klawiatury nie zamienia się w nieskończoną pętlę.

### Wpis appmanifest nie może zostać uszkodzony

Uszkodzony `appmanifest` oznacza dla użytkownika niedziałającą pozycję
w bibliotece Steam, więc zapis jest dwuetapowy: treść trafia najpierw do pliku
tymczasowego, po zapisie jest ponownie odczytywana i sprawdzana, i dopiero
zweryfikowana zastępuje oryginał. Awaria w połowie operacji zostawia nietknięty
plik wyjściowy.

Przed pierwszą modyfikacją powstaje kopia `appmanifest_1961460.acf.oryginal`.
Kontrola sensowności odrzuca treść bez bloku `AppState`, bez pola `appid` albo
z niezrównoważonymi nawiasami — plik ucięty w połowie nie zostanie nadpisany,
a plik zajęty przez klienta Steam kończy się odmową zapisu zamiast wyjątkiem.

### Podmiana katalogu jest transakcyjna

Bezpośrednio przed zastąpieniem katalogu gry sprawdzana jest obecność pliku
wykonywalnego oraz łączny rozmiar pobranych danych. Pobranie przerwane w połowie
zostawia poprawny plik `.exe`, ale bez zasobów, dlatego sam jego widok nie
wystarcza. Niepowodzenie kontroli przerywa operację, zanim cokolwiek zostanie
ruszone — katalog gry pozostaje nietknięty, a pobieranie da się wznowić.

Jeśli przeniesienie mimo to zawiedzie, kopia zapasowa wraca na swoje miejsce.

### Błąd nie kończy programu

Obsługa jest trójwarstwowa: akcja menu, pętla główna i wywołanie najwyższego
poziomu. Błąd pojedynczej operacji zostaje pokazany na ekranie i zapisany
w dzienniku wraz ze śladem stosu, po czym sterowanie wraca do menu. Gdyby zawiodło
samo rysowanie ekranu awarii, pozostaje wypisanie zwykłym tekstem — okno nie może
zniknąć bez śladu.

### Pobieranie narzędzia jest ponawiane

Pobranie DepotDownloadera ponawiane jest trzykrotnie z rosnącą przerwą, a rozmiar
gotowego pliku porównywany z zapowiedzianym przez wydanie. Niezgodność traktowana
jest jak błąd, więc niekompletne archiwum nie trafi do rozpakowania.

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
