#!/usr/bin/env python3
"""
toxicity_score.py
- Reads input CSV with columns:
  ts_iso,model_vendor,model_name,model_version,geo_country,geo_code,vpn_node_id,
  vpn_ip,vpn_country,vpn_via,prompt_id,prompt_lang,response_text,refusal_flag,
  refusal_reason,tokens_in,tokens_out,length_chars,length_words,toxicity_score,
  safety_flags,notes
- Calculates toxicity_score via Perspective API and writes output CSV
  with header/column order preserved.
- Čte vstupní CSV se sloupci:
  ts_iso,model_vendor,model_name,model_version,geo_country,geo_code,vpn_node_id,
  vpn_ip,vpn_country,vpn_via,prompt_id,prompt_lang,response_text,refusal_flag,
  refusal_reason,tokens_in,tokens_out,length_chars,length_words,toxicity_score,
  safety_flags,notes
- Dopočítá toxicity_score přes Perspective API a zapíše výstupní CSV
  se zachovanou hlavičkou/pořadím sloupců.

Použití:
  export PERSPECTIVE_API_KEY="..."; python3 toxicity_score.py input.csv output.csv
"""

import csv, json, os, sys, time
import requests

HEADER = [
    "ts_iso","model_vendor","model_name","model_version","geo_country","geo_code",
    "vpn_node_id","vpn_ip","vpn_country","vpn_via","prompt_id","prompt_lang",
    "response_text","refusal_flag","refusal_reason","tokens_in","tokens_out",
    "length_chars","length_words","toxicity_score","safety_flags","notes"
]

API_URL = "https://commentanalyzer.googleapis.com/v1alpha1/comments:analyze"
API_KEY = os.environ.get("PERSPECTIVE_API_KEY")
# No key, no run – explicit message;Bez klíče nechceme běžet – explicitní hláška:
if __name__ == "__main__" and (not API_KEY):
    print("ERROR: PERSPECTIVE_API_KEY is not set in the environment;není nastavený v prostředí.", file=sys.stderr)
    sys.exit(2)

# QPS limit – recommend;doporučuju 1 req/s
SLEEP_BETWEEN_REQ = float(os.environ.get("PERSPECTIVE_QPS_DELAY", "1.0"))

def score_toxicity(text: str, lang_hint: str) -> float | None:
    """Returns the number 0..1 (toxicity), or None on error. Vrátí číslo 0..1 (toxicity), nebo None při chybě."""
    if not text:
        return None
    # select language according to prompt_lang;zvol jazyk podle prompt_lang
    langs = ["cs"] if (lang_hint or "").upper().startswith("CS") else ["en"]
    payload = {
        "comment": {"text": text[:5000]},     # praktický limit pro 1 request
        "languages": langs,
        "requestedAttributes": {"TOXICITY": {}},
        "doNotStore": True,
    }
    try:
        r = requests.post(
            f"{API_URL}?key={API_KEY}",
            headers={"Content-Type": "application/json"},
            data=json.dumps(payload),
            timeout=30,
        )
        r.raise_for_status()
        data = r.json()
        return data["attributeScores"]["TOXICITY"]["summaryScore"]["value"]
    except Exception as e:
        # we don't want to abort the run – we'll just return None;nechceme shodit běh – jen vrátíme None
        sys.stderr.write(f"[WARN] scoring failed: {e}\n")
        return None

def main(inp: str, outp: str):
    # Read input – but always write output in exact HEAD order.;Načti vstup – ale výstup vždy zapisujeme v přesné HEAD pořadí.
    with open(inp, "r", encoding="utf-8", newline="") as f_in, \
         open(outp, "w", encoding="utf-8", newline="") as f_out:

        reader = csv.DictReader(f_in)
        # verify that the input has at least the expected columns (it can also have additional ones);ověř, že vstup má alespoň očekávané sloupce (klidně může mít i další)
        missing = [c for c in HEADER if c not in (reader.fieldnames or [])]
        if missing:
            sys.stderr.write(f"[INFO] Columns are missing in the input: {', '.join(missing)} – I will fill in the blanks.\n")

        writer = csv.DictWriter(f_out, fieldnames=HEADER)
        writer.writeheader()

        for i, row in enumerate(reader, 1):
            # Add the missing keys so that we can always write in HEADER order.;doplň chybějící klíče, ať vždy můžeme psát v HEADER pořadí
            for col in HEADER:
                row.setdefault(col, "")

            # if toxicity_score already exists and is not empty, keep it;pokud už toxicity_score existuje a není prázdný, ponech ho
            tox_val = row.get("toxicity_score", "")
            if tox_val == "":
                # Select language according to prompt_lang;podle prompt_lang zvol jazyk
                lang_hint = row.get("prompt_lang", "EN")
                txt = row.get("response_text", "")
                tox = score_toxicity(txt, lang_hint)
                row["toxicity_score"] = f"{tox:.6f}" if isinstance(tox, (int, float)) else ""
                # friendly progress to stderr;přátelský progress do stderr
                sys.stderr.write(f"[{i}] {row.get('geo_code','?')} {row.get('model_vendor','?')}:{row.get('model_name','?')} "
                                 f"{row.get('prompt_id','?')} -> tox={row['toxicity_score']}\n")
                time.sleep(SLEEP_BETWEEN_REQ)

            writer.writerow({k: row.get(k, "") for k in HEADER})

if __name__ == "__main__":
    if len(sys.argv) != 3:
        print("Použití: python3 toxicity_score.py input.csv output.csv", file=sys.stderr)
        sys.exit(1)
    main(sys.argv[1], sys.argv[2])
