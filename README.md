# AutoDocOrganizer

Ein leistungsstarkes Shell-Skript zur automatischen Klassifizierung und Organisation von Dokumenten aus einem ZIP-Archiv mithilfe von KI. Das Skript extrahiert Text aus verschiedenen Dateitypen (PDFs, Word-Dokumente, Bilder usw.), klassifiziert jedes Dokument mithilfe der DeepSeek-API und sortiert sie in entsprechende Ordner.

## 🆕 Neu in Version 2.0

- **Optionale Parallelverarbeitung**: Beschleunigen Sie die Verarbeitung großer Archive durch parallele API-Anfragen
- **Fortschrittsanzeige**: Live-Fortschrittsbalken während der Verarbeitung
- **Detaillierte Statistiken**: Umfassende Verarbeitungsstatistiken inkl. Geschwindigkeit und Erfolgsquote
- **Robuste Fehlerbehandlung**: Automatische Wiederholungsversuche bei API-Fehlern
- **Speicherschonender Standard**: Sequenzielle Verarbeitung als Standard für schwache Systeme

## ✨ Hauptfunktionen

- **Automatische Kategorisierung**: Nutzt ein KI-Sprachmodell (DeepSeek), um Dokumente intelligent in Kategorien wie Rechnung, Vertrag, Bericht usw. einzuordnen.

- **Breite Dateiformatunterstützung**: Verarbeitet eine Vielzahl von Formaten, darunter:
  - PDF
  - DOCX
  - TXT, MD, CSV
  - Bilddateien (PNG, JPG, TIFF etc.) durch Texterkennung (OCR)

- **Texterkennung (OCR)**: Integriert Tesseract OCR zur Extraktion von Text aus Bildern und gescannten PDFs.

- **Flexible Verarbeitungsmodi**:
  - **Sequenziell** (Standard): Speicherschonend für schwache Systeme
  - **Parallel** (Optional): Bis zu 20x schneller bei leistungsstarken Systemen

- **Autonome Einrichtung**: Installiert automatisch alle erforderlichen System- und Python-Abhängigkeiten.

- **Einfache Bedienung**: Benötigt nur eine einzige ZIP-Datei als Eingabe und erzeugt ein sauberes, sortiertes ZIP-Archiv als Ausgabe.

- **Sichere API-Schlüssel-Handhabung**: Fragt den API-Schlüssel sicher ab, falls er nicht als Umgebungsvariable gesetzt ist, und validiert ihn vor der Nutzung.

## ⚠️ Wichtiger Hinweis zum Datenschutz (DSGVO)

**Bitte beachten Sie:** Dieses Skript sendet den extrahierten Textinhalt Ihrer Dokumente zur Klassifizierung an die externe API von DeepSeek.

Wenn Ihre Dokumente personenbezogene oder sensible Daten enthalten, unterliegt diese Datenübertragung den Bestimmungen der Datenschutz-Grundverordnung (DSGVO) oder anderen lokalen Datenschutzgesetzen.

Als Nutzer sind Sie selbst dafür verantwortlich, die Einhaltung dieser Vorschriften sicherzustellen. Prüfen Sie vor der Verwendung des Skripts mit sensiblen Daten, ob die Datenschutzrichtlinien und Auftragsdatenverarbeitungs-Verträge von DeepSeek Ihren Anforderungen genügen. Ziehen Sie gegebenenfalls die Anonymisierung oder Schwärzung von Daten in Betracht.

## 🚀 Erste Schritte

### Voraussetzungen

- Ein Debian-basiertes Betriebssystem (entwickelt unter Linux Mint 21.3)
- sudo-Rechte zur Installation von Paketen
- Ein gültiger API-Schlüssel von der [DeepSeek AI Platform](https://platform.deepseek.com)

### Installation

Es ist keine manuelle Installation von Abhängigkeiten erforderlich. Das Skript kümmert sich um alles.

1. AutoDocOrganizer.sh-Datei herunterladen

2. Mache das Skript ausführbar:
   ```bash
   chmod +x AutoDocOrganizer.sh
   ```

## 📖 Verwendung

### Grundlegende Verwendung

```bash
# Standard: Sequenzielle Verarbeitung (speicherschonend)
./AutoDocOrganizer.sh dokumente.zip

# Mit expliziter Parallelverarbeitung (8 parallele Threads)
./AutoDocOrganizer.sh -p 8 dokumente.zip
```

### Erweiterte Optionen

```bash
# Hilfe anzeigen
./AutoDocOrganizer.sh

# Optionen:
#   -p, --parallel <n>  Anzahl der parallel zu verarbeitenden Dokumente
#                       Standard: 1 (sequenzielle Verarbeitung)
```

### Empfohlene Einstellungen

| Archivgröße | System | Empfohlene Parallelität |
|------------|---------|-------------------------|
| < 50 Dateien | Schwach (< 4GB RAM) | 1 (Standard) |
| < 50 Dateien | Stark (> 8GB RAM) | 4-8 |
| 50-200 Dateien | Schwach | 1-2 |
| 50-200 Dateien | Stark | 10-15 |
| > 200 Dateien | Schwach | 1-3 |
| > 200 Dateien | Stark | 15-20 |

**Hinweis:** Bei großen Bildern mit OCR wird empfohlen, die Parallelität niedrig zu halten oder die Standardeinstellung (1) zu verwenden.

### API-Schlüssel

**Option 1 (Empfohlen)**: Setze den API-Schlüssel als Umgebungsvariable
```bash
export DEEPSEEK_API_KEY="DEIN_API_SCHLÜSSEL"
./AutoDocOrganizer.sh dokumente.zip
```

**Option 2**: Führe das Skript ohne die Umgebungsvariable aus. Du wirst dann sicher zur Eingabe deines Schlüssels aufgefordert.

## ⚙️ Wie es funktioniert

Der Prozess läuft in mehreren Schritten ab:

1. **API-Schlüssel-Validierung**: Überprüft, ob der DEEPSEEK_API_KEY vorhanden und gültig ist.

2. **Abhängigkeitsinstallation**: Aktualisiert die Paketlisten und installiert notwendige Tools:
   - System: `tesseract-ocr`, `tesseract-ocr-deu`, `poppler-utils`
   - Python: `openai`, `python-docx`, `pdfminer.six`, `pytesseract`, `pillow`, `tqdm`

3. **Dynamisches Python-Skript**: Erzeugt zur Laufzeit ein Python-Skript mit der Kernlogik für:
   - Parallele oder sequenzielle Dateiverarbeitung
   - Intelligente Retry-Mechanismen
   - Thread-sichere Operationen

4. **Verarbeitung**:
   - Das Eingabe-ZIP wird in ein temporäres Verzeichnis entpackt
   - Jede Datei wird verarbeitet (Text-Extraktion, ggf. OCR)
   - Der extrahierte Text wird an die DeepSeek-API gesendet
   - Dateien werden in Kategorieordner sortiert
   - Fortschritt wird in Echtzeit angezeigt

5. **Archivierung & Bereinigung**:
   - Sortierte Ordner werden in `sorted_documents.zip` gepackt
   - Temporäre Verzeichnisse werden gelöscht
   - Detaillierte Statistiken werden angezeigt

## 📊 Ausgabe

Nach der Verarbeitung erhalten Sie:

- **sorted_documents.zip**: Archiv mit sortierten Dokumenten in Kategorieordnern
- **Verarbeitungsstatistik**: 
  - Anzahl verarbeiteter/erfolgreicher/übersprungener Dateien
  - Verarbeitungszeit und Geschwindigkeit
  - Verwendeter Verarbeitungsmodus

### Beispielausgabe:
```
============================================================
VERARBEITUNGSSTATISTIK
============================================================
Verarbeitete Dateien:     150
Erfolgreich:              145
Übersprungen:               3
Fehlgeschlagen:             2
------------------------------------------------------------
Verarbeitungszeit:     45.32 Sekunden
Dateien pro Sekunde:    3.31
Verarbeitungsmodus:     Parallel (8 Threads)
============================================================
```

*Tatsächliche Geschwindigkeit hängt von Internetverbindung, Dateigröße und Systemleistung ab.*

## 🛠️ Fehlerbehandlung

- **Automatische Wiederholungsversuche**: Bei API-Fehlern bis zu 3 Versuche mit exponentieller Wartezeit
- **Robuste Text-Extraktion**: Fehlertolerante Verarbeitung verschiedener Dateiformate
- **Thread-Sicherheit**: Bei Parallelverarbeitung sind alle Dateioperationen thread-sicher
- **Detaillierte Fehlerausgabe**: Problematische Dateien werden klar gekennzeichnet

## 📜 Lizenz

Dieses Projekt ist unter der Mozilla Public License 2.0 (MPL-2.0) lizenziert.
