# YT2DL Swift — All-in-One
Natywna aplikacja macOS 14+ dla Apple Silicon. Wklej link, sprawdź podgląd i pobierz.
**Bez Homebrew, Pythona, terminala, instalowania bibliotek ani osobnego serwera.**

## Instalacja użytkownika
1. Pobierz paczkę YT2DL-All-in-One-macOS.zip.
2. Rozpakuj i przeciągnij YT2DL.app do folderu Aplikacje.
3. Otwórz aplikację i wklej link do filmu lub playlisty.

Pakiet zawiera yt-dlp, FFmpeg, FFprobe oraz Deno. Narzędzia działają bez systemowych bibliotek Homebrew i są odnajdywane względem aktualnego położenia aplikacji. Domyślnie aplikacja korzysta z wbudowanego silnika. Nie pobiera instalatorów przy pierwszym uruchomieniu.

Paczka podpisana ad hoc nie ma notaryzacji Apple. Pierwsze uruchomienie może wymagać zezwolenia w ustawieniach Prywatność i ochrona. Pełne usunięcie tego komunikatu wymaga podpisu Developer ID i notaryzacji właściciela.

## Funkcje
- Wiele linków, usuwanie duplikatów i podgląd miniatur, tytułów, autorów i czasu trwania.
- Wybór filmów z playlisty, limit podglądu do 1000 pozycji.
- Wideo z dźwiękiem do 4K (MKV), samo wideo lub audio MP3/M4A/Opus/FLAC.
- Metadane, miniatury, napisy PL/EN.
- Kolejka sekwencyjna, anulowanie, ponawianie, historia i otwieranie plików w Finderze.
- Strumieniowy zapis na dysk; film nie jest przechowywany w RAM.
- Prywatne playlisty przez opcjonalną sesję Chrome/Firefox/Safari. System może poprosić o dostęp.
- Opcjonalny tryb zewnętrznego serwera [ipincamp/yt2dl](https://github.com/ipincamp/yt2dl), dla zaawansowanych. Nie jest potrzebny do zwykłego działania.

Biblioteka YouTube nie jest pojedynczą playlistą — wklej link do konkretnej listy, np. Do obejrzenia. Niektóre filmy, metadane lub napisy mogą być niedostępne. Jakość zależy od źródła.

## Aktualizacje
Wbudowane silniki są dostarczane wraz z kolejnymi wersjami aplikacji. Po zmianach YouTube może być potrzebna aktualizacja całej aplikacji. Program nie modyfikuje podpisanego pakietu w tle.

## Budowanie — wyłącznie dla dewelopera
Otwórz Package.swift w Xcode lub użyj swift run do pracy nad interfejsem. Kompletne wydanie buduje polecenie **bash scripts/build-app.sh**.

Build wymaga Xcode, Python 3, Homebrew, pkgconf i nasm. Skrypt pobiera standalone yt-dlp oraz Deno z oficjalnych wydań, weryfikuje SHA256 i buduje niezależny, statyczny FFmpeg z LAME i Opus. Homebrew dostarcza wyłącznie metadane źródeł na maszynie budującej — użytkownik aplikacji go nie potrzebuje.

Workflow macOS buduje pakiet All-in-One i uruchamia testy z PATH ograniczonym do narzędzi systemowych. Sprawdza start wszystkich narzędzi, konwersję WAV do MP3 i Opus, FFprobe, podpis oraz przeniesienie aplikacji do ścieżki ze spacjami.

## Licencje
Kod klienta: MIT. Dodatkowe programy zachowują własne licencje. FFmpeg jest budowany z wyłączonym GPL i nonfree; do paczki dołączane są źródła FFmpeg/LAME/Opus oraz dokładny skrypt budowania. Deno: MIT. Samodzielne wydanie yt-dlp macOS stanowi dystrybucję GPLv3+ ze składnikami opisanymi w upstream THIRD_PARTY_LICENSES. Licencje i źródła znajdują się wewnątrz aplikacji: Ustawienia → Licencje i składniki.

## Tryb zewnętrznego serwera
Klient wykorzystuje rzeczywisty kontrakt API yt2dl: thumbnail oraz formats.bundle/video/audio. Serwer upstream nie ma API playlist ani konwersji MP3; te opcje zapewnia silnik wbudowany. Serwer nie jest dołączany ani wymagany.

## Historia i kolejka
Wstrzymanie kolejki pozwala dokończyć bieżące zadanie. Anulowanie lokalne zachowuje plik częściowy. Ponowienie korzysta z kontynuacji yt-dlp. Historia: ~/Library/Application Support/YT2DL/history.json. Jej wyczyszczenie nie usuwa plików. Zadania przerwane przy zamknięciu aplikacji można ponowić ręcznie.
