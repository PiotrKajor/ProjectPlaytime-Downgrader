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

    try { [Console]::CursorVisible = $false } catch { }
    $script:SzerokoscEkranu = [Math]::Min([Console]::WindowWidth, 100)
}

function Restore-Console {
    try { [Console]::CursorVisible = $true } catch { }
    if ($script:UseAnsi) { [Console]::Write((Get-Kod 'Reset')) }
}

function Get-SzerokoscEkranu {
    $w = 84
    try { $w = [Math]::Min([Console]::WindowWidth, 100) } catch { }
    if ($w -lt 60) { $w = 60 }
    return $w
}

# --- Prymitywy rysowania ---------------------------------------------------

function Clear-Ekran {
    try { [Console]::Clear() } catch { Clear-Host }
}

function Write-Wiersz {
    param([int]$X, [int]$Y, [string]$Tekst)
    try {
        if ($Y -lt 0 -or $Y -ge [Console]::WindowHeight) { return }
        [Console]::SetCursorPosition([Math]::Max(0, $X), $Y)
        [Console]::Write($Tekst)
    } catch { }
}

function Clear-Wiersz {
    param([int]$Y, [int]$Szerokosc = 0)
    if ($Szerokosc -le 0) { $Szerokosc = (Get-SzerokoscEkranu) }
    Write-Wiersz 0 $Y (' ' * $Szerokosc)
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
    $gora = '┌' + ('─' * ($Szerokosc - 2)) + '┐'
    if ($Tytul) {
        $etykieta = " $Tytul "
        if ($etykieta.Length -lt $Szerokosc - 4) {
            $gora = '┌─' + $etykieta + ('─' * ($Szerokosc - 3 - $etykieta.Length)) + '┐'
        }
    }
    Write-Wiersz $X $Y (Format-Barwa $gora $Barwa)
    for ($i = 1; $i -lt $Wysokosc - 1; $i++) {
        Write-Wiersz $X ($Y + $i) (Format-Barwa '│' $Barwa)
        Write-Wiersz ($X + $Szerokosc - 1) ($Y + $i) (Format-Barwa '│' $Barwa)
    }
    Write-Wiersz $X ($Y + $Wysokosc - 1) (Format-Barwa ('└' + ('─' * ($Szerokosc - 2)) + '┘') $Barwa)
}

function Draw-Naglowek {
    param([string]$Podtytul = '', [string]$Wersja = '')

    $szer = Get-SzerokoscEkranu
    $tytul = 'PROJECT: PLAYTIME  ·  DOWNGRADER'

    Write-Wiersz 0 0 (Format-Barwa ('═' * $szer) 'Czerwony')

    $lewy  = "  $tytul"
    $prawy = if ($Wersja) { "$Wersja  " } else { '' }
    $wypelniacz = ' ' * [Math]::Max(1, $szer - $lewy.Length - $prawy.Length)
    Write-Wiersz 0 1 ((Format-Barwa $lewy 'Pogrub') + (Format-Barwa '' 'Reset') + $wypelniacz + (Format-Barwa $prawy 'Szary'))

    Write-Wiersz 0 2 (Format-Barwa ('═' * $szer) 'Czerwony')

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
    if ($Procent -lt 0)   { $Procent = 0 }
    if ($Procent -gt 100) { $Procent = 100 }

    $wnetrze = $Szerokosc - 2
    $pelne   = [int][Math]::Floor($wnetrze * $Procent / 100)
    $reszta  = ($wnetrze * $Procent / 100) - $pelne

    $czastki = @(' ', '▏', '▎', '▍', '▌', '▋', '▊', '▉')
    $ostatni = ''
    if ($pelne -lt $wnetrze) {
        $ostatni = $czastki[[int][Math]::Floor($reszta * 8)]
    }

    $puste = $wnetrze - $pelne - $(if ($ostatni -and $ostatni -ne ' ') { 1 } else { 0 })
    if ($puste -lt 0) { $puste = 0 }

    $tresc = (Format-Barwa ('█' * $pelne) $Barwa) +
             (Format-Barwa $ostatni $Barwa) +
             (Format-Barwa ('░' * $puste) 'Szary')

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

function Show-Menu {
    <#
        Pozycje: tablica obiektów z polami Etykieta oraz (opcjonalnie) Opis.
        Zwraca indeks wybranej pozycji albo -1 przy naciśnięciu Esc.
    #>
    param(
        [Parameter(Mandatory)] [array]$Pozycje,
        [string]$Tytul = '',
        [string]$Podtytul = '',
        [string]$Wersja = '',
        [int]$Zaznaczona = 0,
        [switch]$BezEscape
    )

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

        $klawisz = [Console]::ReadKey($true)
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
    $szer = Get-SzerokoscEkranu
    $szerRamki = $szer - 4
    $wys = $Wiersze.Count + 4

    $y = [Math]::Max(5, [int](([Console]::WindowHeight - $wys) / 2))
    Draw-Ramka -X 2 -Y $y -Szerokosc $szerRamki -Wysokosc $wys -Tytul $Tytul -Barwa $Barwa

    for ($i = 0; $i -lt $Wiersze.Count; $i++) {
        Write-Wiersz 4 ($y + 2 + $i) (Format-Skrot $Wiersze[$i] ($szerRamki - 4))
    }

    if (-not $BezOczekiwania) {
        Write-Wiersz 4 ($y + $wys) (Format-Barwa 'Naciśnij dowolny klawisz, aby kontynuować…' 'Przygas')
        [void][Console]::ReadKey($true)
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
    $y = [Console]::WindowHeight - 4
    Clear-Wiersz $y $szer
    Clear-Wiersz ($y + 1) $szer
    Write-Wiersz 2 $y (Format-Barwa $Etykieta 'Blekit')
    Write-Wiersz 2 ($y + 1) (Format-Barwa '› ' 'Czerwony')

    try { [Console]::SetCursorPosition(4, $y + 1) } catch { }
    try { [Console]::CursorVisible = $true } catch { }

    if ($Ukryte) {
        $bezpieczne = Read-Host -AsSecureString
        $wartosc = [Runtime.InteropServices.Marshal]::PtrToStringAuto(
            [Runtime.InteropServices.Marshal]::SecureStringToBSTR($bezpieczne))
    } else {
        $wartosc = Read-Host
    }

    try { [Console]::CursorVisible = $false } catch { }
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
