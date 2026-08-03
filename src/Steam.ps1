# =============================================================================
#  Steam.ps1 - wykrywanie instalacji, obsługa appmanifest, podmiana katalogu
# =============================================================================

function Get-SteamPath {
    foreach ($klucz in @('HKCU:\Software\Valve\Steam', 'HKLM:\SOFTWARE\WOW6432Node\Valve\Steam', 'HKLM:\SOFTWARE\Valve\Steam')) {
        try {
            $wpis = Get-ItemProperty -Path $klucz -ErrorAction Stop
            foreach ($nazwa in @('SteamPath', 'InstallPath')) {
                $sciezka = $wpis.$nazwa
                if ($sciezka -and [System.IO.Directory]::Exists($sciezka)) {
                    return [System.IO.Path]::GetFullPath($sciezka)
                }
            }
        } catch { }
    }
    return $null
}

function Get-BibliotekiSteam {
    param([Parameter(Mandatory)][string]$SteamPath)

    $lista = New-Object System.Collections.Generic.List[string]
    $lista.Add($SteamPath)

    $vdf = [System.IO.Path]::Combine($SteamPath, 'steamapps', 'libraryfolders.vdf')
    if ([System.IO.File]::Exists($vdf)) {
        foreach ($linia in [System.IO.File]::ReadAllLines($vdf)) {
            if ($linia -match '"path"\s+"(.+?)"') {
                $lista.Add(($Matches[1] -replace '\\\\', '\'))
            }
        }
    }
    return $lista
}

function Get-BibliotekaGry {
    <#
        Zwraca ścieżkę biblioteki zawierającej appmanifest wskazanej gry.
        Odporne na biblioteki na odłączonych dyskach (Join-Path rzuca wtedy wyjątkiem).
    #>
    param([Parameter(Mandatory)][string]$SteamPath, [Parameter(Mandatory)][int]$AppId)

    foreach ($biblioteka in (Get-BibliotekiSteam -SteamPath $SteamPath)) {
        try {
            $acf = [System.IO.Path]::Combine($biblioteka, 'steamapps', "appmanifest_$AppId.acf")
            if ([System.IO.File]::Exists($acf)) {
                return [System.IO.Path]::GetFullPath($biblioteka)
            }
        } catch { }
    }
    return $null
}

function Get-WpisAcf {
    param([Parameter(Mandatory)][string]$Sciezka, [Parameter(Mandatory)][string]$Klucz)
    try {
        foreach ($linia in [System.IO.File]::ReadAllLines($Sciezka)) {
            if ($linia -match ('"{0}"\s+"(.*?)"' -f [regex]::Escape($Klucz))) { return $Matches[1] }
        }
    } catch {
        # plik zajęty przez klienta Steam albo uszkodzony - brak wartości jest
        # informacją samą w sobie, wywołujący ma przewidziane wartości zastępcze
        return $null
    }
    return $null
}

function Test-TrescAcf {
    <# Minimalna kontrola sensowności: bez niej można zapisać uszkodzony wpis. #>
    param([string[]]$Wiersze)
    if (-not $Wiersze -or $Wiersze.Count -lt 5) { return $false }
    $polaczone = $Wiersze -join "`n"
    if ($polaczone -notmatch '"AppState"') { return $false }
    if ($polaczone -notmatch '"appid"')    { return $false }
    # liczba nawiasów musi się zgadzać, inaczej struktura jest ucięta
    $otwarte  = ([regex]::Matches($polaczone, '\{')).Count
    $zamkniete = ([regex]::Matches($polaczone, '\}')).Count
    return ($otwarte -gt 0 -and $otwarte -eq $zamkniete)
}

function Backup-Acf {
    <#
        Jednorazowa kopia oryginalnego wpisu, zakładana przed pierwszą modyfikacją.
        Pozwala odtworzyć stan sprzed działania programu nawet wtedy, gdy katalog
        gry został już podmieniony.
    #>
    param([Parameter(Mandatory)][string]$Sciezka)
    try {
        $kopia = "$Sciezka.oryginal"
        if (-not [System.IO.File]::Exists($kopia) -and [System.IO.File]::Exists($Sciezka)) {
            Copy-Item -LiteralPath $Sciezka -Destination $kopia -Force -ErrorAction Stop
        }
        return $kopia
    } catch {
        return $null
    }
}

function Set-WpisAcf {
    <#
        Podmiana pojedynczej wartości we wpisie appmanifest.

        Zapis jest dwuetapowy: najpierw powstaje plik tymczasowy, który dopiero po
        pełnym zapisaniu zastępuje oryginał. Bezpośredni zapis oznaczałby, że awaria
        zasilania albo błąd w połowie operacji zostawia klientowi Steam uszkodzony
        wpis, a wraz z nim niedziałającą pozycję w bibliotece.
    #>
    param(
        [Parameter(Mandatory)][string]$Sciezka,
        [Parameter(Mandatory)][string]$Klucz,
        [Parameter(Mandatory)][string]$Wartosc
    )

    if (-not [System.IO.File]::Exists($Sciezka)) { return $false }

    Backup-Acf -Sciezka $Sciezka | Out-Null
    Unlock-Acf -Sciezka $Sciezka

    try {
        $zrodlo = [System.IO.File]::ReadAllLines($Sciezka)
    } catch {
        return $false
    }
    if (-not (Test-TrescAcf -Wiersze $zrodlo)) { return $false }

    $wzorzec = '("{0}"\s+")(.*?)(")' -f [regex]::Escape($Klucz)
    $znaleziono = $false
    $wynik = New-Object System.Collections.Generic.List[string]

    foreach ($linia in $zrodlo) {
        if ($linia -match $wzorzec) {
            $znaleziono = $true
            $wynik.Add(($linia -replace $wzorzec, ('${1}' + $Wartosc + '${3}')))
        } else {
            $wynik.Add($linia)
        }
    }

    if (-not $znaleziono) { return $false }
    if (-not (Test-TrescAcf -Wiersze $wynik)) { return $false }

    $tymczasowy = "$Sciezka.nowy"
    try {
        [System.IO.File]::WriteAllLines($tymczasowy, $wynik)

        # kontrola po zapisie: dopiero zweryfikowany plik zastępuje oryginał
        if (-not (Test-TrescAcf -Wiersze ([System.IO.File]::ReadAllLines($tymczasowy)))) {
            throw 'zapisany plik nie przeszedł kontroli'
        }

        [System.IO.File]::Copy($tymczasowy, $Sciezka, $true)
        return $true
    } catch {
        return $false
    } finally {
        Remove-Item -LiteralPath $tymczasowy -Force -ErrorAction SilentlyContinue
    }
}

function Unlock-Acf {
    param([Parameter(Mandatory)][string]$Sciezka)
    try {
        $plik = Get-Item -LiteralPath $Sciezka -Force
        if ($plik.IsReadOnly) { $plik.IsReadOnly = $false }
    } catch { }
}

function Lock-Acf {
    param([Parameter(Mandatory)][string]$Sciezka, [bool]$Zablokuj = $true)
    try { (Get-Item -LiteralPath $Sciezka -Force).IsReadOnly = $Zablokuj } catch { }
}

function Get-InfoDepotu {
    <#
        Zwraca dane bieżącej publicznej wersji depotu: identyfikator manifestu,
        rozmiar po rozpakowaniu oraz rozmiar pobierania. Klient Steam porównuje
        z nimi zawartość wpisu appmanifest.
    #>
    param([Parameter(Mandatory)][int]$AppId, [Parameter(Mandatory)][int]$DepotId, [int]$TimeoutSek = 15)
    try {
        $odp = Invoke-RestMethod -Uri "https://api.steamcmd.net/v1/info/$AppId" `
                                 -TimeoutSec $TimeoutSek -UseBasicParsing -ErrorAction Stop
        $pub = $odp.data.$AppId.depots.$DepotId.manifests.public
        if (-not $pub -or -not $pub.gid) { return $null }
        return [pscustomobject]@{
            Gid       = [string]$pub.gid
            Rozmiar   = [long]$pub.size
            Pobieranie= [long]$pub.download
        }
    } catch {
        return $null
    }
}

function Set-StanZainstalowany {
    <#
        Zapisuje we wpisie appmanifest spójny stan „gra zainstalowana i aktualna”.

        Samo ustawienie buildid nie wystarcza. Klient Steam sprawdza przede wszystkim
        listę InstalledDepots: dopóki jest pusta, uznaje, że żaden depot nie jest
        zainstalowany, dopisuje do StateFlags bit wymaganej aktualizacji i żąda
        pobrania całości niezależnie od numeru kompilacji. Tak samo traktuje zerowe
        SizeOnDisk oraz BytesDownloaded mniejsze od BytesToDownload.

        Wszystkie pola zapisywane są w jednym przebiegu, a plik podmieniany atomowo -
        wpis w żadnym momencie nie pozostaje w stanie częściowo zmienionym.
    #>
    param(
        [Parameter(Mandatory)][string]$Acf,
        [Parameter(Mandatory)][int]$DepotId,
        [string]$BuildId,
        [string]$ManifestGid,
        [long]$RozmiarNaDysku = 0,
        [long]$RozmiarPobierania = 0
    )

    if (-not [System.IO.File]::Exists($Acf)) { return $null }

    Backup-Acf -Sciezka $Acf | Out-Null
    Unlock-Acf -Sciezka $Acf

    try { $zrodlo = [System.IO.File]::ReadAllLines($Acf) } catch { return $null }
    if (-not (Test-TrescAcf -Wiersze $zrodlo)) { return $null }

    if ($RozmiarPobierania -le 0) { $RozmiarPobierania = $RozmiarNaDysku }
    $teraz = [int][double]::Parse((Get-Date -UFormat %s))

    $pola = [ordered]@{
        'StateFlags'          = '4'
        'AutoUpdateBehavior'  = '1'
        'ScheduledAutoUpdate' = '0'
        'UpdateResult'        = '0'
        'DownloadType'        = '1'
        'LastUpdated'         = "$teraz"
    }
    if ($BuildId) {
        $pola['buildid']       = $BuildId
        $pola['TargetBuildID'] = $BuildId
    }
    if ($RozmiarNaDysku -gt 0) {
        $pola['SizeOnDisk']      = "$RozmiarNaDysku"
        $pola['BytesToStage']    = "$RozmiarNaDysku"
        $pola['BytesStaged']     = "$RozmiarNaDysku"
        $pola['BytesToDownload'] = "$RozmiarPobierania"
        $pola['BytesDownloaded'] = "$RozmiarPobierania"
    }

    $wynik = New-Object System.Collections.Generic.List[string]
    $zmienione = New-Object System.Collections.Generic.List[string]
    $blokZapisany = $false

    $i = 0
    while ($i -lt $zrodlo.Count) {
        $linia = $zrodlo[$i]

        # Blok InstalledDepots wymaga podmiany w całości, nie pojedynczej wartości.
        if ($ManifestGid -and $linia -match '^\s*"InstalledDepots"\s*$') {
            $wynik.Add($linia)
            $i++

            if ($i -lt $zrodlo.Count -and $zrodlo[$i] -match '^\s*\{\s*$') {
                $glebokosc = 1
                $i++
                while ($i -lt $zrodlo.Count -and $glebokosc -gt 0) {
                    $glebokosc += ([regex]::Matches($zrodlo[$i], '\{')).Count
                    $glebokosc -= ([regex]::Matches($zrodlo[$i], '\}')).Count
                    $i++
                }
            }

            $rozmiarWpisu = $RozmiarNaDysku
            if ($rozmiarWpisu -le 0) { $rozmiarWpisu = 0 }
            $wynik.Add("`t{")
            $wynik.Add("`t`t`"$DepotId`"")
            $wynik.Add("`t`t{")
            $wynik.Add("`t`t`t`"manifest`"`t`t`"$ManifestGid`"")
            $wynik.Add("`t`t`t`"size`"`t`t`"$rozmiarWpisu`"")
            $wynik.Add("`t`t}")
            $wynik.Add("`t}")
            $blokZapisany = $true
            continue
        }

        $podmieniona = $false
        foreach ($klucz in $pola.Keys) {
            $wzorzec = '("{0}"\s+")(.*?)(")' -f [regex]::Escape($klucz)
            if ($linia -match $wzorzec) {
                $wynik.Add(($linia -replace $wzorzec, ('${1}' + $pola[$klucz] + '${3}')))
                if (-not $zmienione.Contains($klucz)) { $zmienione.Add($klucz) }
                $podmieniona = $true
                break
            }
        }
        if (-not $podmieniona) { $wynik.Add($linia) }
        $i++
    }

    if (-not (Test-TrescAcf -Wiersze $wynik)) { return $null }

    $tymczasowy = "$Acf.nowy"
    try {
        [System.IO.File]::WriteAllLines($tymczasowy, $wynik)
        if (-not (Test-TrescAcf -Wiersze ([System.IO.File]::ReadAllLines($tymczasowy)))) {
            throw 'zapisany plik nie przeszedł kontroli'
        }
        [System.IO.File]::Copy($tymczasowy, $Acf, $true)
    } catch {
        return $null
    } finally {
        Remove-Item -LiteralPath $tymczasowy -Force -ErrorAction SilentlyContinue
    }

    return [pscustomobject]@{
        Pola          = $zmienione.ToArray()
        DepotZapisany = $blokZapisany
        Manifest      = $ManifestGid
        Rozmiar       = $RozmiarNaDysku
    }
}

function Get-AktualnyBuildId {
    <#
        Odpytuje publiczne API steamcmd o identyfikator kompilacji gałęzi "public".
        Zwraca $null przy braku łączności - wywołujący decyduje, co dalej.
    #>
    param([Parameter(Mandatory)][int]$AppId, [int]$TimeoutSek = 15)
    try {
        $odp = Invoke-RestMethod -Uri "https://api.steamcmd.net/v1/info/$AppId" `
                                 -TimeoutSec $TimeoutSek -UseBasicParsing -ErrorAction Stop
        return [string]$odp.data.$AppId.depots.branches.public.buildid
    } catch {
        return $null
    }
}

function Get-InfoGry {
    <#
        Kompletny obraz stanu instalacji - jedno wywołanie na potrzeby ekranu diagnostyki.
    #>
    param([Parameter(Mandatory)][int]$AppId)

    $info = [pscustomobject]@{
        SteamPath      = $null
        Biblioteka     = $null
        Acf            = $null
        InstallDir     = $null
        KatalogGry     = $null
        BuildIdLokalny = $null
        BuildIdZdalny  = $null
        StateFlags     = $null
        Zablokowany    = $false
        Exe            = $null
        WolneGB        = 0
        Zainstalowana  = $false
        PelnaInstalacja= $false
        Wpis           = $false
    }

    $info.SteamPath = Get-SteamPath
    if (-not $info.SteamPath) { return $info }

    $info.Biblioteka = Get-BibliotekaGry -SteamPath $info.SteamPath -AppId $AppId
    if (-not $info.Biblioteka) { return $info }

    $info.Wpis           = $true
    $info.Acf            = [System.IO.Path]::Combine($info.Biblioteka, 'steamapps', "appmanifest_$AppId.acf")
    $info.InstallDir     = Get-WpisAcf -Sciezka $info.Acf -Klucz 'installdir'
    $info.BuildIdLokalny = Get-WpisAcf -Sciezka $info.Acf -Klucz 'buildid'
    $info.StateFlags     = Get-WpisAcf -Sciezka $info.Acf -Klucz 'StateFlags'
    $info.PelnaInstalacja= Test-PelnaInstalacja -StateFlags $info.StateFlags

    try { $info.Zablokowany = (Get-Item -LiteralPath $info.Acf -Force).IsReadOnly } catch { }

    if ($info.InstallDir) {
        $info.KatalogGry = [System.IO.Path]::Combine($info.Biblioteka, 'steamapps', 'common', $info.InstallDir)
        $info.Zainstalowana = [System.IO.Directory]::Exists($info.KatalogGry)
        if ($info.Zainstalowana) {
            $exe = Get-ExeGry -KatalogGry $info.KatalogGry
            if ($exe) { $info.Exe = $exe.FullName }
        }
    }

    try {
        $dysk = New-Object System.IO.DriveInfo ([System.IO.Path]::GetPathRoot($info.Biblioteka))
        $info.WolneGB = [Math]::Round($dysk.AvailableFreeSpace / 1GB, 1)
    } catch { }

    return $info
}

function Test-PelnaInstalacja {
    <#
        StateFlags to pole bitowe. Bit o wartości 4 (StateFullyInstalled) oznacza
        kompletną instalację; wpis utworzony przez zakolejkowanie pobierania go nie ma.
    #>
    param([string]$StateFlags)
    $wartosc = 0
    if ([int]::TryParse($StateFlags, [ref]$wartosc)) { return (($wartosc -band 4) -eq 4) }
    return $false
}

function Get-PostepInstalacjiSteam {
    <#
        Klient Steam zapisuje w appmanifest bieżący stan pobierania, dzięki czemu
        można pokazać jego postęp bez odpytywania samego klienta.
    #>
    param([Parameter(Mandatory)][string]$Acf)

    $pobrano = Get-WpisAcf -Sciezka $Acf -Klucz 'BytesDownloaded'
    $calosc  = Get-WpisAcf -Sciezka $Acf -Klucz 'BytesToDownload'
    $flagi   = Get-WpisAcf -Sciezka $Acf -Klucz 'StateFlags'

    $b = 0L; $c = 0L
    [void][long]::TryParse($pobrano, [ref]$b)
    [void][long]::TryParse($calosc,  [ref]$c)

    $procent = 0.0
    if ($c -gt 0) { $procent = [Math]::Min(100.0, $b * 100.0 / $c) }

    return [pscustomobject]@{
        Bajty      = $b
        Calosc     = $c
        Procent    = $procent
        StateFlags = $flagi
        Gotowe     = (Test-PelnaInstalacja -StateFlags $flagi)
    }
}

function Start-SteamKlient {
    param([Parameter(Mandatory)][string]$SteamPath, [int]$LimitSek = 90)

    if (Get-Process -Name 'steam' -ErrorAction SilentlyContinue) { return $true }

    $exe = [System.IO.Path]::Combine($SteamPath, 'steam.exe')
    if (-not [System.IO.File]::Exists($exe)) { return $false }

    try { Start-Process -FilePath $exe -ErrorAction Stop } catch { return $false }

    $koniec = (Get-Date).AddSeconds($LimitSek)
    while ((Get-Date) -lt $koniec) {
        if (Get-Process -Name 'steam' -ErrorAction SilentlyContinue) {
            Start-Sleep -Seconds 4   # klient potrzebuje chwili na obsługę protokołu steam://
            return $true
        }
        Start-Sleep -Milliseconds 500
    }
    return $false
}

function Request-InstalacjaGry {
    <#
        Otwiera w kliencie Steam okno instalacji gry. Dla gier darmowych obejmuje
        to również dodanie pozycji do biblioteki konta. Potwierdzenie należy
        do użytkownika - nie jest i nie powinno być automatyzowane.
    #>
    param([Parameter(Mandatory)][int]$AppId)
    try {
        Start-Process "steam://install/$AppId" -ErrorAction Stop
        return $true
    } catch {
        return $false
    }
}

function Wait-Appmanifest {
    <#
        Czeka na pojawienie się wpisu instalacji. Steam tworzy go w chwili
        zakolejkowania pobierania, na długo przed jego zakończeniem.
        Zwraca ścieżkę biblioteki, $null przy przekroczeniu czasu
        albo 'anulowano', gdy użytkownik naciśnie Esc.
    #>
    param(
        [Parameter(Mandatory)][string]$SteamPath,
        [Parameter(Mandatory)][int]$AppId,
        [int]$LimitSek = 900,
        [scriptblock]$Tick
    )

    $koniec = (Get-Date).AddSeconds($LimitSek)
    while ((Get-Date) -lt $koniec) {
        $biblioteka = Get-BibliotekaGry -SteamPath $SteamPath -AppId $AppId
        if ($biblioteka) { return $biblioteka }

        if (Test-Escape) { return 'anulowano' }
        if ($Tick) { & $Tick }
        Start-Sleep -Milliseconds 200
    }
    return $null
}

function Remove-CzesciowePobieranie {
    <#
        Usuwa dane niedokończonego pobierania klienta Steam i zwraca liczbę
        zwolnionych bajtów.
    #>
    param([Parameter(Mandatory)][string]$Biblioteka, [Parameter(Mandatory)][int]$AppId)

    $zwolnione = 0L
    $sciezki = @(
        [System.IO.Path]::Combine($Biblioteka, 'steamapps', 'downloading', "$AppId"),
        [System.IO.Path]::Combine($Biblioteka, 'steamapps', 'temp', "$AppId")
    )
    foreach ($s in $sciezki) {
        if ([System.IO.Directory]::Exists($s)) {
            $zwolnione += Get-RozmiarKatalogu -Sciezka $s
            try { Remove-Item -LiteralPath $s -Recurse -Force } catch { }
        }
    }
    return $zwolnione
}

function Get-ExeGry {
    <#
        Ścieżka wskazująca nieistniejący dysk sprawia, że PowerShell rozwiązuje
        Get-ChildItem względem innego dostawcy, który nie zna parametru -File
        i zgłasza błąd wiązania. Stąd wcześniejsze sprawdzenie istnienia katalogu
        oraz osłona całości.
    #>
    param([Parameter(Mandatory)][string]$KatalogGry)

    $wykluczone = 'UnrealCEFSubProcess|CrashReportClient|EasyAntiCheat|UnityCrashHandler|vc_redist|DXSETUP|Uninstall'
    try {
        if (-not [System.IO.Directory]::Exists($KatalogGry)) { return $null }
        return Get-ChildItem -LiteralPath $KatalogGry -Filter '*.exe' -File -ErrorAction SilentlyContinue |
               Where-Object { $_.Name -notmatch $wykluczone } |
               Sort-Object Name |
               Select-Object -First 1
    } catch {
        return $null
    }
}

function Stop-Steam {
    <#
        Zamyka klienta Steam w sposób kontrolowany (-shutdown zapisuje konfigurację).
        Zwraca $true, jeśli po zakończeniu żaden proces Steam nie działa.
    #>
    param([Parameter(Mandatory)][string]$SteamPath, [int]$LimitSek = 40)

    if (-not (Get-Process -Name 'steam' -ErrorAction SilentlyContinue)) { return $true }

    $exe = [System.IO.Path]::Combine($SteamPath, 'steam.exe')
    if ([System.IO.File]::Exists($exe)) {
        try { Start-Process -FilePath $exe -ArgumentList '-shutdown' -ErrorAction Stop } catch { }
    }

    $koniec = (Get-Date).AddSeconds($LimitSek)
    while ((Get-Date) -lt $koniec) {
        if (-not (Get-Process -Name 'steam' -ErrorAction SilentlyContinue)) { return $true }
        Start-Sleep -Milliseconds 500
    }
    return (-not (Get-Process -Name 'steam' -ErrorAction SilentlyContinue))
}

function Get-KopieZapasowe {
    param([Parameter(Mandatory)][string]$Biblioteka, [Parameter(Mandatory)][string]$InstallDir)
    $common = [System.IO.Path]::Combine($Biblioteka, 'steamapps', 'common')
    if (-not [System.IO.Directory]::Exists($common)) { return @() }
    return @(Get-ChildItem -LiteralPath $common -Directory -ErrorAction SilentlyContinue |
             Where-Object { $_.Name -like "$InstallDir.backup_*" } |
             Sort-Object Name -Descending)
}

function New-SkrotPulpitu {
    param([Parameter(Mandatory)][string]$Cel, [Parameter(Mandatory)][string]$Nazwa)
    try {
        $sciezka = [System.IO.Path]::Combine([Environment]::GetFolderPath('Desktop'), "$Nazwa.lnk")
        $shell = New-Object -ComObject WScript.Shell
        $lnk = $shell.CreateShortcut($sciezka)
        $lnk.TargetPath       = $Cel
        $lnk.WorkingDirectory = [System.IO.Path]::GetDirectoryName($Cel)
        $lnk.Description      = 'PROJECT: PLAYTIME - starsza wersja'
        $lnk.Save()
        return $sciezka
    } catch {
        return $null
    }
}

function Invoke-NaprawaWpisu {
    <#
        Pełna naprawa wpisu: pobiera dane bieżącej wersji depotu, mierzy katalog gry
        i zapisuje spójny stan „zainstalowana i aktualna”. Zwraca opis wykonanych
        zmian albo $null, jeśli zapis się nie powiódł.
    #>
    param(
        [Parameter(Mandatory)][string]$Acf,
        [Parameter(Mandatory)][int]$AppId,
        [Parameter(Mandatory)][int]$DepotId,
        [string]$KatalogGry,
        [string]$BuildIdZapasowy,
        [scriptblock]$Postep
    )

    function Raport { param($t) if ($Postep) { & $Postep $t } }

    Raport 'odpytywanie api.steamcmd.net'
    $build = Get-AktualnyBuildId -AppId $AppId
    if (-not $build) { $build = $BuildIdZapasowy }

    $depot = Get-InfoDepotu -AppId $AppId -DepotId $DepotId

    # Rozmiar z API opisuje pełną, nieuszkodzoną zawartość depotu i jest
    # wiarygodniejszy niż pomiar katalogu, który może być w trakcie zmian.
    $rozmiar = 0L
    $pobieranie = 0L
    if ($depot) {
        $rozmiar    = $depot.Rozmiar
        $pobieranie = $depot.Pobieranie
    } elseif ($KatalogGry) {
        Raport 'brak łączności, pomiar katalogu'
        $rozmiar = Get-RozmiarKatalogu -Sciezka $KatalogGry
    }

    $gid = $null
    if ($depot) { $gid = $depot.Gid }

    Raport 'zapis wpisu'
    return Set-StanZainstalowany -Acf $Acf -DepotId $DepotId -BuildId $build `
                                 -ManifestGid $gid -RozmiarNaDysku $rozmiar -RozmiarPobierania $pobieranie
}

function Set-BlokadaAktualizacji {
    <#
        Sprawia, że klient Steam uznaje instalację za kompletną i aktualną,
        mimo że na dysku znajdują się pliki starszej kompilacji.

        Steam porównuje wyłącznie metadane z appmanifest z informacjami o grze
        pobranymi z serwera - zawartość katalogu nie jest weryfikowana, dopóki
        użytkownik nie uruchomi opcji "Sprawdź spójność plików gry". Ustawienie
        buildid na wartość bieżącej kompilacji publicznej oznacza, że przycisk
        "Graj" nie wywoła aktualizacji, tylko od razu uruchomi grę.
    #>
    param(
        [Parameter(Mandatory)][string]$Acf,
        [string]$BuildId,
        [bool]$TylkoDoOdczytu = $false
    )

    $zmiany = @{}

    Unlock-Acf -Sciezka $Acf

    if ($BuildId) {
        if (Set-WpisAcf -Sciezka $Acf -Klucz 'buildid' -Wartosc $BuildId) { $zmiany['buildid'] = $BuildId }
    }
    if (Set-WpisAcf -Sciezka $Acf -Klucz 'StateFlags' -Wartosc '4')         { $zmiany['StateFlags'] = '4' }
    if (Set-WpisAcf -Sciezka $Acf -Klucz 'TargetBuildID' -Wartosc '0')      { $zmiany['TargetBuildID'] = '0' }
    if (Set-WpisAcf -Sciezka $Acf -Klucz 'AutoUpdateBehavior' -Wartosc '1') { $zmiany['AutoUpdateBehavior'] = '1' }
    if (Set-WpisAcf -Sciezka $Acf -Klucz 'ScheduledAutoUpdate' -Wartosc '0'){ $zmiany['ScheduledAutoUpdate'] = '0' }

    if ($TylkoDoOdczytu) { Lock-Acf -Sciezka $Acf -Zablokuj $true }

    return $zmiany
}

function Reset-BlokadaAktualizacji {
    param([Parameter(Mandatory)][string]$Acf, [string]$BuildId)
    Unlock-Acf -Sciezka $Acf
    if ($BuildId) { Set-WpisAcf -Sciezka $Acf -Klucz 'buildid' -Wartosc $BuildId | Out-Null }
    Set-WpisAcf -Sciezka $Acf -Klucz 'StateFlags' -Wartosc '4'          | Out-Null
    Set-WpisAcf -Sciezka $Acf -Klucz 'AutoUpdateBehavior' -Wartosc '0'  | Out-Null
}
