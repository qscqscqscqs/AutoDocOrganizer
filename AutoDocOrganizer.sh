#!/bin/bash

set -e

## Funktion: Fehlermeldung ausgeben und Skript beenden
abort() {
  echo "Fehler: $1" >&2
  exit 1
}

## Standard: Keine Parallelisierung (1 = sequenzielle Verarbeitung)
PARALLEL_JOBS=1

## Argumente parsen
while [[ $# -gt 0 ]]; do
  case $1 in
    -p|--parallel)
      PARALLEL_JOBS="$2"
      shift 2
      ;;
    *)
      ZIP_FILE="$1"
      shift
      ;;
  esac
done

## Überprüfen, ob eine ZIP-Datei als Argument übergeben wurde
if [ -z "$ZIP_FILE" ]; then
  echo "Verwendung: $0 [OPTIONEN] <pfad_zur_zip_datei>"
  echo ""
  echo "Beispiele:"
  echo "  $0 eingangsdokumente.zip                    # Sequenzielle Verarbeitung (Standard)"
  echo "  $0 -p 8 eingangsdokumente.zip                # 8 parallele Prozesse"
  echo ""
  echo "Optionen:"
  echo "  -p, --parallel <n>  Anzahl der parallel zu verarbeitenden Dokumente"
  echo "                       Standard: 1 (sequenzielle Verarbeitung, empfohlen für schwache Systeme)"
  echo "                       Höhere Werte nur für leistungsstarke Systeme empfohlen!"
  exit 1
fi

if [ ! -f "$ZIP_FILE" ]; then
  abort "Die angegebene ZIP-Datei existiert nicht: $ZIP_FILE"
fi

## Validiere Parallelitätswert
if ! [[ "$PARALLEL_JOBS" =~ ^[0-9]+$ ]] || [ "$PARALLEL_JOBS" -lt 1 ]; then
  abort "Die Anzahl der parallelen Jobs muss eine positive Ganzzahl sein: $PARALLEL_JOBS"
fi

if [ "$PARALLEL_JOBS" -eq 1 ]; then
  echo "[+] Konfiguration: Sequenzielle Verarbeitung (empfohlen für schwache Systeme)"
else
  echo "[+] Konfiguration: $PARALLEL_JOBS parallele Verarbeitungsprozesse"
  echo "[!] Warnung: Parallelverarbeitung kann bei großen Bildern/PDFs viel Speicher benötigen!"
fi

## API-Schlüssel erfragen, falls nicht gesetzt und Gültigkeit prüfen
if [ -z "$DEEPSEEK_API_KEY" ]; then
  read -r -s -p "Bitte geben Sie Ihren DeepSeek-API-Schlüssel ein: " input_key
  echo
  if [ -z "$input_key" ]; then
    abort "Es wurde kein API-Schlüssel eingegeben. Abbruch."
  fi
  export DEEPSEEK_API_KEY="$input_key"
fi

echo "[+] Prüfe Gültigkeit des API-Schlüssels..."
API_CHECK_RESPONSE=$(curl -s -X POST "https://api.deepseek.com/v1/chat/completions" \
  -H "Content-Type: application/json" \
  -H "Authorization: Bearer $DEEPSEEK_API_KEY" \
  -d '{
    "model": "deepseek-chat",
    "messages": [
      {"role": "user", "content": "hello"}
    ],
    "max_tokens": 1
  }' | grep -o "choices")

if [[ ! "$API_CHECK_RESPONSE" == "choices" ]]; then
  abort "Der eingegebene API-Schlüssel ist ungültig oder konnte nicht verifiziert werden. Bitte überprüfen Sie den Schlüssel und versuchen Sie es erneut."
fi
echo "[+] API-Schlüssel erfolgreich verifiziert."

echo "[1/5] Systempakete aktualisieren und Abhängigkeiten installieren …"

sudo apt-get update -qq
sudo apt-get install -y unzip tesseract-ocr tesseract-ocr-deu python3 python3-pip python3-venv poppler-utils curl

## Installiere Python-Abhängigkeiten
echo "[2/5] Python-Abhängigkeiten installieren …"
python3 -m pip install --upgrade pip 
python3 -m pip install --upgrade openai python-docx pdfminer.six pytesseract pillow tqdm --break-system-packages

## Stelle sicher, dass die Tesseract-Binärdatei gefunden wird
if ! command -v tesseract >/dev/null 2>&1; then
  abort "Tesseract-OCR konnte nicht gefunden werden. Bitte prüfen Sie die Installation."
fi

## Erzeuge die Python-Klassifikationsdatei im aktuellen Verzeichnis
CLASSIFIER_SCRIPT="classify_documents_parallel.py"
echo "[3/5] Python-Klassifikationsskript erstellen …"
cat > "$CLASSIFIER_SCRIPT" <<'PYEOF'
#!/usr/bin/env python3

import os
import sys
import zipfile
import shutil
import re
import argparse
from concurrent.futures import ThreadPoolExecutor, as_completed
from threading import Lock
from pathlib import Path
from typing import Optional, Tuple, List
import time

try:
    import pytesseract  # type: ignore
    from PIL import Image  # type: ignore
    import docx  # type: ignore
    from pdfminer.high_level import extract_text  # type: ignore
    from openai import OpenAI  # type: ignore
    from tqdm import tqdm  # type: ignore
except ImportError as e:
    print(f"Fehlende Python-Abhängigkeiten: {e}. Bitte führen Sie das Installationsskript erneut aus.")
    sys.exit(1)


API_KEY = os.environ.get("DEEPSEEK_API_KEY")
if not API_KEY:
    print("Die Umgebungsvariable DEEPSEEK_API_KEY ist nicht gesetzt. Bitte setzen Sie sie vor dem Ausführen des Skripts.")
    sys.exit(1)

# API Client
client = OpenAI(api_key=API_KEY, base_url="https://api.deepseek.com")

# Lock für Thread-sichere Dateioperationen (nur bei Parallelverarbeitung nötig)
file_lock = Lock()

# Statistiken
stats = {
    "processed": 0,
    "successful": 0,
    "failed": 0,
    "skipped": 0
}
stats_lock = Lock()


def extract_text_from_file(file_path: Path) -> str:
    """Extrahiert Text aus verschiedenen Dokumentformaten (txt, pdf, docx, bilder)."""
    ext = file_path.suffix.lower()[1:]
    text = ""
    try:
        if ext in {"txt", "md", "csv"}:
            text = file_path.read_text(encoding="utf-8", errors="ignore")
        elif ext == "pdf":
            text = extract_text(str(file_path))
        elif ext == "docx":
            doc = docx.Document(str(file_path))
            text = "\n".join(paragraph.text for paragraph in doc.paragraphs)
        elif ext in {"png", "jpg", "jpeg", "bmp", "tiff", "tif", "gif"}:
            # Lese Bild und führe OCR mit deutscher Sprache aus
            text = pytesseract.image_to_string(Image.open(str(file_path)), lang="deu")
        else:
            # Für unbekannte Formate keine Textausgabe
            text = ""
    except Exception as ex:
        print(f"\nFehler beim Extrahieren von Text aus {file_path.name}: {ex}")
        text = ""
    # Begrenze Länge des Textes, um Kosten zu senken und das Kontextlimit zu wahren
    return text[:12000]


def classify_document(text: str, retry_count: int = 3) -> Tuple[Optional[str], Optional[str]]:
    """Sendet Text an die DeepSeek-API und gibt (Slug, Originalbezeichnung) zurück."""
    system_message = {
        "role": "system",
        "content": (
            "Du bist ein Dokumenten-Klassifizierer. Ordne den folgenden Text einer "
            "übergeordneten Kategorie zu (z. B. Rechnung, Vertrag, Bericht, Präsentation, "
            "Geschäftsbrief, Angebot, Einladung, Sonstiges). Antworte ausschließlich mit "
            "der Kategorienbezeichnung (ein Wort oder eine kurze Phrase) und ohne "
            "zusätzliche Erklärungen."
        ),
    }
    user_message = {"role": "user", "content": text}
    
    for attempt in range(retry_count):
        try:
            response = client.chat.completions.create(
                model="deepseek-chat",
                messages=[system_message, user_message],
                temperature=0.0,
                max_tokens=20,
            )
            content = response.choices[0].message.content.strip()
            # Slugify: nur alphanumerische Zeichen und Unterstriche, alles klein
            slug = re.sub(r"[^\w-]+", "_", content.lower()).strip("_")
            return slug if slug else None, content
        except Exception as ex:
            if attempt < retry_count - 1:
                time.sleep(0.5 * (attempt + 1))  # Exponential backoff
                continue
            print(f"\nFehler bei der DeepSeek-API-Anfrage nach {retry_count} Versuchen: {ex}")
            return None, None


def process_single_file(args: Tuple[Path, Path]) -> Tuple[bool, str]:
    """Verarbeitet eine einzelne Datei und gibt (Erfolg, Nachricht) zurück."""
    current_path, output_dir = args
    filename = current_path.name
    
    try:
        # Extrahiere Text
        text = extract_text_from_file(current_path)
        if not text.strip():
            with stats_lock:
                stats["skipped"] += 1
            return False, f"⊘ {filename}: Kein Text extrahiert"
        
        # Klassifiziere Dokument
        slug, label = classify_document(text)
        if slug is None:
            with stats_lock:
                stats["failed"] += 1
            return False, f"✗ {filename}: Klassifizierung fehlgeschlagen"
        
        # Erstelle Kategorie-Ordner und kopiere Datei
        with file_lock:
            category_folder = output_dir / slug
            category_folder.mkdir(parents=True, exist_ok=True)
            shutil.copy2(current_path, category_folder / filename)
            
            # Lege eine .label-Datei mit der ursprünglichen Kategorienbezeichnung an
            label_file = category_folder / f"{filename}.label.txt"
            with label_file.open("w", encoding="utf-8") as lf:
                lf.write(label)
        
        with stats_lock:
            stats["successful"] += 1
        
        return True, f"✓ {filename} → {slug}"
    
    except Exception as ex:
        with stats_lock:
            stats["failed"] += 1
        return False, f"✗ {filename}: {ex}"


def process_sequentially(files_to_process: List[Tuple[Path, Path]], output_dir: Path) -> None:
    """Verarbeitet Dateien sequenziell (keine Parallelisierung)."""
    total_files = len(files_to_process)
    
    print(f"Starte sequenzielle Verarbeitung (speicherschonend)...")
    print("-" * 60)
    
    with tqdm(total=total_files, desc="Verarbeitung", unit="Datei") as pbar:
        for file_path, output_dir in files_to_process:
            success, message = process_single_file((file_path, output_dir))
            
            # Zeige detaillierte Ausgabe für wichtige Ereignisse
            if not success and "✗" in message:
                tqdm.write(message)
            elif success and stats["successful"] % 10 == 0:
                # Alle 10 erfolgreiche Dateien einen Status ausgeben
                tqdm.write(f"[{stats['successful']} Dateien erfolgreich verarbeitet]")
            
            pbar.update(1)
            stats["processed"] += 1


def process_parallel(files_to_process: List[Tuple[Path, Path]], output_dir: Path, parallel_jobs: int) -> None:
    """Verarbeitet Dateien parallel."""
    total_files = len(files_to_process)
    
    print(f"Starte Parallelverarbeitung mit {parallel_jobs} Threads...")
    print("⚠ Hinweis: Bei Speicherproblemen nutzen Sie die sequenzielle Verarbeitung (ohne -p Parameter)")
    print("-" * 60)
    
    with ThreadPoolExecutor(max_workers=parallel_jobs) as executor:
        # Starte alle Jobs
        futures = {executor.submit(process_single_file, args): args 
                  for args in files_to_process}
        
        # Verarbeite Ergebnisse mit Progress Bar
        with tqdm(total=total_files, desc="Verarbeitung", unit="Datei") as pbar:
            for future in as_completed(futures):
                success, message = future.result()
                # Detaillierte Ausgabe für Fehler
                if not success and "✗" in message:
                    tqdm.write(message)
                pbar.update(1)
                with stats_lock:
                    stats["processed"] += 1


def main(zip_path: str, parallel_jobs: int) -> None:
    start_time = time.time()
    
    zip_file = Path(zip_path)
    if not zip_file.is_file():
        print(f"Die Datei {zip_path} existiert nicht oder ist keine reguläre Datei.")
        sys.exit(1)

    temp_dir = Path("temp_unzipped")
    if temp_dir.exists():
        shutil.rmtree(temp_dir)
    temp_dir.mkdir(parents=True, exist_ok=True)

    # Entpacke das ZIP-Archiv
    print(f"Entpacke Archiv: {zip_path}")
    with zipfile.ZipFile(zip_file, "r") as zf:
        zf.extractall(temp_dir)

    output_dir = Path("sorted_documents")
    if output_dir.exists():
        shutil.rmtree(output_dir)
    output_dir.mkdir(parents=True, exist_ok=True)

    # Sammle alle zu verarbeitenden Dateien
    files_to_process: List[Tuple[Path, Path]] = []
    for root, dirs, files in os.walk(temp_dir):
        for filename in files:
            current_path = Path(root) / filename
            files_to_process.append((current_path, output_dir))
    
    total_files = len(files_to_process)
    print(f"Gefundene Dateien: {total_files}")
    
    # Wähle Verarbeitungsmethode basierend auf parallel_jobs
    if parallel_jobs == 1:
        process_sequentially(files_to_process, output_dir)
    else:
        process_parallel(files_to_process, output_dir, parallel_jobs)
    
    # Erstelle ZIP der sortierten Dokumente
    result_zip = Path("sorted_documents.zip")
    if result_zip.exists():
        result_zip.unlink()
    print("\nErstelle Ergebnis-Archiv...")
    shutil.make_archive("sorted_documents", "zip", output_dir)
    
    # Aufräumen
    shutil.rmtree(temp_dir)
    
    # Zeige Statistiken
    elapsed_time = time.time() - start_time
    print("\n" + "=" * 60)
    print("VERARBEITUNGSSTATISTIK")
    print("=" * 60)
    print(f"Verarbeitete Dateien:  {stats['processed']:>6}")
    print(f"Erfolgreich:           {stats['successful']:>6}")
    print(f"Übersprungen:          {stats['skipped']:>6}")
    print(f"Fehlgeschlagen:        {stats['failed']:>6}")
    print("-" * 60)
    print(f"Verarbeitungszeit:     {elapsed_time:.2f} Sekunden")
    if stats['processed'] > 0:
        print(f"Dateien pro Sekunde:   {stats['processed'] / elapsed_time:.2f}")
    if parallel_jobs == 1:
        print(f"Verarbeitungsmodus:    Sequenziell (speicherschonend)")
    else:
        print(f"Verarbeitungsmodus:    Parallel ({parallel_jobs} Threads)")
    print("=" * 60)
    print(f"\n✓ Sortierung abgeschlossen. Archiv: {result_zip.resolve()}")


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description="Klassifiziere und sortiere Dokumente mit DeepSeek API")
    parser.add_argument("zip_file", help="Pfad zur ZIP-Datei mit Dokumenten")
    parser.add_argument("-p", "--parallel", type=int, default=1,
                       help="Anzahl paralleler Verarbeitungs-Threads (Standard: 1 = sequenziell, speicherschonend)")
    
    args = parser.parse_args()
    
    if args.parallel < 1:
        print("Die Anzahl der parallelen Jobs muss mindestens 1 sein.")
        sys.exit(1)
    
    main(args.zip_file, args.parallel)
PYEOF

chmod +x "$CLASSIFIER_SCRIPT"

## Führe das Klassifikationsskript aus
if [ "$PARALLEL_JOBS" -eq 1 ]; then
    echo "[4/5] Dokumente klassifizieren und sortieren (sequenzielle Verarbeitung) …"
else
    echo "[4/5] Dokumente klassifizieren und sortieren (${PARALLEL_JOBS} parallele Prozesse) …"
fi
python3 "$CLASSIFIER_SCRIPT" -p "$PARALLEL_JOBS" "$ZIP_FILE"

## Ergebnisarchiv bereitstellen
echo "[5/5] Vorgang abgeschlossen. Die sortierten Dateien befinden sich im Archiv 'sorted_documents.zip'."