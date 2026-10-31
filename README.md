# YT2DL Swift
Natywna aplikacja SwiftUI dla macOS 14+, jako frontend do [ipincamp/yt2dl](https://github.com/ipincamp/yt2dl). Dodatkowy lokalny silnik yt-dlp obsługuje playlisty i prywatne listy użytkownika.

## Funkcje
- Wklejanie wielu linków, walidacja adresów i usuwanie duplikatów.
- Podgląd miniatur, tytułów, autorów i czasu trwania, zaznaczanie wybranych filmów.
- Serwer yt2dl: rzeczywiste API /api/video-info i /api/download, formaty grupowane jako bundle, audio, video.
- Lokalnie: playlisty, limit podglądu 10–1000, jakość do 4K, audio MP3/M4A/Opus/FLAC, metadane, miniatury i napisy PL/EN.
- Opcjonalny odczyt sesji Chrome/Firefox/Safari przez yt-dlp dla prywatnych playlist, np. Do obejrzenia. Bez zapisywania haseł w aplikacji.
- Sekwencyjna kolejka, anulowanie, ponawianie, wstrzymanie startu następnych zadań, historia i otwieranie plików w Finderze.
- Zapis bez buforowania filmów w pamięci. Lokalnie pobiera yt-dlp, a tryb serwera używa URLSessionDownloadTask.
- Ustawienia są zapamiętywane, a każde zadanie zachowuje własny zestaw opcji.

## Uruchomienie — lokalnie
1. Zainstaluj Xcode / Command Line Tools i Homebrew.
2. W Terminalu wykonaj: **brew install yt-dlp ffmpeg**.
3. Otwórz Package.swift w Xcode i uruchom schemat YT2DL lub wykonaj **swift run**.
4. Sprawdź ścieżkę yt-dlp w ustawieniach: Apple Silicon /opt/homebrew/bin/yt-dlp, Intel /usr/local/bin/yt-dlp.
5. Wklej link, pokaż podgląd, wybierz materiały i dodaj do kolejki.

Do aktualnych mechanizmów YouTube yt-dlp może wymagać dodatkowego środowiska JavaScript (np. **brew install deno**); zobacz oficjalne wymagania yt-dlp. W razie błędów ekstrakcji zaktualizuj silnik przez Homebrew.

## Tryb serwera yt2dl
Uruchom backend zgodnie z jego README, wybierz „Serwer yt2dl” i ustaw adres, np. http://localhost:3000. Backend wymaga Node.js >=22. Nie jest wbudowany ani uruchamiany automatycznie. Do serwera zdalnego używaj HTTPS.

**Istotna różnica:** README upstream pokazuje inne pola niż jego bieżący kod. Ten klient implementuje rzeczywistą odpowiedź thumbnail i formats.bundle/video/audio, a nie przykładową płaską tablicę z README.

Serwer upstream nie udostępnia API playlist, logowania, scalania wybranych strumieni, konwersji do MP3 ani dodatkowych opcji. W tym trybie wybiera się tylko format faktycznie udostępniony przez backend. Tryb „Wideo i dźwięk” pokazuje wyłącznie formaty bundle; nie oznacza to dostępności 1080p lub 4K. Do tych funkcji wybierz silnik lokalny.

## Biblioteka i playlisty
Wklej adres konkretnej playlisty (także list=WL), nie ogólną stronę Biblioteka. Prywatne listy wymagają zalogowania w wybranej przeglądarce i zgody systemu na dostęp do jej danych. Obsługa zależy od YouTube, yt-dlp oraz uprawnień macOS. Podgląd playlist jest płaski, więc część metadanych może nie być dostępna. Limit podglądu jest widoczny w interfejsie; zwiększ go przed ponownym wczytaniem większej listy.

## Budowanie aplikacji
W katalogu repozytorium wykonaj **swift test**, następnie **bash scripts/build-app.sh**.

Wynik: dist/YT2DL.app oraz dist/YT2DL-macOS.zip. Przeciągnij aplikację do Applications. Build lokalny jest podpisany ad hoc; dystrybucja bez ostrzeżeń Gatekeeper wymaga Developer ID i notaryzacji właściciela. yt-dlp i ffmpeg są zależnościami zewnętrznymi. Workflow GitHub Actions buduje i publikuje ZIP jako artefakt po pushu.

## Zachowanie kolejki
Wstrzymanie kolejki pozwala dokończyć bieżące zadanie. Anulowanie lokalne zachowuje plik częściowy; ponowienie korzysta z mechanizmu kontynuacji yt-dlp. Pobrania serwerowe po ponowieniu zaczynają się od początku. Po ponownym uruchomieniu przerwane zadania wymagają kliknięcia „Ponów”. Historia jest w ~/Library/Application Support/YT2DL/history.json; „Wyczyść historię” usuwa tylko wpisy, nie pobrane pliki. Format wideo lokalnego to MKV (scalanie bez ponownej kompresji).

## Testy i granice weryfikacji
Testy obejmują kontrakt odpowiedzi upstream, argumenty silnika, odrzucanie fałszywych domen, duplikaty, nazwy plików oraz obsługę procesów i anulowania. Nie zastępują testu pobierania z działającego backendu/YouTube; usługa może wymagać logowania, aktualizacji ekstraktora lub odmówić dostępu.

## Licencja i pochodzenie
Nowy, niezależnie napisany klient komunikujący się przez HTTP oraz CLI. Kod backendu yt2dl nie jest kopiowany ani dołączany. Backend ipincamp/yt2dl: GPL-3.0, autor ipincamp. yt-dlp i ffmpeg zachowują własne licencje. Kod klienta: MIT, zobacz LICENSE.
