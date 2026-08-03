# =============================================================================
#  Tui.ps1 - warstwa prezentacji: ramki, menu, paski postępu, animacje
# =============================================================================

$script:Esc     = [char]0x1B
$script:UseAnsi = $false

# --- Paleta ----------------------------------------------------------------

$script:Barwy = @{
    Reset   = '0'
    Pogrub  = '1'
    Przygas = '2'
    Szary   = '90'
    Czerwony= '91'
    Zielony = '92'
    Zolty   = '93'
    Niebieski='94'
    Rozowy  = '95'
    Blekit  = '96'
    Bialy   = '97'
}

function Get-Kod {
    param([string]$Nazwa)
    if (-not $script:UseAnsi) { return '' }
    $kod = $script:Barwy[$Nazwa]
    if (-not $kod) { $kod = '0' }
    return "$script:Esc[${kod}m"
}

function Format-Barwa {
    param([string]$Tekst, [string]$Barwa = 'Bialy')
    if (-not $script:UseAnsi) { return $Tekst }
    return (Get-Kod $Barwa) + $Tekst + (Get-Kod 'Reset')
}

function Get-DlugoscWidoczna {
    param([string]$Tekst)
    if (-not $Tekst) { return 0 }
    return ($Tekst -replace "$script:Esc\[[0-9;]*m", '').Length
}

# --- Inicjalizacja konsoli -------------------------------------------------

$script:VtSource = @'
using System;
using System.Runtime.InteropServices;
public static class VtConsole {
    [DllImport("kernel32.dll", SetLastError = true)]
    static extern IntPtr GetStdHandle(int nStdHandle);
    [DllImport("kernel32.dll", SetLastError = true)]
    static extern bool GetConsoleMode(IntPtr hConsoleHandle, out uint lpMode);
    [DllImport("kernel32.dll", SetLastError = true)]
    static extern bool SetConsoleMode(IntPtr hConsoleHandle, uint dwMode);
    public static bool Enable() {
        IntPtr handle = GetStdHandle(-11);
        uint mode;
        if (!GetConsoleMode(handle, out mode)) { return false; }
        return SetConsoleMode(handle, mode | 0x0004);
    }
}
'@

function Initialize-Tui {
    param([int]$MinSzerokosc = 84, [int]$MinWysokosc = 30)

    try { [Console]::OutputEncoding = [System.Text.Encoding]::UTF8 } catch { }

    # Wirtualny terminal (sekwencje ANSI). W Windows Terminal działa od razu,
    # w klasycznej konsoli wymaga jawnego włączenia trybu.
    try {
        if (-not ('VtConsole' -as [type])) {
            Add-Type -TypeDefinition $script:VtSource -ErrorAction Stop
        }
        $script:UseAnsi = [VtConsole]::Enable()
    } catch {
        $script:UseAnsi = $false
    }

    try {
        $okno = $Host.UI.RawUI.WindowSize
        $bufor = $Host.UI.RawUI.BufferSize
        if ($okno.Width -lt $MinSzerokosc -or $okno.Height -lt $MinWysokosc) {
            $maks = $Host.UI.RawUI.MaxPhysicalWindowSize
            $w = [Math]::Min([Math]::Max($okno.Width,  $MinSzerokosc), $maks.Width)
            $h = [Math]::Min([Math]::Max($okno.Height, $MinWysokosc),  $maks.Height)
            if ($bufor.Width -lt $w) {
                $bufor.Width = $w
                $Host.UI.RawUI.BufferSize = $bufor
            }
            $okno.Width = $w; $okno.Height = $h
            $Host.UI.RawUI.WindowSize = $okno
        }
    } catch { }

    Set-KursorWidoczny $false
    $script:SzerokoscEkranu = Get-SzerokoscEkranu
}

function Restore-Console {
    Set-KursorWidoczny $true
    if ($script:UseAnsi) { try { [Console]::Write((Get-Kod 'Reset')) } catch { } }
}

function Set-KursorWidoczny {
    param([bool]$Widoczny)
    try { [Console]::CursorVisible = $Widoczny } catch { }
}

# --- Bezpieczny odczyt wymiarów --------------------------------------------
#
# Bez rzeczywistej konsoli (wyjście przekierowane, uruchomienie z potoku, zadanie
# w tle) właściwości WindowWidth i WindowHeight albo rzucają wyjątkiem, albo
# zwracają wartość pustą, która w arytmetyce staje się zerem. Zero szerokości
# rozlewa się dalej na ujemne powtórzenia znaków, a te już rzucają wyjątkiem.
# Dlatego każdy odczyt przechodzi przez funkcję z wartością zastępczą i zakresem.

function Get-WymiarKonsoli {
    param([string]$Nazwa, [int]$Domyslny, [int]$Min, [int]$Max)
    $v = 0
    try {
        $surowy = [Console]::$Nazwa
        if ($null -ne $surowy) { $v = [int]$surowy }
    } catch { $v = 0 }
    if ($v -le 0) { $v = $Domyslny }
    if ($v -lt $Min) { $v = $Min }
    if ($v -gt $Max) { $v = $Max }
    return $v
}

function Get-SzerokoscEkranu { return (Get-WymiarKonsoli -Nazwa 'WindowWidth'  -Domyslny 84 -Min 60 -Max 100) }
function Get-WysokoscEkranu  { return (Get-WymiarKonsoli -Nazwa 'WindowHeight' -Domyslny 30 -Min 24 -Max 200) }

function Get-Powtorzenie {
    <# Powtórzenie znaku nigdy nie może dostać ujemnej liczby - to wyjątek. #>
    param([string]$Znak, [int]$Ile)
    if ($Ile -le 0) { return '' }
    if ($Ile -gt 500) { $Ile = 500 }
    return $Znak * $Ile
}

function Format-Pole {
    <# Wyrównanie do szerokości pola; ujemna szerokość w operatorze -f to wyjątek. #>
    param([string]$Tekst, [int]$Szerokosc)
    if ($null -eq $Tekst) { $Tekst = '' }
    if ($Szerokosc -le 0) { return '' }
    if ($Tekst.Length -ge $Szerokosc) { return $Tekst.Substring(0, $Szerokosc) }
    return $Tekst + (Get-Powtorzenie ' ' ($Szerokosc - $Tekst.Length))
}

function Split-NaWiersze {
    <#
        Dzieli tekst na wiersze mieszczące się w zadanej szerokości, łamiąc na
        granicy słów. Pozwala układowi dopasować się do okna zamiast obcinać treść.
        Słowo dłuższe niż wiersz - na przykład długa ścieżka - dzielone jest twardo.
    #>
    param([string]$Tekst, [int]$Szerokosc)

    if ($null -eq $Tekst -or $Tekst -eq '') { return , @('') }
    if ($Szerokosc -lt 8) { $Szerokosc = 8 }

    $wynik = New-Object System.Collections.Generic.List[string]

    foreach ($akapit in ($Tekst -split "`r?`n")) {
        $biezacy = ''
        foreach ($slowo in ($akapit -split ' ')) {
            if ($slowo.Length -gt $Szerokosc) {
                if ($biezacy) { $wynik.Add($biezacy); $biezacy = '' }
                $reszta = $slowo
                while ($reszta.Length -gt $Szerokosc) {
                    $wynik.Add($reszta.Substring(0, $Szerokosc))
                    $reszta = $reszta.Substring($Szerokosc)
                }
                $biezacy = $reszta
                continue
            }
            if (-not $biezacy) {
                $biezacy = $slowo
            } elseif (($biezacy.Length + 1 + $slowo.Length) -le $Szerokosc) {
                $biezacy += ' ' + $slowo
            } else {
                $wynik.Add($biezacy)
                $biezacy = $slowo
            }
        }
        $wynik.Add($biezacy)
    }

    return , $wynik.ToArray()
}

function Read-Klawisz {
    <#
        Bezpieczny odczyt klawisza. Bez konsoli ReadKey rzuca wyjątkiem, co bez
        osłony kończyło program. Zwraca $null, gdy odczyt jest niemożliwy -
        wywołujący musi to potraktować jako rezygnację, a nie zapętlić się.
    #>
    try { return [Console]::ReadKey($true) } catch { return $null }
}

# --- Prymitywy rysowania ---------------------------------------------------

function Clear-Ekran {
    try { [Console]::Clear() } catch { try { Clear-Host } catch { } }
}

function Write-Wiersz {
    param([int]$X, [int]$Y, [string]$Tekst)
    if ($null -eq $Tekst) { return }
    try {
        if ($Y -lt 0 -or $Y -ge (Get-WysokoscEkranu)) { return }
        if ($X -lt 0) { $X = 0 }
        [Console]::SetCursorPosition($X, $Y)
        [Console]::Write($Tekst)
    } catch { }
}

function Clear-Wiersz {
    param([int]$Y, [int]$Szerokosc = 0)
    if ($Szerokosc -le 0) { $Szerokosc = (Get-SzerokoscEkranu) }
    Write-Wiersz 0 $Y (Get-Powtorzenie ' ' $Szerokosc)
}

function Write-Wysrodkowany {
    param([int]$Y, [string]$Tekst, [string]$Barwa = 'Bialy')
    $szer = Get-SzerokoscEkranu
    $x = [Math]::Max(0, [int](($szer - (Get-DlugoscWidoczna $Tekst)) / 2))
    Write-Wiersz $x $Y (Format-Barwa $Tekst $Barwa)
}

function Draw-Ramka {
    param(
        [int]$X, [int]$Y, [int]$Szerokosc, [int]$Wysokosc,
        [string]$Tytul = '',
        [string]$Barwa = 'Blekit'
    )
    # Ramka węższa niż cztery znaki albo niższa niż dwa wiersze nie ma sensu,
    # a przy ujemnych wymiarach powtórzenie znaku rzuciłoby wyjątkiem.
    if ($Szerokosc -lt 4 -or $Wysokosc -lt 2) { return }

    $gora = '┌' + (Get-Powtorzenie '─' ($Szerokosc - 2)) + '┐'
    if ($Tytul) {
        $etykieta = " $Tytul "
        if ($etykieta.Length -lt $Szerokosc - 4) {
            $gora = '┌─' + $etykieta + (Get-Powtorzenie '─' ($Szerokosc - 3 - $etykieta.Length)) + '┐'
        }
    }
    Write-Wiersz $X $Y (Format-Barwa $gora $Barwa)
    for ($i = 1; $i -lt $Wysokosc - 1; $i++) {
        Write-Wiersz $X ($Y + $i) (Format-Barwa '│' $Barwa)
        Write-Wiersz ($X + $Szerokosc - 1) ($Y + $i) (Format-Barwa '│' $Barwa)
    }
    Write-Wiersz $X ($Y + $Wysokosc - 1) (Format-Barwa ('└' + (Get-Powtorzenie '─' ($Szerokosc - 2)) + '┘') $Barwa)
}

function Draw-Naglowek {
    param([string]$Podtytul = '', [string]$Wersja = '')

    $szer = Get-SzerokoscEkranu
    $tytul = 'PROJECT: PLAYTIME  ·  DOWNGRADER'

    Write-Wiersz 0 0 (Format-Barwa (Get-Powtorzenie '═' $szer) 'Czerwony')

    $lewy  = "  $tytul"
    $prawy = if ($Wersja) { "$Wersja  " } else { '' }
    $wypelniacz = Get-Powtorzenie ' ' ([Math]::Max(1, $szer - $lewy.Length - $prawy.Length))
    Write-Wiersz 0 1 ((Format-Barwa $lewy 'Pogrub') + (Format-Barwa '' 'Reset') + $wypelniacz + (Format-Barwa $prawy 'Szary'))

    Write-Wiersz 0 2 (Format-Barwa (Get-Powtorzenie '═' $szer) 'Czerwony')

    if ($Podtytul) {
        Clear-Wiersz 3
        Write-Wiersz 2 3 (Format-Barwa $Podtytul 'Blekit')
    }
}

function Draw-Pasek {
    param(
        [int]$X, [int]$Y, [int]$Szerokosc,
        [double]$Procent,
        [string]$Barwa = 'Zielony'
    )
    # Pasek węższy niż trzy znaki nie zmieściłby nawet nawiasów, a ujemne wnętrze
    # rozsypałoby powtórzenia znaków.
    if ($Szerokosc -lt 3) { return }

    # Wartość spoza zakresu albo nieliczbowa (skutek dzielenia przez zero
    # w obliczeniach postępu) zostaje sprowadzona do bezpiecznego przedziału.
    if ([double]::IsNaN($Procent) -or [double]::IsInfinity($Procent)) { $Procent = 0 }
    if ($Procent -lt 0)   { $Procent = 0 }
    if ($Procent -gt 100) { $Procent = 100 }

    $wnetrze = $Szerokosc - 2
    $pelne   = [int][Math]::Floor($wnetrze * $Procent / 100)
    if ($pelne -lt 0) { $pelne = 0 }
    if ($pelne -gt $wnetrze) { $pelne = $wnetrze }
    $reszta = ($wnetrze * $Procent / 100) - $pelne

    $czastki = @(' ', '▏', '▎', '▍', '▌', '▋', '▊', '▉')
    $ostatni = ''
    if ($pelne -lt $wnetrze) {
        $indeks = [int][Math]::Floor($reszta * 8)
        if ($indeks -lt 0) { $indeks = 0 }
        if ($indeks -gt 7) { $indeks = 7 }
        $ostatni = $czastki[$indeks]
    }

    $puste = $wnetrze - $pelne - $(if ($ostatni -and $ostatni -ne ' ') { 1 } else { 0 })
    if ($puste -lt 0) { $puste = 0 }

    $tresc = (Format-Barwa (Get-Powtorzenie '█' $pelne) $Barwa) +
             (Format-Barwa $ostatni $Barwa) +
             (Format-Barwa (Get-Powtorzenie '░' $puste) 'Szary')

    Write-Wiersz $X $Y ((Format-Barwa '[' 'Szary') + $tresc + (Format-Barwa ']' 'Szary'))
}

$script:KlatkiSpinnera = @('⠋','⠙','⠹','⠸','⠼','⠴','⠦','⠧','⠇','⠏')

function Get-Spinner {
    param([int]$Krok)
    return $script:KlatkiSpinnera[$Krok % $script:KlatkiSpinnera.Count]
}

function Format-Skrot {
    param([string]$Tekst, [int]$Maks)
    if (-not $Tekst) { return '' }
    if ($Tekst.Length -le $Maks) { return $Tekst }
    if ($Maks -le 3) { return $Tekst.Substring(0, $Maks) }
    return '…' + $Tekst.Substring($Tekst.Length - $Maks + 1)
}

# --- Elementy interaktywne -------------------------------------------------

function Clear-BuforKlawiatury {
    <#
        Klawisze naciśnięte w trakcie długiej operacji zostają w kolejce wejściowej.
        Pierwszy ReadKey skonsumowałby je natychmiast, przez co ekran podsumowania
        zniknąłby, zanim ktokolwiek zdążyłby go przeczytać.
    #>
    try { while ([Console]::KeyAvailable) { [void][Console]::ReadKey($true) } } catch { }
}

function Wait-Klawisz {
    param([string]$Tekst = 'Naciśnij dowolny klawisz, aby kontynuować…', [int]$Y = -1)

    if ($Y -ge 0) { Write-Wiersz 2 $Y (Format-Barwa $Tekst 'Przygas') }
    Clear-BuforKlawiatury
    try { [void][Console]::ReadKey($true) } catch { Start-Sleep -Seconds 2 }
}

function Set-TytulOkna {
    <# Tytuł okna jest widoczny na pasku zadań także wtedy, gdy okno jest zminimalizowane. #>
    param([string]$Tekst)
    try { $Host.UI.RawUI.WindowTitle = $Tekst } catch { }
}

function Invoke-Sygnal {
    <# Krótki sygnał dźwiękowy - pobieranie trwa na tyle długo, że użytkownik
       zdąży odejść od komputera. #>
    param([switch]$Blad)
    try {
        if ($Blad) { [Console]::Beep(392, 200); [Console]::Beep(262, 350) }
        else       { [Console]::Beep(659, 120); [Console]::Beep(880, 200) }
    } catch { }
}

function Test-Escape {
    <#
        Bezpieczne sprawdzenie, czy naciśnięto Esc. Console.KeyAvailable rzuca
        wyjątkiem, gdy wejście konsoli jest przekierowane (uruchomienie z potoku,
        zadanie w tle, przechwycone stdin), dlatego całość jest osłonięta.
    #>
    try {
        if ([Console]::KeyAvailable) {
            return ([Console]::ReadKey($true).Key -eq 'Escape')
        }
    } catch { }
    return $false
}

function Show-Menu {
    <#
        Pozycje: tablica obiektów z polami Etykieta oraz (opcjonalnie) Opis.
        Zwraca indeks wybranej pozycji albo -1 przy naciśnięciu Esc.
    #>
    param(
        # AllowEmptyCollection: pusta lista jest obsługiwana w ciele funkcji, a bez
        # tego atrybutu walidacja parametru zgłosiłaby błąd, zanim tam dotrzemy
        [Parameter(Mandatory)] [AllowEmptyCollection()] [array]$Pozycje,
        [string]$Tytul = '',
        [string]$Podtytul = '',
        [string]$Wersja = '',
        [int]$Zaznaczona = 0,
        [switch]$BezEscape
    )

    # Menu bez pozycji zapętliłoby się na dzieleniu modulo przez zero.
    if (-not $Pozycje -or $Pozycje.Count -eq 0) { return -1 }
    if ($Zaznaczona -lt 0 -or $Zaznaczona -ge $Pozycje.Count) { $Zaznaczona = 0 }

    $szer = Get-SzerokoscEkranu
    Clear-Ekran
    Draw-Naglowek -Podtytul $Podtytul -Wersja $Wersja

    $yStart = 5
    if ($Tytul) {
        Write-Wiersz 2 $yStart (Format-Barwa $Tytul 'Pogrub')
        $yStart += 2
    }

    $wysWiersza = 2
    while ($true) {
        for ($i = 0; $i -lt $Pozycje.Count; $i++) {
            $y = $yStart + ($i * $wysWiersza)
            $poz = $Pozycje[$i]
            $aktywna = ($i -eq $Zaznaczona)

            Clear-Wiersz $y $szer
            Clear-Wiersz ($y + 1) $szer

            if ($aktywna) {
                $wskaznik = Format-Barwa ' ▶ ' 'Czerwony'
                $etykieta = Format-Barwa $poz.Etykieta 'Bialy'
            } else {
                $wskaznik = '   '
                $etykieta = Format-Barwa $poz.Etykieta 'Szary'
            }
            Write-Wiersz 2 $y ($wskaznik + $etykieta)

            if ($poz.PSObject.Properties['Opis'] -and $poz.Opis) {
                $barwaOpisu = if ($aktywna) { 'Blekit' } else { 'Przygas' }
                Write-Wiersz 7 ($y + 1) (Format-Barwa (Format-Skrot $poz.Opis ($szer - 9)) $barwaOpisu)
            }
        }

        $yStopka = $yStart + ($Pozycje.Count * $wysWiersza) + 1
        Clear-Wiersz $yStopka $szer
        $podpowiedz = '↑ ↓ wybór    Enter zatwierdź'
        if (-not $BezEscape) { $podpowiedz += '    Esc powrót' }
        Write-Wiersz 2 $yStopka (Format-Barwa $podpowiedz 'Przygas')

        # Brak możliwości odczytu klawisza oznacza brak konsoli interaktywnej.
        # Zapętlanie się w takiej sytuacji zawiesiłoby program na zawsze,
        # dlatego menu zwraca rezygnację.
        $klawisz = Read-Klawisz
        if ($null -eq $klawisz) { return -1 }

        switch ($klawisz.Key) {
            'UpArrow'   { $Zaznaczona = ($Zaznaczona - 1 + $Pozycje.Count) % $Pozycje.Count }
            'DownArrow' { $Zaznaczona = ($Zaznaczona + 1) % $Pozycje.Count }
            'Home'      { $Zaznaczona = 0 }
            'End'       { $Zaznaczona = $Pozycje.Count - 1 }
            'Enter'     { return $Zaznaczona }
            'Escape'    { if (-not $BezEscape) { return -1 } }
            default {
                $znak = $klawisz.KeyChar.ToString()
                if ($znak -match '^[1-9]$') {
                    $idx = [int]$znak - 1
                    if ($idx -lt $Pozycje.Count) { return $idx }
                }
            }
        }
    }
}

function Show-Komunikat {
    param(
        [string[]]$Wiersze,
        [string]$Tytul = 'Informacja',
        [string]$Barwa = 'Blekit',
        [switch]$BezOczekiwania
    )
    if ($null -eq $Wiersze) { $Wiersze = @() }

    $szer = Get-SzerokoscEkranu
    $wysEkranu = Get-WysokoscEkranu
    $szerRamki = $szer - 4

    # Komunikat dłuższy niż ekran zostaje przycięty - inaczej ramka wyszłaby
    # poza bufor, a kolejne wiersze nadpisałyby ekran w przypadkowych miejscach.
    $maksWierszy = [Math]::Max(1, $wysEkranu - 10)
    if ($Wiersze.Count -gt $maksWierszy) {
        $Wiersze = @($Wiersze | Select-Object -First ($maksWierszy - 1)) + '…'
    }
    $wys = $Wiersze.Count + 4

    $y = [Math]::Max(5, [int](($wysEkranu - $wys) / 2))
    Draw-Ramka -X 2 -Y $y -Szerokosc $szerRamki -Wysokosc $wys -Tytul $Tytul -Barwa $Barwa

    for ($i = 0; $i -lt $Wiersze.Count; $i++) {
        Write-Wiersz 4 ($y + 2 + $i) (Format-Skrot $Wiersze[$i] ($szerRamki - 4))
    }

    if (-not $BezOczekiwania) {
        Write-Wiersz 4 ($y + $wys) (Format-Barwa 'Naciśnij dowolny klawisz, aby kontynuować…' 'Przygas')
        Clear-BuforKlawiatury
        [void](Read-Klawisz)
    }
}

function Confirm-Tui {
    param([string]$Pytanie, [string]$Opis = '', [switch]$DomyslnieNie)

    $pozycje = @(
        [pscustomobject]@{ Etykieta = 'Tak'; Opis = '' },
        [pscustomobject]@{ Etykieta = 'Nie'; Opis = '' }
    )
    $start = 0
    if ($DomyslnieNie) { $start = 1 }

    $wynik = Show-Menu -Pozycje $pozycje -Tytul $Pytanie -Podtytul $Opis -Zaznaczona $start -BezEscape
    return ($wynik -eq 0)
}

function Read-Pole {
    param([string]$Etykieta, [switch]$Ukryte)

    $szer = Get-SzerokoscEkranu
    $y = [Math]::Max(5, (Get-WysokoscEkranu) - 4)
    Clear-Wiersz $y $szer
    Clear-Wiersz ($y + 1) $szer
    Write-Wiersz 2 $y (Format-Barwa $Etykieta 'Blekit')
    Write-Wiersz 2 ($y + 1) (Format-Barwa '› ' 'Czerwony')

    try { [Console]::SetCursorPosition(4, $y + 1) } catch { }
    Set-KursorWidoczny $true

    # Read-Host bez konsoli natychmiast napotyka koniec strumienia i rzuca wyjątkiem;
    # pusta odpowiedź jest wtedy jedyną sensowną wartością.
    $wartosc = ''
    try {
        if ($Ukryte) {
            $bezpieczne = Read-Host -AsSecureString
            $wskaznik = [Runtime.InteropServices.Marshal]::SecureStringToBSTR($bezpieczne)
            try {
                $wartosc = [Runtime.InteropServices.Marshal]::PtrToStringAuto($wskaznik)
            } finally {
                # zwolnienie pamięci niezarządzanej z hasłem
                [Runtime.InteropServices.Marshal]::ZeroFreeBSTR($wskaznik)
            }
        } else {
            $wartosc = Read-Host
        }
    } catch {
        $wartosc = ''
    }

    Set-KursorWidoczny $false
    if ($null -eq $wartosc) { return '' }
    return $wartosc
}

# --- Lista kroków z animowanym statusem ------------------------------------

function New-ListaKrokow {
    param([string[]]$Etykiety)
    $lista = @()
    foreach ($e in $Etykiety) {
        $lista += [pscustomobject]@{ Etykieta = $e; Stan = 'oczekuje'; Detal = '' }
    }
    return ,$lista
}

function Draw-Kroki {
    param([array]$Kroki, [int]$Y, [int]$Klatka = 0)

    $szer = Get-SzerokoscEkranu
    for ($i = 0; $i -lt $Kroki.Count; $i++) {
        $k = $Kroki[$i]
        switch ($k.Stan) {
            'gotowe'  { $ikona = Format-Barwa '  ✔ ' 'Zielony' }
            'trwa'    { $ikona = Format-Barwa "  $(Get-Spinner $Klatka) " 'Zolty' }
            'blad'    { $ikona = Format-Barwa '  ✖ ' 'Czerwony' }
            'pominiete'{ $ikona = Format-Barwa '  – ' 'Szary' }
            default   { $ikona = Format-Barwa '  · ' 'Przygas' }
        }
        switch ($k.Stan) {
            'gotowe'  { $barwa = 'Bialy' }
            'trwa'    { $barwa = 'Bialy' }
            'blad'    { $barwa = 'Czerwony' }
            default   { $barwa = 'Przygas' }
        }

        $tekst = $k.Etykieta
        if ($k.Detal) { $tekst += "  ($($k.Detal))" }

        Clear-Wiersz ($Y + $i) $szer
        Write-Wiersz 0 ($Y + $i) ($ikona + (Format-Barwa (Format-Skrot $tekst ($szer - 8)) $barwa))
    }
}
