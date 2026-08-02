#Requires -Version 5.1
<#
    PROJECT: PLAYTIME - Downgrader
    Instalacja starszych kompilacji gry z zachowaniem działającego przycisku "Graj".

    Uruchamianie: Start.bat w katalogu głównego repozytorium.
#>

[CmdletBinding()]
param(
    [string]$Manifest,
    [switch]$BezTui
)

$ErrorActionPreference = 'Stop'
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

. "$PSScriptRoot\Tui.ps1"
. "$PSScriptRoot\Steam.ps1"
. "$PSScriptRoot\Depot.ps1"

# --- Konfiguracja ----------------------------------------------------------

$Wersja  = 'v1.3.0'
$AppId   = 1961460
$DepotId = 1961461

# Ostatnia publiczna aktualizacja gry: 30 października 2023 (build 12576441).
# Wartość służy jako zapas, gdy API steamcmd jest niedostępne.
$BuildIdZapasowy = '12576441'

# Nazwa katalogu w steamapps\common nie odpowiada tytułowi gry. Zwykle odczytywana
# jest z wpisu installdir, ta wartość służy wyłącznie jako zabezpieczenie.
$InstallDirZapasowy = 'Poppy Playtime - Multiplayer'

$Katalogi = @{
    Narzedzia = [System.IO.Path]::Combine($PSScriptRoot, '..', 'tools')
    Dziennik  = [System.IO.Path]::Combine($PSScriptRoot, '..', 'logs')
}

$Kompilacje = @(
    [pscustomobject]@{
        Etykieta = 'Faza 2 · Incineration  (bez EasyAntiCheat)'
        Opis     = 'Zalecana. Działa również pod Proton/Linux. Około 12 GB.'
        Manifest = '1265526790874008598'
    }
    [pscustomobject]@{
        Etykieta = 'Faza 2 · Incineration  (z EasyAntiCheat)'
        Opis     = 'Wariant z anticheatem. Wyłącznie Windows. Około 12 GB.'
        Manifest = '1362072626294775891'
    }
    [pscustomobject]@{
        Etykieta = 'Własny identyfikator manifestu'
        Opis     = 'Dowolna kompilacja z listy na steamdb.info/depot/1961461/manifests/'
        Manifest = $null
    }
)

# --- Dziennik --------------------------------------------------------------

$script:PlikDziennika = $null

function Initialize-Dziennik {
    New-Item -ItemType Directory -Path $Katalogi.Dziennik -Force | Out-Null
    $script:PlikDziennika = [System.IO.Path]::Combine(
        $Katalogi.Dziennik, ('sesja-{0:yyyyMMdd-HHmmss}.log' -f (Get-Date)))
    Zapisz-Dziennik "Downgrader $Wersja · PowerShell $($PSVersionTable.PSVersion) · $([Environment]::OSVersion.VersionString)"
}

function Zapisz-Dziennik {
    param([string]$Tekst)
    if (-not $script:PlikDziennika) { return }
    try {
        Add-Content -LiteralPath $script:PlikDziennika -Encoding UTF8 `
                    -Value ('[{0:HH:mm:ss}] {1}' -f (Get-Date), $Tekst)
    } catch { }
}

# --- Ekran diagnostyki -----------------------------------------------------

function Show-Diagnostyka {
    Clear-Ekran
    Draw-Naglowek -Podtytul 'Sprawdzanie środowiska' -Wersja $Wersja

    $kroki = New-ListaKrokow @(
        'Klient Steam',
        'Wpis instalacji gry',
        'Katalog instalacyjny',
        'Aktualna kompilacja na Steam',
        'Wolne miejsce na dysku'
    )
    $y = 6
    Draw-Kroki -Kroki $kroki -Y $y

    $ustaw = {
        param($i, $stan, $detal)
        $kroki[$i].Stan = $stan
        $kroki[$i].Detal = $detal
        Draw-Kroki -Kroki $kroki -Y $y
    }
    $pauza = { Wait-Klawisz -Tekst 'Naciśnij dowolny klawisz…' -Y ($y + $kroki.Count + 2) }

    & $ustaw 0 'trwa' ''
    $info = Get-InfoGry -AppId $AppId

    if (-not $info.SteamPath) {
        & $ustaw 0 'blad' 'nie znaleziono w rejestrze'
        & $pauza
        return $info
    }
    & $ustaw 0 'gotowe' $info.SteamPath

    # Brak wpisu ani katalogu nie jest błędem - program potrafi doprowadzić
    # instalację do stanu wymaganego do podmiany wersji.
    & $ustaw 1 'trwa' ''
    if ($info.Wpis) {
        & $ustaw 1 'gotowe' $info.Biblioteka
    } else {
        & $ustaw 1 'pominiete' 'gra nie jest zainstalowana'
    }

    & $ustaw 2 'trwa' ''
    if ($info.Zainstalowana -and $info.PelnaInstalacja) {
        & $ustaw 2 'gotowe' $info.InstallDir
    } elseif ($info.Zainstalowana) {
        & $ustaw 2 'pominiete' "$($info.InstallDir) · instalacja niekompletna"
    } else {
        & $ustaw 2 'pominiete' 'zostanie przygotowany przy instalacji'
    }

    & $ustaw 3 'trwa' 'odpytywanie api.steamcmd.net'
    $info.BuildIdZdalny = Get-AktualnyBuildId -AppId $AppId
    if ($info.BuildIdZdalny) {
        $zgodne = ($info.BuildIdZdalny -eq $info.BuildIdLokalny)
        if ($zgodne) { $detal = "$($info.BuildIdZdalny) · zgodna z lokalną" }
        else         { $detal = "$($info.BuildIdZdalny) · lokalna $($info.BuildIdLokalny)" }
        & $ustaw 3 'gotowe' $detal
    } else {
        $info.BuildIdZdalny = $BuildIdZapasowy
        & $ustaw 3 'pominiete' "brak łączności, przyjęto $BuildIdZapasowy"
    }

    & $ustaw 4 'trwa' ''
    if ($info.WolneGB -lt 14) {
        & $ustaw 4 'blad' "$($info.WolneGB) GB · zalecane co najmniej 14 GB"
    } else {
        & $ustaw 4 'gotowe' "$($info.WolneGB) GB"
    }

    Zapisz-Dziennik "Steam: $($info.SteamPath) | biblioteka: $($info.Biblioteka) | installdir: $($info.InstallDir) | pełna: $($info.PelnaInstalacja) | build lokalny: $($info.BuildIdLokalny) | build zdalny: $($info.BuildIdZdalny)"

    & $pauza
    return $info
}

# --- Wybór kompilacji ------------------------------------------------------

function Select-Kompilacja {
    $wybor = Show-Menu -Pozycje $Kompilacje -Tytul 'Którą wersję zainstalować?' `
                       -Podtytul 'Wszyscy gracze w sesji muszą mieć tę samą kompilację' -Wersja $Wersja
    if ($wybor -lt 0) { return $null }

    $wybrana = $Kompilacje[$wybor]
    if ($wybrana.Manifest) { return $wybrana }

    Clear-Ekran
    Draw-Naglowek -Podtytul 'Własny manifest' -Wersja $Wersja
    Write-Wiersz 2 5 (Format-Barwa 'Lista wszystkich kompilacji wraz z datami:' 'Bialy')
    Write-Wiersz 2 6 (Format-Barwa 'https://steamdb.info/depot/1961461/manifests/' 'Blekit')

    $wpis = (Read-Pole -Etykieta 'Identyfikator manifestu (same cyfry)').Trim()
    if ($wpis -notmatch '^\d+$') {
        Show-Komunikat -Wiersze @("Nieprawidłowy identyfikator: $wpis") -Tytul 'Błąd' -Barwa 'Czerwony'
        return $null
    }
    return [pscustomobject]@{
        Etykieta = "Kompilacja własna"
        Opis     = ''
        Manifest = $wpis
    }
}

# --- Logowanie -------------------------------------------------------------

function Show-DlaczegoLogowanie {
    <#
        Pytanie pojawia się naturalnie: klient Steam jest zalogowany, więc po co
        drugie logowanie. Ekran wyjaśnia to zamiast zostawiać użytkownika z domysłami.
    #>
    $szer = Get-SzerokoscEkranu
    Clear-Ekran
    Draw-Naglowek -Podtytul 'Dlaczego wymagane jest logowanie' -Wersja $Wersja

    $tresc = @(
        'DepotDownloader nie jest wtyczką do klienta Steam, tylko osobnym programem',
        'z własnym połączeniem do serwerów Valve. Sesja klienta jest zaszyfrowana',
        'i związana z jego procesem — nie da się jej pożyczyć.',
        '',
        'Aby pobrać wskazaną kompilację, narzędzie musi samo uzyskać klucz depotu,',
        'a do tego potrzebuje uwierzytelnienia na koncie posiadającym grę.',
        '',
        'Logowanie jest jednorazowe. Token sesji zostaje zapisany, więc przy',
        'kolejnych uruchomieniach hasło nie będzie już potrzebne.',
        '',
        'Hasło i kod Steam Guard wpisywane są bezpośrednio w oknie DepotDownloadera.',
        'Ten program ich nie widzi i nigdzie nie zapisuje.'
    )
    for ($i = 0; $i -lt $tresc.Count; $i++) {
        $barwa = 'Bialy'
        if ($tresc[$i] -like 'Logowanie jest jednorazowe*') { $barwa = 'Zielony' }
        Write-Wiersz 4 (5 + $i) (Format-Barwa (Format-Skrot $tresc[$i] ($szer - 8)) $barwa)
    }

    Write-Wiersz 2 (7 + $tresc.Count) (Format-Barwa 'Naciśnij dowolny klawisz…' 'Przygas')
    [void][Console]::ReadKey($true)
}

function Invoke-Logowanie {
    param([Parameter(Mandatory)][string]$Exe, [Parameter(Mandatory)][string]$ManifestId)

    $zapamietane = Get-ZapamietaneKonto -KatalogNarzedzi $Katalogi.Narzedzia
    $sesja       = Test-ZapisanaSesja  -KatalogNarzedzi $Katalogi.Narzedzia

    $metody = @()
    if ($zapamietane) {
        if ($sesja) { $opis = 'Zapisana sesja — hasło nie będzie potrzebne.' }
        else        { $opis = 'Konto z poprzedniego uruchomienia.' }
        $metody += [pscustomobject]@{ Etykieta = "Kontynuuj jako $zapamietane"; Opis = $opis }
    }
    $metody += [pscustomobject]@{ Etykieta = 'Nazwa użytkownika i hasło'; Opis = 'Pełny podgląd postępu pobierania. Logowanie jednorazowe.' }
    $metody += [pscustomobject]@{ Etykieta = 'Kod QR w aplikacji Steam';  Opis = 'Bez wpisywania hasła. Postęp w trybie tekstowym.' }
    $metody += [pscustomobject]@{ Etykieta = 'Dlaczego to jest wymagane?'; Opis = 'Klient Steam jest zalogowany, a mimo to potrzebne jest logowanie' }

    $podtytul = 'Dane trafiają wyłącznie do DepotDownloadera (projekt SteamRE)'
    $wybor = Show-Menu -Pozycje $metody -Tytul 'Logowanie do Steam' -Podtytul $podtytul -Wersja $Wersja
    if ($wybor -lt 0) { return $null }

    # przesunięcie indeksów, gdy pierwsza pozycja to zapamiętane konto
    $przesuniecie = 0
    if ($zapamietane) { $przesuniecie = 1 }

    if ($wybor -eq ($metody.Count - 1)) {
        Show-DlaczegoLogowanie
        return (Invoke-Logowanie -Exe $Exe -ManifestId $ManifestId)
    }

    $qr = ($wybor -eq ($przesuniecie + 1))
    $uzytkownik = $null

    if ($zapamietane -and $wybor -eq 0) {
        $uzytkownik = $zapamietane
    } elseif (-not $qr) {
        Clear-Ekran
        Draw-Naglowek -Podtytul 'Logowanie do Steam' -Wersja $Wersja
        Write-Wiersz 2 5 (Format-Barwa 'Hasło i kod Steam Guard zostaną podane w oknie DepotDownloadera.' 'Bialy')
        Write-Wiersz 2 6 (Format-Barwa 'Ten skrypt nigdy ich nie widzi ani nie zapisuje.' 'Przygas')
        Write-Wiersz 2 7 (Format-Barwa 'Logowanie jednorazowe — token sesji zostanie zapamiętany.' 'Zielony')
        $uzytkownik = (Read-Pole -Etykieta 'Nazwa konta Steam').Trim()
        if (-not $uzytkownik) { return $null }
    }

    Clear-Ekran
    Restore-Console
    Write-Host ''
    Write-Host '  Trwa logowanie do Steam. Postępuj zgodnie z komunikatami poniżej.' -ForegroundColor Cyan
    Write-Host '  ------------------------------------------------------------------' -ForegroundColor DarkGray
    Write-Host ''

    $ok = Invoke-LogowanieSteam -Exe $Exe -AppId $AppId -DepotId $DepotId `
                                -Manifest $ManifestId -Uzytkownik $uzytkownik -KodQr:$qr

    Zapisz-Dziennik "Logowanie: $(if ($ok) { 'powodzenie' } else { 'niepowodzenie' }) | QR: $qr"

    if (-not $ok) {
        Write-Host ''
        Write-Host '  Logowanie nie powiodło się.' -ForegroundColor Red
        Write-Host '  Najczęstsze przyczyny: błędne hasło, brak gry na koncie,' -ForegroundColor DarkGray
        Write-Host '  niedostępny manifest lub odrzucone potwierdzenie Steam Guard.' -ForegroundColor DarkGray
        Write-Host ''
        Read-Host '  Naciśnij Enter, aby wrócić do menu'
        return $null
    }

    # Po zalogowaniu kodem QR nazwa konta nie jest znana, a bez niej pobieranie
    # wymagałoby zeskanowania drugiego kodu i musiałoby działać w trybie tekstowym.
    # Token zapisany w account.config zawiera ją jako klucz słownika - odczytanie
    # nazwy pozwala potraktować sesję QR tak samo jak zwykłą i pokazać pełny interfejs.
    if ($qr) {
        $kandydaci = Get-NazwyKontZSesji -KatalogNarzedzi $Katalogi.Narzedzia
        Zapisz-Dziennik "Sesja QR: kandydatów na nazwę konta: $($kandydaci.Count)"

        [Console]::CursorVisible = $false
        if ($kandydaci.Count -eq 1) {
            $uzytkownik = $kandydaci[0]
            $qr = $false
        } elseif ($kandydaci.Count -gt 1) {
            $pozycje = @()
            foreach ($k in $kandydaci) { $pozycje += [pscustomobject]@{ Etykieta = $k; Opis = '' } }
            $pozycje += [pscustomobject]@{ Etykieta = 'Żadne z powyższych'; Opis = 'Pobieranie w trybie tekstowym, z ponownym kodem QR' }

            $w = Show-Menu -Pozycje $pozycje -Tytul 'Które konto zostało użyte?' `
                           -Podtytul 'Wskazanie konta pozwala pokazać pełny podgląd postępu' -Wersja $Wersja -BezEscape
            if ($w -lt $kandydaci.Count) {
                $uzytkownik = $kandydaci[$w]
                $qr = $false
            }
        } else {
            # Ostatnia deska ratunku przed trybem tekstowym: nazwę konta użytkownik zna,
            # a token jest już zapisany, więc jej podanie wystarczy do pełnego interfejsu.
            Clear-Ekran
            Draw-Naglowek -Podtytul 'Nazwa konta' -Wersja $Wersja
            Write-Wiersz 2 5 (Format-Barwa 'Logowanie powiodło się, ale nie udało się odczytać nazwy konta.' 'Bialy')
            Write-Wiersz 2 6 (Format-Barwa 'Podanie jej pozwoli pokazać pasek postępu zamiast surowego tekstu.' 'Przygas')
            Write-Wiersz 2 7 (Format-Barwa 'Pominięcie (Enter) uruchomi pobieranie w trybie tekstowym.' 'Przygas')

            $wpis = (Read-Pole -Etykieta 'Nazwa konta Steam').Trim()
            if ($wpis) { $uzytkownik = $wpis; $qr = $false }
            [Console]::CursorVisible = $false
        }
    }

    if ($uzytkownik) { Set-ZapamietaneKonto -KatalogNarzedzi $Katalogi.Narzedzia -Uzytkownik $uzytkownik }

    [Console]::CursorVisible = $false
    return [pscustomobject]@{ Uzytkownik = $uzytkownik; Qr = $qr }
}

# --- Ekran pobierania ------------------------------------------------------

function Show-Pobieranie {
    param(
        [Parameter(Mandatory)][string]$Exe,
        [Parameter(Mandatory)][object]$Kompilacja,
        [Parameter(Mandatory)][string]$KatalogDocelowy,
        [string]$Uzytkownik
    )

    $szer = Get-SzerokoscEkranu
    Clear-Ekran
    Draw-Naglowek -Podtytul 'Pobieranie zawartości' -Wersja $Wersja

    Write-Wiersz 2 5 (Format-Barwa (Format-Skrot $Kompilacja.Etykieta ($szer - 4)) 'Bialy')
    Write-Wiersz 2 6 (Format-Barwa "manifest $($Kompilacja.Manifest)   ·   depot $DepotId" 'Przygas')

    $yPasek  = 8
    $yStat   = 10
    $yPlik   = 13
    $yLog    = 15
    $wysLog  = [Math]::Max(5, [Console]::WindowHeight - $yLog - 3)
    $szerLog = $szer - 4

    Draw-Ramka -X 2 -Y $yLog -Szerokosc $szerLog -Wysokosc $wysLog -Tytul 'Dziennik' -Barwa 'Szary'

    $stan = Start-PobieranieDepotu -Exe $Exe -AppId $AppId -DepotId $DepotId `
                                   -Manifest $Kompilacja.Manifest -Katalog $KatalogDocelowy `
                                   -Uzytkownik $Uzytkownik
    Zapisz-Dziennik "Start pobierania: manifest $($Kompilacja.Manifest) do $KatalogDocelowy"

    $klatka = 0
    $ostatniLog = -1

    try {
        while (-not $stan.Zakonczone) {
            $stan = Update-StanPobierania -Stan $stan

            $uplyw = ((Get-Date) - $stan.Start).TotalSeconds
            if ($stan.Procent -gt 0.5) {
                $pozostalo = $uplyw * (100 - $stan.Procent) / $stan.Procent
            } else {
                $pozostalo = -1
            }
            if ($stan.Procent -gt 0.5) {
                $calosc = $stan.Bajty * 100 / $stan.Procent
            } else {
                $calosc = 0
            }

            Draw-Pasek -X 2 -Y $yPasek -Szerokosc ($szer - 14) -Procent $stan.Procent
            Write-Wiersz ($szer - 11) $yPasek (Format-Barwa ('{0,6:N2} %' -f $stan.Procent) 'Bialy')

            $rozmiar = Format-Bajty $stan.Bajty
            if ($calosc -gt 0) { $rozmiar += ' / ' + (Format-Bajty $calosc) }

            Clear-Wiersz $yStat $szer
            Write-Wiersz 4 $yStat (
                (Format-Barwa 'Pobrano   ' 'Przygas') + (Format-Barwa ('{0,-22}' -f $rozmiar) 'Bialy') +
                (Format-Barwa 'Prędkość  ' 'Przygas') + (Format-Barwa ('{0}/s' -f (Format-Bajty $stan.Predkosc)) 'Zielony'))

            Clear-Wiersz ($yStat + 1) $szer
            Write-Wiersz 4 ($yStat + 1) (
                (Format-Barwa 'Czas      ' 'Przygas') + (Format-Barwa ('{0,-22}' -f (Format-Czas $uplyw)) 'Bialy') +
                (Format-Barwa 'Pozostało ' 'Przygas') + (Format-Barwa (Format-Czas $pozostalo) 'Zolty'))

            Clear-Wiersz $yPlik $szer
            Write-Wiersz 2 $yPlik (
                (Format-Barwa " $(Get-Spinner $klatka) " 'Czerwony') +
                (Format-Barwa (Format-Skrot $stan.PlikBiezacy ($szer - 8)) 'Blekit'))

            if ($stan.Dziennik.Count -ne $ostatniLog) {
                $ostatniLog = $stan.Dziennik.Count
                $ile = $wysLog - 2
                $od = [Math]::Max(0, $stan.Dziennik.Count - $ile)
                for ($i = 0; $i -lt $ile; $i++) {
                    $idx = $od + $i
                    if ($idx -lt $stan.Dziennik.Count) { $tekst = $stan.Dziennik[$idx] } else { $tekst = '' }
                    Write-Wiersz 4 ($yLog + 1 + $i) (Format-Barwa ('{0,-' + ($szerLog - 5) + '}' -f (Format-Skrot $tekst ($szerLog - 6))) 'Przygas')
                }
            }

            # tytuł okna aktualizowany raz na sekundę - postęp widać na pasku zadań
            # także wtedy, gdy okno jest zminimalizowane
            if ($klatka % 8 -eq 0) {
                Set-TytulOkna ('{0:N1}%  ·  {1}/s  ·  PROJECT: PLAYTIME Downgrader' -f $stan.Procent, (Format-Bajty $stan.Predkosc))
            }

            if ($stan.Blad) { break }

            $klatka++
            Start-Sleep -Milliseconds 120
        }
    } finally {
        $stan = Update-StanPobierania -Stan $stan
        Stop-PobieranieDepotu -Stan $stan
    }

    foreach ($w in $stan.Dziennik) { Zapisz-Dziennik "  DD> $w" }
    Zapisz-Dziennik "Pobieranie zakończone: kod $($stan.KodWyjscia), $(Format-Bajty $stan.Bajty)"

    if ($stan.Blad) {
        Set-TytulOkna 'PRZERWANO · PROJECT: PLAYTIME Downgrader'
        Invoke-Sygnal -Blad
        Show-Komunikat -Wiersze @($stan.Blad, '', 'Uruchom logowanie ponownie z poziomu menu głównego.') `
                       -Tytul 'Przerwano' -Barwa 'Czerwony'
        return $false
    }
    if ($stan.KodWyjscia -ne 0) {
        Set-TytulOkna 'BŁĄD · PROJECT: PLAYTIME Downgrader'
        Invoke-Sygnal -Blad
        $ogon = @($stan.Dziennik | Select-Object -Last 6)
        Show-Komunikat -Wiersze (@("DepotDownloader zakończył pracę z kodem $($stan.KodWyjscia).", '') + $ogon) `
                       -Tytul 'Błąd pobierania' -Barwa 'Czerwony'
        return $false
    }

    return $true
}

# --- Instalacja ------------------------------------------------------------

function Install-Kompilacja {
    param(
        [Parameter(Mandatory)][object]$Info,
        [Parameter(Mandatory)][string]$KatalogZrodlowy,
        [Parameter(Mandatory)][object]$Kompilacja
    )

    Clear-Ekran
    Draw-Naglowek -Podtytul 'Instalacja' -Wersja $Wersja

    $kroki = New-ListaKrokow @(
        'Zamknięcie klienta Steam',
        'Kopia zapasowa obecnej wersji',
        'Przeniesienie pobranej wersji',
        'Konfiguracja przycisku „Graj"',
        'Skrót na pulpicie'
    )
    $y = 6
    Draw-Kroki -Kroki $kroki -Y $y
    $ustaw = {
        param($i, $stan, $detal)
        $kroki[$i].Stan = $stan
        $kroki[$i].Detal = $detal
        Draw-Kroki -Kroki $kroki -Y $y
    }

    # 1 — Steam musi być zamknięty, w przeciwnym razie trzyma uchwyty do plików
    & $ustaw 0 'trwa' ''
    if (-not (Stop-Steam -SteamPath $Info.SteamPath)) {
        & $ustaw 0 'blad' 'proces nadal działa'
        Show-Komunikat -Wiersze @('Nie udało się zamknąć klienta Steam.',
                                  'Zamknij go ręcznie i uruchom instalację ponownie.') `
                       -Tytul 'Przerwano' -Barwa 'Czerwony'
        return $null
    }
    & $ustaw 0 'gotowe' ''

    # 2 — kopia ma sens wyłącznie dla kompletnej instalacji; szczątki po przerwanym
    #     pobieraniu tylko zajęłyby kilkanaście gigabajtów bez żadnej wartości
    & $ustaw 1 'trwa' ''
    $kopia = $null
    if (-not [System.IO.Directory]::Exists($Info.KatalogGry)) {
        & $ustaw 1 'pominiete' 'brak istniejącej instalacji'
    } elseif (-not $Info.PelnaInstalacja) {
        try {
            $szczatki = Get-RozmiarKatalogu -Sciezka $Info.KatalogGry
            Remove-Item -LiteralPath $Info.KatalogGry -Recurse -Force -ErrorAction SilentlyContinue
            & $ustaw 1 'pominiete' "niekompletna instalacja — usunięto $(Format-Bajty $szczatki)"
        } catch {
            & $ustaw 1 'pominiete' 'niekompletna instalacja'
        }
    } else {
        $kopia = "$($Info.KatalogGry).backup_$(Get-Date -Format 'yyyyMMdd-HHmmss')"
        try {
            [System.IO.Directory]::Move($Info.KatalogGry, $kopia)
            & $ustaw 1 'gotowe' ([System.IO.Path]::GetFileName($kopia))
        } catch {
            & $ustaw 1 'blad' $_.Exception.Message
            Show-Komunikat -Wiersze @('Nie udało się utworzyć kopii zapasowej:', $_.Exception.Message) `
                           -Tytul 'Przerwano' -Barwa 'Czerwony'
            return $null
        }
    }

    # 3 — przeniesienie w obrębie tego samego wolumenu jest natychmiastowe
    & $ustaw 2 'trwa' ''
    try {
        [System.IO.Directory]::Move($KatalogZrodlowy, $Info.KatalogGry)
        & $ustaw 2 'gotowe' ''
    } catch {
        & $ustaw 2 'blad' $_.Exception.Message
        if ($kopia) {
            try { [System.IO.Directory]::Move($kopia, $Info.KatalogGry) } catch { }
        }
        Show-Komunikat -Wiersze @('Nie udało się przenieść pobranych plików:', $_.Exception.Message,
                                  '', 'Poprzednia wersja została przywrócona.') `
                       -Tytul 'Przerwano' -Barwa 'Czerwony'
        return $null
    }

    # 4 — identyfikator pobierany na bieżąco; stan z ekranu diagnostyki mógł się
    #     zdezaktualizować, a wpisanie złej wartości od razu wywołałoby aktualizację
    & $ustaw 3 'trwa' 'odpytywanie api.steamcmd.net'
    $build = Get-AktualnyBuildId -AppId $AppId
    if (-not $build) { $build = $Info.BuildIdZdalny }
    if (-not $build) { $build = $BuildIdZapasowy }
    $zmiany = Set-BlokadaAktualizacji -Acf $Info.Acf -BuildId $build
    & $ustaw 3 'gotowe' "buildid $build, StateFlags 4"
    Zapisz-Dziennik "Blokada aktualizacji: $(($zmiany.GetEnumerator() | ForEach-Object { "$($_.Key)=$($_.Value)" }) -join ', ')"

    # 5
    & $ustaw 4 'trwa' ''
    $exe = Get-ExeGry -KatalogGry $Info.KatalogGry
    $skrot = $null
    if ($exe) {
        $skrot = New-SkrotPulpitu -Cel $exe.FullName -Nazwa 'PROJECT PLAYTIME (starsza wersja)'
        if ($skrot) { & $ustaw 4 'gotowe' $exe.Name } else { & $ustaw 4 'pominiete' 'nie udało się utworzyć' }
    } else {
        & $ustaw 4 'pominiete' 'nie znaleziono pliku wykonywalnego'
    }

    Start-Sleep -Milliseconds 600

    return [pscustomobject]@{
        Kopia = $kopia
        Skrot = $skrot
        Exe   = $(if ($exe) { $exe.FullName } else { $null })
        Build = $build
    }
}

function Show-Podsumowanie {
    param([Parameter(Mandatory)][object]$Wynik, [Parameter(Mandatory)][object]$Kompilacja)

    Set-TytulOkna 'GOTOWE · PROJECT: PLAYTIME Downgrader'
    Invoke-Sygnal

    Clear-Ekran
    Draw-Naglowek -Podtytul 'Instalacja zakończona' -Wersja $Wersja
    $szer = Get-SzerokoscEkranu

    $y = 5
    Write-Wiersz 2 $y (Format-Barwa '  ✔  GOTOWE' 'Zielony')
    Write-Wiersz 13 $y (Format-Barwa '— gra jest gotowa do uruchomienia' 'Bialy')
    $y += 2

    # Wykaz tego, co faktycznie zostało zrobione. Bez niego użytkownik po długim
    # pobieraniu nie ma jak stwierdzić, które kroki się powiodły.
    $kroki = @(
        @('✔', "Pobrano kompilację  ·  manifest $($Kompilacja.Manifest)", 'Zielony')
    )
    if ($Wynik.Kopia) {
        $kroki += , @('✔', "Poprzednią wersję zachowano jako $([System.IO.Path]::GetFileName($Wynik.Kopia))", 'Zielony')
    } else {
        $kroki += , @('–', 'Kopia zapasowa: brak poprzedniej instalacji do zachowania', 'Szary')
    }
    $kroki += , @('✔', 'Pliki gry podmieniono w bibliotece Steam', 'Zielony')
    # cudzysłowy drukarskie tylko w łańcuchach apostrofowych: PowerShell traktuje
    # znak ” jako ogranicznik i przerywa na nim łańcuch w cudzysłowach prostych
    $kroki += , @('✔', 'Przycisk „Graj” skonfigurowany  ·  buildid ' + $Wynik.Build, 'Zielony')
    if ($Wynik.Skrot) {
        $kroki += , @('✔', 'Skrót „PROJECT PLAYTIME (starsza wersja)” na pulpicie', 'Zielony')
    } else {
        $kroki += , @('–', 'Skrót na pulpicie: nie utworzono', 'Szary')
    }

    foreach ($k in $kroki) {
        Write-Wiersz 4 $y ((Format-Barwa "$($k[0])  " $k[2]) + (Format-Barwa (Format-Skrot $k[1] ($szer - 10)) 'Bialy'))
        $y++
    }
    $y++

    Write-Wiersz 4 $y (Format-Barwa (Format-Skrot "Zainstalowana wersja: $($Kompilacja.Etykieta)" ($szer - 8)) 'Blekit')
    $y += 2

    Draw-Ramka -X 2 -Y $y -Szerokosc ($szer - 4) -Wysokosc 6 -Tytul 'Jak uruchomić' -Barwa 'Zielony'
    $tresc = @(
        'Naciśnij „Graj” w Steam albo użyj skrótu z pulpitu — działają tak samo.',
        'Aktualizacja nie zostanie pobrana.',
        'Nie używaj opcji „Sprawdź spójność plików gry”: cofa całą operację.'
    )
    for ($i = 0; $i -lt $tresc.Count; $i++) {
        Write-Wiersz 4 ($y + 1 + $i) (Format-Barwa (Format-Skrot $tresc[$i] ($szer - 8)) 'Bialy')
    }

    $y += 7
    Wait-Klawisz -Tekst 'Naciśnij dowolny klawisz, aby wrócić do menu…' -Y $y
}

# --- Pozostałe akcje menu --------------------------------------------------

function Invoke-NaprawaPrzycisku {
    param([Parameter(Mandatory)][object]$Info)

    Clear-Ekran
    Draw-Naglowek -Podtytul 'Naprawa przycisku „Graj"' -Wersja $Wersja
    $szer = Get-SzerokoscEkranu

    $build = Get-AktualnyBuildId -AppId $AppId
    if (-not $build) { $build = $BuildIdZapasowy }

    $opis = @(
        'Operacja zapisuje w pliku appmanifest informację, że instalacja jest',
        'kompletna i zgodna z bieżącą kompilacją publiczną. Pliki gry pozostają',
        'nietknięte, więc Steam przestaje planować aktualizację.',
        '',
        "Bieżąca kompilacja publiczna: $build",
        "Zapisana w appmanifest:       $($Info.BuildIdLokalny)"
    )
    for ($i = 0; $i -lt $opis.Count; $i++) {
        Write-Wiersz 4 (5 + $i) (Format-Barwa (Format-Skrot $opis[$i] ($szer - 8)) 'Bialy')
    }
    Start-Sleep -Milliseconds 400

    if (-not (Confirm-Tui -Pytanie 'Zastosować ustawienia?' -Opis 'Klient Steam zostanie zamknięty')) { return }

    if (-not (Stop-Steam -SteamPath $Info.SteamPath)) {
        Show-Komunikat -Wiersze @('Klient Steam nadal działa. Zamknij go i spróbuj ponownie.') `
                       -Tytul 'Przerwano' -Barwa 'Czerwony'
        return
    }

    $zmiany = Set-BlokadaAktualizacji -Acf $Info.Acf -BuildId $build
    Zapisz-Dziennik "Naprawa przycisku: $(($zmiany.GetEnumerator() | ForEach-Object { "$($_.Key)=$($_.Value)" }) -join ', ')"

    $wiersze = @('Zapisane wartości:', '')
    foreach ($z in $zmiany.GetEnumerator()) { $wiersze += "  $($z.Key) = $($z.Value)" }
    Show-Komunikat -Wiersze $wiersze -Tytul 'Gotowe' -Barwa 'Zielony'
}

function Invoke-Przywracanie {
    param([Parameter(Mandatory)][object]$Info)

    $kopie = Get-KopieZapasowe -Biblioteka $Info.Biblioteka -InstallDir $Info.InstallDir
    if ($kopie.Count -eq 0) {
        Show-Komunikat -Wiersze @('Nie odnaleziono żadnej kopii zapasowej.') -Tytul 'Brak kopii' -Barwa 'Zolty'
        return
    }

    $pozycje = @()
    foreach ($k in $kopie) {
        $data = $k.Name -replace '^.*backup_', ''
        $pozycje += [pscustomobject]@{
            Etykieta = "Kopia z $data"
            Opis     = $k.FullName
        }
    }

    $wybor = Show-Menu -Pozycje $pozycje -Tytul 'Którą kopię przywrócić?' `
                       -Podtytul 'Bieżąca zawartość katalogu gry zostanie usunięta' -Wersja $Wersja
    if ($wybor -lt 0) { return }
    $kopia = $kopie[$wybor]

    if (-not (Confirm-Tui -Pytanie 'Przywrócić tę kopię?' -Opis $kopia.FullName -DomyslnieNie)) { return }

    Clear-Ekran
    Draw-Naglowek -Podtytul 'Przywracanie' -Wersja $Wersja
    $kroki = New-ListaKrokow @('Zamknięcie klienta Steam', 'Usunięcie bieżącej zawartości', 'Przywrócenie kopii', 'Reset ustawień aktualizacji')
    $y = 6
    Draw-Kroki -Kroki $kroki -Y $y
    $ustaw = { param($i, $s, $d) $kroki[$i].Stan = $s; $kroki[$i].Detal = $d; Draw-Kroki -Kroki $kroki -Y $y }

    & $ustaw 0 'trwa' ''
    if (-not (Stop-Steam -SteamPath $Info.SteamPath)) {
        & $ustaw 0 'blad' 'proces nadal działa'
        Show-Komunikat -Wiersze @('Zamknij klienta Steam i spróbuj ponownie.') -Tytul 'Przerwano' -Barwa 'Czerwony'
        return
    }
    & $ustaw 0 'gotowe' ''

    & $ustaw 1 'trwa' ''
    if ([System.IO.Directory]::Exists($Info.KatalogGry)) {
        try {
            Remove-Item -LiteralPath $Info.KatalogGry -Recurse -Force
            & $ustaw 1 'gotowe' ''
        } catch {
            & $ustaw 1 'blad' $_.Exception.Message
            Show-Komunikat -Wiersze @('Nie udało się usunąć katalogu gry:', $_.Exception.Message) -Tytul 'Przerwano' -Barwa 'Czerwony'
            return
        }
    } else {
        & $ustaw 1 'pominiete' ''
    }

    & $ustaw 2 'trwa' ''
    try {
        [System.IO.Directory]::Move($kopia.FullName, $Info.KatalogGry)
        & $ustaw 2 'gotowe' ''
    } catch {
        & $ustaw 2 'blad' $_.Exception.Message
        Show-Komunikat -Wiersze @('Nie udało się przywrócić kopii:', $_.Exception.Message) -Tytul 'Przerwano' -Barwa 'Czerwony'
        return
    }

    & $ustaw 3 'trwa' ''
    $build = Get-AktualnyBuildId -AppId $AppId
    if (-not $build) { $build = $BuildIdZapasowy }
    Reset-BlokadaAktualizacji -Acf $Info.Acf -BuildId $build
    & $ustaw 3 'gotowe' ''
    Zapisz-Dziennik "Przywrócono kopię: $($kopia.FullName)"

    Start-Sleep -Milliseconds 500
    Show-Komunikat -Wiersze @('Oryginalna instalacja została przywrócona.', '',
                              'Jeżeli gra nie uruchamia się poprawnie, użyj w Steam opcji',
                              '„Sprawdź spójność plików gry".') -Tytul 'Gotowe' -Barwa 'Zielony'
}

function Invoke-ZarzadzanieKopiami {
    param([Parameter(Mandatory)][object]$Info)

    $kopie = Get-KopieZapasowe -Biblioteka $Info.Biblioteka -InstallDir $Info.InstallDir
    if ($kopie.Count -eq 0) {
        Show-Komunikat -Wiersze @('Nie odnaleziono żadnej kopii zapasowej.') -Tytul 'Kopie zapasowe' -Barwa 'Blekit'
        return
    }

    $pozycje = @()
    foreach ($k in $kopie) {
        $rozmiar = Format-Bajty (Get-RozmiarKatalogu -Sciezka $k.FullName)
        $pozycje += [pscustomobject]@{
            Etykieta = "$($k.Name)   ·   $rozmiar"
            Opis     = 'Enter usuwa tę kopię i zwalnia miejsce na dysku'
        }
    }

    $wybor = Show-Menu -Pozycje $pozycje -Tytul 'Kopie zapasowe' `
                       -Podtytul 'Usunięcie kopii jest nieodwracalne' -Wersja $Wersja
    if ($wybor -lt 0) { return }

    $kopia = $kopie[$wybor]
    if (Confirm-Tui -Pytanie 'Usunąć tę kopię zapasową?' -Opis $kopia.FullName -DomyslnieNie) {
        try {
            Remove-Item -LiteralPath $kopia.FullName -Recurse -Force
            Zapisz-Dziennik "Usunięto kopię: $($kopia.FullName)"
            Show-Komunikat -Wiersze @('Kopia została usunięta.') -Tytul 'Gotowe' -Barwa 'Zielony'
        } catch {
            Show-Komunikat -Wiersze @('Nie udało się usunąć kopii:', $_.Exception.Message) -Tytul 'Błąd' -Barwa 'Czerwony'
        }
    }
}

# --- Przygotowanie gry, gdy nie ma jej w bibliotece -------------------------

function Show-PostepSteam {
    <#
        Rysuje postęp pobierania realizowanego przez klienta Steam. Dane pochodzą
        z appmanifest, który klient aktualizuje na bieżąco.
    #>
    param([Parameter(Mandatory)][string]$Acf)

    $szer = Get-SzerokoscEkranu
    Clear-Ekran
    Draw-Naglowek -Podtytul 'Instalacja wersji bazowej przez Steam' -Wersja $Wersja

    Write-Wiersz 2 5 (Format-Barwa 'Pobieranie prowadzi klient Steam. Okno można zminimalizować.' 'Bialy')
    Write-Wiersz 2 6 (Format-Barwa 'Esc przerywa oczekiwanie i wraca do menu (pobieranie trwa dalej).' 'Przygas')

    $yPasek = 9
    $yStat  = 11
    $klatka = 0
    $start  = Get-Date

    while ($true) {
        $stan = Get-PostepInstalacjiSteam -Acf $Acf
        if ($stan.Gotowe) { return $true }

        Draw-Pasek -X 2 -Y $yPasek -Szerokosc ($szer - 14) -Procent $stan.Procent
        Write-Wiersz ($szer - 11) $yPasek (Format-Barwa ('{0,6:N2} %' -f $stan.Procent) 'Bialy')

        $rozmiar = Format-Bajty $stan.Bajty
        if ($stan.Calosc -gt 0) { $rozmiar += ' / ' + (Format-Bajty $stan.Calosc) }

        Clear-Wiersz $yStat $szer
        Write-Wiersz 4 $yStat (
            (Format-Barwa 'Pobrano   ' 'Przygas') + (Format-Barwa ('{0,-24}' -f $rozmiar) 'Bialy') +
            (Format-Barwa 'Czas  ' 'Przygas') + (Format-Barwa (Format-Czas ((Get-Date) - $start).TotalSeconds) 'Bialy'))

        Clear-Wiersz ($yStat + 2) $szer
        Write-Wiersz 2 ($yStat + 2) (
            (Format-Barwa " $(Get-Spinner $klatka) " 'Czerwony') +
            (Format-Barwa ('StateFlags ' + $stan.StateFlags + ' — oczekiwanie na stan „w pełni zainstalowana”') 'Blekit'))

        if ($klatka % 3 -eq 0) {
            Set-TytulOkna ('Steam: {0:N1}%  ·  PROJECT: PLAYTIME Downgrader' -f $stan.Procent)
        }

        if (Test-Escape) { return $false }
        $klatka++
        Start-Sleep -Milliseconds 400
    }
}

function Invoke-PrzygotowanieGry {
    <#
        Doprowadza system do stanu, w którym możliwa jest podmiana wersji:
        gra musi mieć wpis appmanifest oraz katalog w bibliotece Steam.
        Zwraca zaktualizowany obiekt informacji albo $null przy rezygnacji.
    #>
    param([Parameter(Mandatory)][object]$Info)

    $opcje = @(
        [pscustomobject]@{
            Etykieta = 'Zarejestruj grę i pobierz od razu starszą wersję'
            Opis     = 'Zalecane. Na dysk trafia tylko wybrana kompilacja — około 12 GB.'
        }
        [pscustomobject]@{
            Etykieta = 'Zainstaluj pełną wersję bieżącą, potem cofnij ją do starszej'
            Opis     = 'Bez skrótów, ale pobiera dwukrotnie — około 24 GB.'
        }
    )

    $wybor = Show-Menu -Pozycje $opcje -Tytul 'Gra nie jest zainstalowana' `
                       -Podtytul 'PROJECT: PLAYTIME jest darmowe — wystarczy dodać je do konta' -Wersja $Wersja
    if ($wybor -lt 0) { return $null }
    $trybOszczedny = ($wybor -eq 0)

    Clear-Ekran
    Draw-Naglowek -Podtytul 'Przygotowanie gry' -Wersja $Wersja

    $kroki = New-ListaKrokow @(
        'Uruchomienie klienta Steam',
        'Otwarcie okna instalacji',
        'Oczekiwanie na wpis instalacji',
        'Pobranie wersji bazowej'
    )
    $y = 6
    Draw-Kroki -Kroki $kroki -Y $y
    $ustaw = { param($i, $s, $d) $kroki[$i].Stan = $s; $kroki[$i].Detal = $d; Draw-Kroki -Kroki $kroki -Y $y }

    # 1
    & $ustaw 0 'trwa' ''
    if (-not (Start-SteamKlient -SteamPath $Info.SteamPath)) {
        & $ustaw 0 'blad' 'nie udało się uruchomić'
        Show-Komunikat -Wiersze @('Nie udało się uruchomić klienta Steam.',
                                  'Uruchom go ręcznie i spróbuj ponownie.') -Tytul 'Przerwano' -Barwa 'Czerwony'
        return $null
    }
    & $ustaw 0 'gotowe' ''

    # 2
    & $ustaw 1 'trwa' ''
    if (-not (Request-InstalacjaGry -AppId $AppId)) {
        & $ustaw 1 'blad' 'protokół steam:// niedostępny'
        Show-Komunikat -Wiersze @('Nie udało się otworzyć okna instalacji.', '',
                                  'Dodaj grę ręcznie ze sklepu Steam, a następnie',
                                  'uruchom program ponownie.') -Tytul 'Przerwano' -Barwa 'Czerwony'
        return $null
    }
    & $ustaw 1 'gotowe' "steam://install/$AppId"

    # 3
    & $ustaw 2 'trwa' 'potwierdź instalację w oknie Steam'
    $yPodpowiedz = $y + $kroki.Count + 2
    Write-Wiersz 2 $yPodpowiedz (Format-Barwa 'W oknie klienta Steam wybierz dysk i kliknij „Instaluj”.' 'Bialy')
    Write-Wiersz 2 ($yPodpowiedz + 1) (Format-Barwa 'Esc anuluje oczekiwanie.' 'Przygas')

    # licznik w zasięgu skryptu: inkrementacja wewnątrz scriptblocka utworzyłaby
    # kopię lokalną i animacja stałaby w miejscu
    $script:KlatkaOczekiwania = 0
    $biblioteka = Wait-Appmanifest -SteamPath $Info.SteamPath -AppId $AppId -Tick {
        $kroki[2].Detal = "potwierdź instalację w oknie Steam  $(Get-Spinner $script:KlatkaOczekiwania)"
        Draw-Kroki -Kroki $kroki -Y $y
        $script:KlatkaOczekiwania++
    }

    Clear-Wiersz $yPodpowiedz
    Clear-Wiersz ($yPodpowiedz + 1)

    if ($biblioteka -eq 'anulowano') { & $ustaw 2 'blad' 'anulowano'; return $null }
    if (-not $biblioteka) {
        & $ustaw 2 'blad' 'przekroczono czas oczekiwania'
        Show-Komunikat -Wiersze @('Wpis instalacji się nie pojawił.', '',
                                  'Upewnij się, że instalacja została potwierdzona w oknie Steam,',
                                  'a następnie uruchom program ponownie.') -Tytul 'Przerwano' -Barwa 'Zolty'
        return $null
    }
    & $ustaw 2 'gotowe' $biblioteka

    $acf = [System.IO.Path]::Combine($biblioteka, 'steamapps', "appmanifest_$AppId.acf")

    # 4
    if ($trybOszczedny) {
        & $ustaw 3 'trwa' 'wstrzymywanie pobierania bazowego'

        if (-not (Stop-Steam -SteamPath $Info.SteamPath)) {
            & $ustaw 3 'blad' 'klient nadal działa'
            Show-Komunikat -Wiersze @('Nie udało się zamknąć klienta Steam.',
                                      'Zamknij go ręcznie i uruchom instalację ponownie.') -Tytul 'Przerwano' -Barwa 'Czerwony'
            return $null
        }

        $zwolnione = Remove-CzesciowePobieranie -Biblioteka $biblioteka -AppId $AppId

        # katalog docelowy musi istnieć, aby podmiana miała gdzie trafić
        $installdir = Get-WpisAcf -Sciezka $acf -Klucz 'installdir'
        if (-not $installdir) {
            $installdir = $InstallDirZapasowy
            Set-WpisAcf -Sciezka $acf -Klucz 'installdir' -Wartosc $installdir | Out-Null
        }
        $katalog = [System.IO.Path]::Combine($biblioteka, 'steamapps', 'common', $installdir)

        # Po odinstalowaniu gry Steam potrafi zostawić katalog z plikami, mimo że
        # usunie wpis appmanifest. Takie pliki i tak zostaną zastąpione.
        $osierocone = 0L
        if ([System.IO.Directory]::Exists($katalog)) { $osierocone = Get-RozmiarKatalogu -Sciezka $katalog }
        New-Item -ItemType Directory -Force -Path $katalog | Out-Null

        $detal = "pominięto, zwolniono $(Format-Bajty $zwolnione)"
        if ($osierocone -gt 0) { $detal += ", zastanych plików $(Format-Bajty $osierocone)" }
        & $ustaw 3 'pominiete' $detal
        Zapisz-Dziennik "Tryb oszczędny: wpis w $biblioteka, installdir=$installdir, zwolniono $zwolnione B, zastane $osierocone B"
    } else {
        & $ustaw 3 'trwa' 'pobieranie prowadzi klient Steam'
        Start-Sleep -Milliseconds 800

        if (-not (Show-PostepSteam -Acf $acf)) {
            Show-Komunikat -Wiersze @('Oczekiwanie przerwane.', '',
                                      'Gdy Steam zakończy pobieranie, uruchom instalację ponownie.') `
                           -Tytul 'Przerwano' -Barwa 'Zolty'
            return $null
        }

        Clear-Ekran
        Draw-Naglowek -Podtytul 'Przygotowanie gry' -Wersja $Wersja
        & $ustaw 3 'gotowe' 'wersja bazowa zainstalowana'
        Zapisz-Dziennik 'Tryb pełny: klient Steam ukończył instalację wersji bazowej'
    }

    Start-Sleep -Milliseconds 600
    return (Get-InfoGry -AppId $AppId)
}

# --- Główny przebieg instalacji --------------------------------------------

function Invoke-PelnaInstalacja {
    param([Parameter(Mandatory)][object]$Info)

    if (-not $Info.Zainstalowana) {
        $Info = Invoke-PrzygotowanieGry -Info $Info
        if (-not $Info -or -not $Info.Zainstalowana) { return }
    }

    $kompilacja = Select-Kompilacja
    if (-not $kompilacja) { return }

    if ($Info.WolneGB -lt 14) {
        $ok = Confirm-Tui -Pytanie 'Kontynuować mimo małej ilości wolnego miejsca?' `
                          -Opis "Dostępne $($Info.WolneGB) GB, zalecane 14 GB (pobranie plus kopia zapasowa)" -DomyslnieNie
        if (-not $ok) { return }
    }

    Clear-Ekran
    Draw-Naglowek -Podtytul 'Przygotowanie narzędzi' -Wersja $Wersja
    $kroki = New-ListaKrokow @('DepotDownloader')
    Draw-Kroki -Kroki $kroki -Y 6
    $kroki[0].Stan = 'trwa'; Draw-Kroki -Kroki $kroki -Y 6

    try {
        $exe = Get-DepotDownloader -KatalogNarzedzi $Katalogi.Narzedzia -Postep {
            param($t) $kroki[0].Detal = $t; Draw-Kroki -Kroki $kroki -Y 6
        }
        $kroki[0].Stan = 'gotowe'; Draw-Kroki -Kroki $kroki -Y 6
    } catch {
        $kroki[0].Stan = 'blad'; $kroki[0].Detal = $_.Exception.Message
        Draw-Kroki -Kroki $kroki -Y 6
        Show-Komunikat -Wiersze @('Nie udało się przygotować DepotDownloadera:', $_.Exception.Message) `
                       -Tytul 'Błąd' -Barwa 'Czerwony'
        return
    }

    $sesja = Invoke-Logowanie -Exe $exe -ManifestId $kompilacja.Manifest
    if (-not $sesja) { return }

    $katalogRoboczy = [System.IO.Path]::Combine($Info.Biblioteka, 'steamapps', '_pjpt_pobieranie')

    if ($sesja.Qr) {
        # Sesja QR nie zapisuje tokenu pod znaną nazwą konta, więc kolejne
        # uruchomienie ponownie wymagałoby skanowania. Pobieranie odbywa się
        # w trybie tekstowym, w tym samym procesie logowania.
        Clear-Ekran
        Restore-Console
        Write-Host ''
        Write-Host '  Pobieranie w trybie tekstowym (logowanie kodem QR).' -ForegroundColor Cyan
        Write-Host ''
        # ta sama zasada co przy logowaniu: kod QR musi trafić na konsolę,
        # a nie do przechwyconego strumienia sukcesu
        $argQr = @('-app', $AppId, '-depot', $DepotId, '-manifest', $kompilacja.Manifest,
                   '-dir', "`"$katalogRoboczy`"", '-qr', '-loginid', $script:LoginId)
        $procQr = Start-Process -FilePath $exe -ArgumentList $argQr `
                                -WorkingDirectory ([System.IO.Path]::GetDirectoryName($exe)) `
                                -NoNewWindow -Wait -PassThru
        $kod = $procQr.ExitCode
        [Console]::CursorVisible = $false
        if ($kod -ne 0) {
            Show-Komunikat -Wiersze @("DepotDownloader zakończył pracę z kodem $kod.") -Tytul 'Błąd' -Barwa 'Czerwony'
            return
        }
    } else {
        $ok = Show-Pobieranie -Exe $exe -Kompilacja $kompilacja -KatalogDocelowy $katalogRoboczy -Uzytkownik $sesja.Uzytkownik
        if (-not $ok) { return }
    }

    if (-not (Get-ExeGry -KatalogGry $katalogRoboczy)) {
        Show-Komunikat -Wiersze @('W pobranych plikach brakuje pliku wykonywalnego gry.',
                                  'Pobieranie jest niekompletne - uruchom je ponownie.') -Tytul 'Błąd' -Barwa 'Czerwony'
        return
    }

    $wynik = Install-Kompilacja -Info $Info -KatalogZrodlowy $katalogRoboczy -Kompilacja $kompilacja
    if ($wynik) { Show-Podsumowanie -Wynik $wynik -Kompilacja $kompilacja }
}

# --- Menu główne -----------------------------------------------------------

function Start-Aplikacja {
    Initialize-Tui
    Initialize-Dziennik

    try {
        $info = Show-Diagnostyka

        while ($true) {
            if ($info.Zainstalowana -and $info.PelnaInstalacja) {
                $podtytul = "$($info.InstallDir)  ·  build $($info.BuildIdLokalny)  ·  $($info.WolneGB) GB wolne"
                $opisInstalacji = 'Pobranie wybranej kompilacji i podmiana plików gry'
            } elseif ($info.Wpis) {
                $podtytul = "$($info.InstallDir)  ·  instalacja niekompletna  ·  $($info.WolneGB) GB wolne"
                $opisInstalacji = 'Dokończenie instalacji od razu w wybranej starszej wersji'
            } else {
                $podtytul = "Gra nie jest zainstalowana  ·  $($info.WolneGB) GB wolne"
                $opisInstalacji = 'Program doda grę do konta i pobierze wybraną kompilację'
            }

            $pozycje = @(
                [pscustomobject]@{ Etykieta = 'Zainstaluj starszą wersję';        Opis = $opisInstalacji }
                [pscustomobject]@{ Etykieta = 'Napraw przycisk „Graj"';           Opis = 'Zapobiega pobieraniu aktualizacji przy uruchamianiu ze Steam' }
                [pscustomobject]@{ Etykieta = 'Przywróć wersję z kopii zapasowej';Opis = 'Powrót do stanu sprzed instalacji starszej wersji' }
                [pscustomobject]@{ Etykieta = 'Kopie zapasowe';                   Opis = 'Przegląd i usuwanie kopii w celu zwolnienia miejsca' }
                [pscustomobject]@{ Etykieta = 'Diagnostyka';                      Opis = 'Ponowne sprawdzenie środowiska' }
                [pscustomobject]@{ Etykieta = 'Zakończ';                          Opis = '' }
            )

            $wybor = Show-Menu -Pozycje $pozycje -Tytul 'Menu główne' -Podtytul $podtytul -Wersja $Wersja -BezEscape

            switch ($wybor) {
                0 { Invoke-PelnaInstalacja      -Info $info }
                1 { if ($info.Acf) { Invoke-NaprawaPrzycisku -Info $info } else { Show-Komunikat -Wiersze @('Brak pliku appmanifest.') -Tytul 'Błąd' -Barwa 'Czerwony' } }
                2 { if ($info.Acf) { Invoke-Przywracanie     -Info $info } else { Show-Komunikat -Wiersze @('Brak pliku appmanifest.') -Tytul 'Błąd' -Barwa 'Czerwony' } }
                3 { if ($info.Acf) { Invoke-ZarzadzanieKopiami -Info $info } else { Show-Komunikat -Wiersze @('Brak pliku appmanifest.') -Tytul 'Błąd' -Barwa 'Czerwony' } }
                4 { $info = Show-Diagnostyka }
                5 { return }
            }

            if ($wybor -in 0, 1, 2) { $info = Get-InfoGry -AppId $AppId }
        }
    } finally {
        Clear-Ekran
        Restore-Console
        Write-Host ''
        Write-Host '  Do zobaczenia w fabryce.' -ForegroundColor DarkGray
        if ($script:PlikDziennika) {
            Write-Host "  Dziennik sesji: $script:PlikDziennika" -ForegroundColor DarkGray
        }
        Write-Host ''
    }
}

Start-Aplikacja
