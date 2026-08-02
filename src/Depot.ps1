# =============================================================================
#  Depot.ps1 - pobieranie DepotDownloadera, logowanie i pobieranie zawartości
# =============================================================================

# Steam zrywa połączenie, gdy dwie sesje tego samego konta zgłoszą identyczny
# LoginID. Bez jawnej wartości DepotDownloader kolidowałby z działającym
# klientem Steam i wyrzucał użytkownika z aplikacji w trakcie pobierania.
$script:LoginId = 1961460

function Get-ZapamietaneKonto {
    <# Nazwa konta użyta przy ostatnim udanym logowaniu, jeśli została zapisana. #>
    param([Parameter(Mandatory)][string]$KatalogNarzedzi)
    $plik = [System.IO.Path]::Combine($KatalogNarzedzi, 'konto.txt')
    if (-not [System.IO.File]::Exists($plik)) { return $null }
    try {
        $wartosc = ([System.IO.File]::ReadAllText($plik)).Trim()
        if ($wartosc) { return $wartosc }
    } catch { }
    return $null
}

function Set-ZapamietaneKonto {
    param([Parameter(Mandatory)][string]$KatalogNarzedzi, [string]$Uzytkownik)
    try {
        $plik = [System.IO.Path]::Combine($KatalogNarzedzi, 'konto.txt')
        if ($Uzytkownik) { [System.IO.File]::WriteAllText($plik, $Uzytkownik) }
        elseif ([System.IO.File]::Exists($plik)) { Remove-Item -LiteralPath $plik -Force }
    } catch { }
}

function Test-ZapisanaSesja {
    <#
        DepotDownloader przechowuje token sesji w pliku account.config w swoim
        katalogu roboczym. Jego obecność razem z zapamiętaną nazwą konta oznacza,
        że kolejne logowanie przebiegnie bez pytania o hasło.
    #>
    param([Parameter(Mandatory)][string]$KatalogNarzedzi)
    return [System.IO.File]::Exists([System.IO.Path]::Combine($KatalogNarzedzi, 'account.config'))
}

function Get-DepotDownloader {
    <#
        Zwraca ścieżkę do DepotDownloader.exe, pobierając narzędzie z GitHuba,
        jeżeli nie ma go jeszcze lokalnie. $Postep to opcjonalny scriptblock
        przyjmujący komunikat tekstowy.
    #>
    param(
        [Parameter(Mandatory)][string]$KatalogNarzedzi,
        [scriptblock]$Postep
    )

    function Raport { param($t) if ($Postep) { & $Postep $t } }

    $exe = [System.IO.Path]::Combine($KatalogNarzedzi, 'DepotDownloader.exe')
    if ([System.IO.File]::Exists($exe)) {
        Raport 'narzędzie już dostępne'
        return $exe
    }

    if ($env:PROCESSOR_ARCHITECTURE -eq 'ARM64') { $arch = 'windows-arm64' } else { $arch = 'windows-x64' }
    Raport "pobieranie wydania ($arch)"

    [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
    $wydanie = Invoke-RestMethod -Uri 'https://api.github.com/repos/SteamRE/DepotDownloader/releases/latest' `
                                 -Headers @{ 'User-Agent' = 'ProjectPlaytime-Downgrader' } -UseBasicParsing

    $zasob = $wydanie.assets | Where-Object { $_.name -eq "DepotDownloader-$arch.zip" } | Select-Object -First 1
    if (-not $zasob) { throw "W wydaniu $($wydanie.tag_name) brak pakietu DepotDownloader-$arch.zip." }

    New-Item -ItemType Directory -Path $KatalogNarzedzi -Force | Out-Null
    $zip = [System.IO.Path]::Combine($KatalogNarzedzi, $zasob.name)

    Raport "$($wydanie.tag_name), $([Math]::Round($zasob.size / 1MB, 1)) MB"
    $poprzedni = $ProgressPreference
    $ProgressPreference = 'SilentlyContinue'
    try {
        Invoke-WebRequest -Uri $zasob.browser_download_url -OutFile $zip -UseBasicParsing
    } finally {
        $ProgressPreference = $poprzedni
    }

    Raport 'rozpakowywanie'
    Expand-Archive -LiteralPath $zip -DestinationPath $KatalogNarzedzi -Force
    Remove-Item -LiteralPath $zip -Force -ErrorAction SilentlyContinue

    if (-not [System.IO.File]::Exists($exe)) { throw 'Rozpakowanie DepotDownloadera nie powiodło się.' }
    return $exe
}

function Invoke-LogowanieSteam {
    <#
        Faza logowania. DepotDownloader czyta hasło i kod Steam Guard przez
        Console.ReadKey, co jest niemożliwe przy przekierowanym wejściu - dlatego
        ten etap wykonuje się w zwykłej konsoli, bez interfejsu graficznego.

        Pusta lista plików sprawia, że narzędzie tylko się uwierzytelnia,
        potwierdza dostęp do depotu i zapisuje token, nie pobierając niczego.
    #>
    param(
        [Parameter(Mandatory)][string]$Exe,
        [Parameter(Mandatory)][int]$AppId,
        [Parameter(Mandatory)][int]$DepotId,
        [Parameter(Mandatory)][string]$Manifest,
        [string]$Uzytkownik,
        [switch]$KodQr
    )

    $katalog = [System.IO.Path]::GetDirectoryName($Exe)
    # Wzorzec dopasowuje wyłącznie znak NUL, który nie występuje w nazwach plików,
    # więc lista jest w praktyce pusta i nic nie zostanie pobrane.
    $pustaLista = [System.IO.Path]::Combine($katalog, 'brak-plikow.txt')
    [System.IO.File]::WriteAllText($pustaLista, 'regex:^\x00$' + "`r`n")

    $tymczasowy = [System.IO.Path]::Combine($katalog, '_login')
    New-Item -ItemType Directory -Path $tymczasowy -Force | Out-Null

    $argumenty = @(
        '-app', $AppId, '-depot', $DepotId, '-manifest', $Manifest,
        '-dir', "`"$tymczasowy`"", '-filelist', "`"$pustaLista`"", '-loginid', $script:LoginId
    )
    if ($KodQr) {
        $argumenty += '-qr'
    } else {
        $argumenty += @('-username', $Uzytkownik, '-remember-password')
    }

    # Uruchomienie operatorem & kieruje wyjście narzędzia do strumienia sukcesu tej
    # funkcji, a ten jest przechwytywany przez przypisanie po stronie wywołującego.
    # PowerShell podstawia wtedy procesowi potok zamiast konsoli, więc monit o hasło
    # staje się niewidoczny, podczas gdy Console.ReadKey nadal czeka na klawisze -
    # program sprawia wrażenie zawieszonego. Start-Process -NoNewWindow przekazuje
    # uchwyty konsoli bezpośrednio i nie przechwytuje niczego.
    $proces = Start-Process -FilePath $Exe -ArgumentList $argumenty `
                            -WorkingDirectory $katalog -NoNewWindow -Wait -PassThru
    $kod = $proces.ExitCode

    Remove-Item -LiteralPath $tymczasowy -Recurse -Force -ErrorAction SilentlyContinue
    return [bool]($kod -eq 0)
}

function Start-PobieranieDepotu {
    <#
        Uruchamia DepotDownloader z przekierowanym wyjściem i zwraca obiekt stanu,
        który należy odpytywać funkcją Update-StanPobierania.
    #>
    param(
        [Parameter(Mandatory)][string]$Exe,
        [Parameter(Mandatory)][int]$AppId,
        [Parameter(Mandatory)][int]$DepotId,
        [Parameter(Mandatory)][string]$Manifest,
        [Parameter(Mandatory)][string]$Katalog,
        [string]$Uzytkownik,
        [int]$RownolegleFragmenty = 8
    )

    New-Item -ItemType Directory -Path $Katalog -Force | Out-Null

    $argumenty = @(
        '-app', $AppId, '-depot', $DepotId, '-manifest', $Manifest,
        '-dir', "`"$Katalog`"", '-max-downloads', $RownolegleFragmenty,
        '-loginid', $script:LoginId
    )
    if ($Uzytkownik) { $argumenty += @('-username', $Uzytkownik, '-remember-password') }

    $psi = New-Object System.Diagnostics.ProcessStartInfo
    $psi.FileName               = $Exe
    $psi.Arguments              = ($argumenty -join ' ')
    $psi.WorkingDirectory       = [System.IO.Path]::GetDirectoryName($Exe)
    $psi.UseShellExecute        = $false
    $psi.RedirectStandardOutput = $true
    $psi.RedirectStandardError  = $true
    $psi.CreateNoWindow         = $true
    $psi.StandardOutputEncoding = [System.Text.Encoding]::UTF8
    $psi.StandardErrorEncoding  = [System.Text.Encoding]::UTF8

    $kolejka = New-Object 'System.Collections.Concurrent.ConcurrentQueue[string]'

    $proces = New-Object System.Diagnostics.Process
    $proces.StartInfo = $psi
    $proces.EnableRaisingEvents = $true

    $subskrypcje = @()
    foreach ($zdarzenie in @('OutputDataReceived', 'ErrorDataReceived')) {
        $subskrypcje += Register-ObjectEvent -InputObject $proces -EventName $zdarzenie -MessageData $kolejka -Action {
            if ($null -ne $EventArgs.Data) { $Event.MessageData.Enqueue($EventArgs.Data) }
        }
    }

    [void]$proces.Start()
    $proces.BeginOutputReadLine()
    $proces.BeginErrorReadLine()

    return [pscustomobject]@{
        Proces       = $proces
        Kolejka      = $kolejka
        Subskrypcje  = $subskrypcje
        Katalog      = $Katalog
        Procent      = 0.0
        PlikBiezacy  = ''
        Dziennik     = New-Object System.Collections.Generic.List[string]
        Bajty        = 0L
        BajtyPoprz   = 0L
        Predkosc     = 0.0
        Start        = Get-Date
        OstatniPomiar= [datetime]::MinValue
        Zakonczone   = $false
        KodWyjscia   = $null
        Blad         = $null
    }
}

function Update-StanPobierania {
    <#
        Pobiera nowe wiersze z kolejki, aktualizuje procent, prędkość i dziennik.
        Prędkość liczona jest z rzeczywistego przyrostu danych na dysku - jest to
        jedyny wiarygodny pomiar, bo DepotDownloader nie raportuje przepustowości.
    #>
    param([Parameter(Mandatory)][object]$Stan, [int]$OkresPomiaruSek = 2)

    $linia = $null
    while ($Stan.Kolejka.TryDequeue([ref]$linia)) {
        if ([string]::IsNullOrWhiteSpace($linia)) { continue }

        if ($linia -match '^\s*(\d+[\.,]\d+)%\s+(.+)$') {
            $Stan.Procent     = [double](($Matches[1]) -replace ',', '.')
            $Stan.PlikBiezacy = $Matches[2].Trim()
            $Stan.Dziennik.Add($Stan.PlikBiezacy)
        } else {
            $Stan.Dziennik.Add($linia.Trim())
            if ($linia -match 'password|Steam Guard|two-factor|Enter the') {
                $Stan.Blad = 'Narzędzie oczekuje na dane logowania - sesja wygasła.'
            }
        }

        while ($Stan.Dziennik.Count -gt 200) { $Stan.Dziennik.RemoveAt(0) }
    }

    $teraz = Get-Date
    if (($teraz - $Stan.OstatniPomiar).TotalSeconds -ge $OkresPomiaruSek) {
        $bajty = Get-RozmiarKatalogu -Sciezka $Stan.Katalog
        if ($Stan.OstatniPomiar -ne [datetime]::MinValue) {
            $delta = ($teraz - $Stan.OstatniPomiar).TotalSeconds
            if ($delta -gt 0) {
                $chwilowa = ($bajty - $Stan.BajtyPoprz) / $delta
                # wygładzanie wykładnicze - surowy pomiar skacze zbyt mocno
                if ($Stan.Predkosc -le 0) { $Stan.Predkosc = $chwilowa }
                else { $Stan.Predkosc = ($Stan.Predkosc * 0.6) + ($chwilowa * 0.4) }
            }
        }
        $Stan.BajtyPoprz    = $bajty
        $Stan.Bajty         = $bajty
        $Stan.OstatniPomiar = $teraz
    }

    if ($Stan.Proces.HasExited -and $Stan.Kolejka.Count -eq 0) {
        $Stan.Zakonczone = $true
        $Stan.KodWyjscia = $Stan.Proces.ExitCode
    }

    return $Stan
}

function Stop-PobieranieDepotu {
    param([Parameter(Mandatory)][object]$Stan)
    try {
        if (-not $Stan.Proces.HasExited) {
            $Stan.Proces.Kill()
            $Stan.Proces.WaitForExit(5000) | Out-Null
        }
    } catch { }
    foreach ($s in $Stan.Subskrypcje) {
        Unregister-Event -SubscriptionId $s.Id -ErrorAction SilentlyContinue
        Remove-Job -Id $s.Id -Force -ErrorAction SilentlyContinue
    }
    try { $Stan.Proces.Dispose() } catch { }
}

function Get-RozmiarKatalogu {
    param([Parameter(Mandatory)][string]$Sciezka)
    try {
        $suma = 0L
        foreach ($plik in [System.IO.Directory]::EnumerateFiles($Sciezka, '*', [System.IO.SearchOption]::AllDirectories)) {
            try { $suma += (New-Object System.IO.FileInfo $plik).Length } catch { }
        }
        return $suma
    } catch {
        return 0L
    }
}

function Format-Bajty {
    param([double]$Bajty)
    if ($Bajty -ge 1GB) { return ('{0:N2} GB' -f ($Bajty / 1GB)) }
    if ($Bajty -ge 1MB) { return ('{0:N1} MB' -f ($Bajty / 1MB)) }
    if ($Bajty -ge 1KB) { return ('{0:N0} kB' -f ($Bajty / 1KB)) }
    return ('{0:N0} B' -f $Bajty)
}

function Format-Czas {
    param([double]$Sekundy)
    if ($Sekundy -lt 0 -or [double]::IsInfinity($Sekundy) -or [double]::IsNaN($Sekundy)) { return '--:--:--' }
    if ($Sekundy -gt 359999) { return '--:--:--' }
    $t = [TimeSpan]::FromSeconds([Math]::Round($Sekundy))
    return ('{0:d2}:{1:d2}:{2:d2}' -f [int]$t.TotalHours, $t.Minutes, $t.Seconds)
}
