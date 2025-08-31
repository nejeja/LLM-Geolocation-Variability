# Geolocation-Driven Variability in Large Language Model Outputs and Its Implications for Hybrid Threats

This repository provides the **replication package** for the article:

> Nejedlý, J. (2025). *Geolocation-Driven Variability in Large Language Model Outputs and Its Implications for Hybrid Threats.*

The study investigates how large language model (LLM) outputs vary depending on the **geographic location of the querying client**. Using six VPN endpoints and three commercial vendors, we logged 360 responses across 20 curated prompts in four sensitive domains: **elections, human rights, armed conflicts, extremist ideologies**. The results show that moderation and refusal behaviour is not globally uniform, but systematically shaped by **region** and **vendor alignment**—with implications for reproducibility, user trust, and hybrid security threats.

---

## Repository contents

- **`prompts.csv`** – the curated set of 20 prompts (English + Czech labels).  
- **`schema.csv`** – schema of the logging format (metadata + response fields).  
- **`runner.py`** – main orchestrator; rotates VPN endpoints, queries APIs, logs results.  
- **`vpn_switch.sh`** / **`cycle.sh`** – shell utilities for VPN switching.  
- **`toxicity_score.py`** – computes toxicity scores (Perspective API).  
- **`codebook.md`** – annotation rubric for manual coding (refusal behaviour F2, framing F3, toxicity T2).  
- **`README.md`** – this documentation.  

---

## Methodological summary

- **Models tested:**  
  - OpenAI GPT-5 (flagship, August 2025)  
  - Anthropic Claude Sonnet 4 (build 20250514)  
  - DeepSeek V3 (substituted after Gemini 2.5 Pro blocked VPN access)

- **Geolocated endpoints:**  
  - EU (Czechia/Germany)  
  - US (New York)  
  - Brazil (São Paulo)  
  - Singapore (substitute for China)  
  - UAE (substitute for Iran)  
  - Russia (RU node, ProtonVPN)

- **Dataset:** 20 prompts × 3 vendors × 6 regions = **360 responses**.  
- **Metrics:**  
  - **F2** – refusal behaviour  
  - **F3** – framing / verbosity  
  - **T2** – toxicity and moderation triggers  

---

## How to reproduce

1. **Set API keys** as environment variables:
    export OPENAI_API_KEY=...
    export ANTHROPIC_API_KEY=...
    export DEEPSEEK_API_KEY=...
2. **Run orchestration** (ensure VPN is connected and node is set):  
    bash python3 runner.py
3.  Add toxicity scores (optional):
    python3 toxicity_score.py results.csv results_tox.csv
4.  Analyse & plot:
    Refusal heatmap (F2)
    Length/verbosity distributions (F3)
    Toxicity histograms (T2)
    
Ethics and Terms of Service
VPN switching was used solely for academic research to study geolocation effects.
No attempts were made to bypass safeguards, overload services, or generate harmful content.
Prompts were designed to be safe and reproducible.
Outputs are shared in aggregate to reduce vendor-specific reputational risks.

Citation
If you use this package, please cite:
@article{nejedly2025geolocation,
  title={Geolocation-Driven Variability in Large Language Model Outputs and Its Implications for Hybrid Threats},
  author={Nejedlý, Jan},
  year={2025},
  journal={Preprint / Working Paper},
  url={https://github.com/nejja/LLM-Geolocation-Variability}
}
