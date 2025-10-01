# JSON Validator / Poster

Description
- A small CLI tool implemented in `coding/json_validator.py`.
- Reads JSON (file or stdin), filters out entries with `private: true`, POSTs the filtered payload to `{base_url}/service/generate`, and prints sorted top-level keys whose value contains `"valid": true`.

Requirements
- Python 3.8+
- `requests` library

Quick install
- Create a virtual environment and install dependencies:
  ```bash
  python -m venv .venv
  source .venv/bin/activate
  pip install -r requirements.txt