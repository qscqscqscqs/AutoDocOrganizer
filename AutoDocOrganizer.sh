#!/bin/bash

set -e

## Funktion: Fehlermeldung ausgeben und Skript beenden
abort() {
  echo "Fehler: $1" >&2
  exit 1
}

## API‑Schlüssel erfragen, falls nicht gesetzt und Gültigkeit prüfen
if [ -z "$DEEPSEEK_API_KEY" ]; then
  read -r -s -p "Bitte geben Sie Ihren DeepSeek‑API‑Schlüssel ein: " input_key
  echo
  if [ -z "$input_key" ]; then
    abort "Es wurde kein API‑Schlüssel eingegeben. Abbruch."
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

## Überprüfen, ob eine ZIP‑Datei als Argument übergeben wurde
if [ $# -lt 1 ]; then
  echo "Verwendung: $0 <pfad_zur_zip_datei>"
  echo "Beispiel: $0 eingangsdokumente.zip"
  exit 1
fi

ZIP_FILE="$1"

if [ ! -f "$ZIP_FILE" ]; then
  abort "Die angegebene ZIP‑Datei existiert nicht: $ZIP_FILE"
fi

echo "[1/5] Systempakete aktualisieren und Abhängigkeiten installieren …"

sudo apt-get update -qq
sudo apt-get install -y unzip tesseract-ocr tesseract-ocr-deu python3 python3-pip python3-venv poppler-utils curl

## Installiere Python-Abhängigkeiten
echo "[2/5] Python‑Abhängigkeiten installieren …"
python3 -m pip install --upgrade pip 
python3 -m pip install --upgrade openai python-docx pdfminer.six pytesseract pillow --break-system-packages

## Stelle sicher, dass die Tesseract‑Binärdatei gefunden wird
if ! command -v tesseract >/dev/null 2>&1; then
  abort "Tesseract‑OCR konnte nicht gefunden werden. Bitte prüfen Sie die Installation."
fi

## Erzeuge die Python‑Klassifikationsdatei im aktuellen Verzeichnis
CLASSIFIER_SCRIPT="classify_documents.py"
echo "[3/5] Python‑Klassifikationsskript erstellen …"
cat > "$CLASSIFIER_SCRIPT" <<'PYEOF'
#!/usr/bin/env python3

import os
import sys
import zipfile
import shutil
import re

from pathlib import Path

try:
    import pytesseract  # type: ignore
    from PIL import Image  # type: ignore
    import docx  # type: ignore
    from pdfminer.high_level import extract_text  # type: ignore
    from openai import OpenAI  # type: ignore
except ImportError as e:
    print(f"Fehlende Python‑Abhängigkeiten: {e}. Bitte führen Sie das Installationsskript erneut aus.")
    sys.exit(1)


API_KEY = os.environ.get("DEEPSEEK_API_KEY")
if not API_KEY:
    print("Die Umgebungsvariable DEEPSEEK_API_KEY ist nicht gesetzt. Bitte setzen Sie sie vor dem Ausführen des Skripts.")
    sys.exit(1)

client = OpenAI(api_key=API_KEY, base_url="https://api.deepseek.com")


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
        print(f"Fehler beim Extrahieren von Text aus {file_path}: {ex}")
        text = ""
    # Begrenze Länge des Textes, um Kosten zu senken und das Kontextlimit zu wahren
    return text[:12000]


def classify_document(text: str) -> tuple[str, str] | tuple[None, None]:
    """Sendet Text an die DeepSeek‑API und gibt (Slug, Originalbezeichnung) zurück."""
    system_message = {
        "role": "system",
        "content": (
            "Du bist ein Dokumenten‑Klassifizierer. Ordne den folgenden Text einer "
            "übergeordneten Kategorie zu (z. B. Rechnung, Vertrag, Bericht, Präsentation, "
            "Geschäftsbrief, Angebot, Einladung, Sonstiges). Antworte ausschließlich mit "
            "der Kategorienbezeichnung (ein Wort oder eine kurze Phrase) und ohne "
            "zusätzliche Erklärungen."
        ),
    }
    user_message = {"role": "user", "content": text}
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
        print(f"Fehler bei der DeepSeek‑API‑Anfrage: {ex}")
        return None, None


def main(zip_path: str) -> None:
    zip_file = Path(zip_path)
    if not zip_file.is_file():
        print(f"Die Datei {zip_path} existiert nicht oder ist keine reguläre Datei.")
        sys.exit(1)

    temp_dir = Path("temp_unzipped")
    if temp_dir.exists():
        shutil.rmtree(temp_dir)
    temp_dir.mkdir(parents=True, exist_ok=True)

    # Entpacke das ZIP‑Archiv
    with zipfile.ZipFile(zip_file, "r") as zf:
        zf.extractall(temp_dir)

    output_dir = Path("sorted_documents")
    if output_dir.exists():
        shutil.rmtree(output_dir)
    output_dir.mkdir(parents=True, exist_ok=True)

    # Durchsuche alle Dateien rekursiv
    for root, dirs, files in os.walk(temp_dir):
        for filename in files:
            current_path = Path(root) / filename
            # Extrahiere Text
            text = extract_text_from_file(current_path)
            if not text.strip():
                # Keine Textbasis – Datei überspringen
                continue
            slug, label = classify_document(text)
            if slug is None:
                # API gab keinen sinnvollen Typ zurück
                continue
            category_folder = output_dir / slug
            category_folder.mkdir(parents=True, exist_ok=True)
            # Kopiere die Originaldatei in den Kategorienordner
            shutil.copy2(current_path, category_folder / current_path.name)
            # Lege eine .label‑Datei mit der ursprünglichen Kategorienbezeichnung an
            label_file = category_folder / f"{current_path.name}.label.txt"
            with label_file.open("w", encoding="utf-8") as lf:
                lf.write(label)

    # Erstelle ZIP der sortierten Dokumente
    result_zip = Path("sorted_documents.zip")
    if result_zip.exists():
        result_zip.unlink()
    shutil.make_archive("sorted_documents", "zip", output_dir)
    print(f"Sortierung abgeschlossen. Archiv: {result_zip.resolve()}")

    # Aufräumen
    shutil.rmtree(temp_dir)


if __name__ == "__main__":
    if len(sys.argv) != 2:
        print(f"Nutzung: {sys.argv[0]} <pfad_zur_zip_datei>")
        sys.exit(1)
    main(sys.argv[1])
PYEOF

chmod +x "$CLASSIFIER_SCRIPT"

## Führe das Klassifikationsskript aus
echo "[4/5] Dokumente klassifizieren und sortieren …"
python3 "$CLASSIFIER_SCRIPT" "$ZIP_FILE"

## Ergebnisarchiv bereitstellen
echo "[5/5] Vorgang abgeschlossen. Die sortierten Dateien befinden sich im Archiv 'sorted_documents.zip'."
