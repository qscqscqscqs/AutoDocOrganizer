AutoDocOrganizer

Ein leistungsstarkes Shell-Skript zur automatischen Klassifizierung und Organisation von Dokumenten aus einem ZIP-Archiv mithilfe von KI. Das Skript extrahiert Text aus verschiedenen Dateitypen (PDFs, Word-Dokumente, Bilder usw.), klassifiziert jedes Dokument mithilfe der DeepSeek-API und sortiert sie in entsprechende Ordner.
  
  Hauptfunktionen:

    Automatische Kategorisierung: Nutzt ein KI-Sprachmodell (DeepSeek), um Dokumente intelligent in Kategorien wie Rechnung, Vertrag, Bericht usw. einzuordnen.

    Breite Dateiformatunterstützung: Verarbeitet eine Vielzahl von Formaten, darunter:

        pdf

        docx

        txt, md, csv

        Bilddateien (png, jpg, tiff etc.) durch Texterkennung (OCR).

    Texterkennung (OCR): Integriert Tesseract OCR zur Extraktion von Text aus Bildern und gescannten PDFs.

    Autonome Einrichtung: Installiert automatisch alle erforderlichen System- und Python-Abhängigkeiten.

    Einfache Bedienung: Benötigt nur eine einzige ZIP-Datei als Eingabe und erzeugt ein sauberes, sortiertes ZIP-Archiv als Ausgabe.

    Sichere API-Schlüssel-Handhabung: Frägt den API-Schlüssel sicher ab, falls er nicht als Umgebungsvariable gesetzt ist, und validiert ihn vor der Nutzung.

⚠️ Wichtiger Hinweis zum Datenschutz (DSGVO)

Bitte beachten Sie: Dieses Skript sendet den extrahierten Textinhalt Ihrer Dokumente zur Klassifizierung an die externe API von DeepSeek.

Wenn Ihre Dokumente personenbezogene oder sensible Daten enthalten, unterliegt diese Datenübertragung den Bestimmungen der Datenschutz-Grundverordnung (DSGVO) oder anderen lokalen Datenschutzgesetzen.

Als Nutzer sind Sie selbst dafür verantwortlich, die Einhaltung dieser Vorschriften sicherzustellen. Prüfen Sie vor der Verwendung des Skripts mit sensiblen Daten, ob die Datenschutzrichtlinien und Auftragsdatenverarbeitungs-Verträge von DeepSeek Ihren Anforderungen genügen. Ziehen Sie gegebenenfalls die Anonymisierung oder Schwärzung von Daten in Betracht.

🚀 Erste Schritte
Voraussetzungen

    Ein Debian-basiertes Betriebssystem (entwickelt unter Linuxmint 21.3).

    sudo-Rechte zur Installation von Paketen.

    Ein gültiger API-Schlüssel vom DeepSeek AI Platform.

Installation

Es ist keine manuelle Installation von Abhängigkeiten erforderlich. Das Skript kümmert sich um alles.

    AutoDocOrganizer.sh-Datei Herunterladen

    Mache das Skript ausführbar:

    chmod +x AutoDocOrganizer.sh

Verwendung

Führe das Skript aus und übergib den Pfad zu deiner ZIP-Datei als einziges Argument.

./AutoDocOrganizer.sh /pfad/zu/deinen/dokumenten.zip

Beispiel:

./AutoDocOrganizer.sh ~/Downloads/eingangsdokumente.zip

API-Schlüssel

    Option 1 (Empfohlen): Setze den API-Schlüssel als Umgebungsvariable.

    export DEEPSEEK_API_KEY="DEIN_API_SCHLÜSSEL"
    ./AutoDocOrganizer.sh dokumente.zip

    Option 2: Führe das Skript ohne die Umgebungsvariable aus. Du wirst dann sicher zur Eingabe deines Schlüssels aufgefordert.

⚙️ Wie es funktioniert

Der Prozess läuft in mehreren Schritten ab:

    API-Schlüssel-Validierung: Überprüft, ob der DEEPSEEK_API_KEY vorhanden und gültig ist.

    Abhängigkeitsinstallation: Aktualisiert die Paketlisten (apt-get update) und installiert notwendige Tools wie tesseract-ocr, python3, pip und poppler-utils.

    Python-Setup: Installiert erforderliche Python-Bibliotheken (openai, python-docx, pdfminer.six, pytesseract, pillow).

    Dynamisches Python-Skript: Erzeugt zur Laufzeit ein Python-Skript (classify_documents.py), das die Kernlogik für die Dateiverarbeitung und Klassifizierung enthält.

    Verarbeitung:

        Das Eingabe-ZIP wird in ein temporäres Verzeichnis entpackt.

        Das Skript durchläuft jede Datei, extrahiert den Textinhalt (via OCR bei Bildern).

        Der extrahierte Text wird an die DeepSeek-API gesendet, um eine passende Kategorie zu erhalten.

        Für jede ermittelte Kategorie wird ein Ordner erstellt (z. B. rechnung).

        Die Originaldatei wird in den entsprechenden Ordner kopiert.

    Archivierung & Bereinigung:

        Alle sortierten Ordner und Dateien werden in ein neues ZIP-Archiv namens sorted_documents.zip gepackt.

        Alle temporären Verzeichnisse werden anschließend gelöscht.

📜 Lizenz

Dieses Projekt ist unter der Mozilla Public License 2.0 (MPL-2.0) lizenziert. 
