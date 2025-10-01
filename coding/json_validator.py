# python
"""
Refactored JSON validator / poster.

Usage:
  python -m coding.json_validator --input coding/example.json --url https://example.com

Features:
- Read JSON from file or stdin (`-`)
- Validate top-level list or map and filter out items where `"private": true`
- POST filtered payload to `{base_url}/service/generate`
- Print sorted top-level keys whose value is a dict with `"valid": true`
- Clear exceptions and exit codes for scripting
"""
from __future__ import annotations

import argparse
import json
import logging
import sys
from typing import Any, Dict, List, Mapping, MutableMapping, Union

import requests
from requests.exceptions import RequestException

logger = logging.getLogger(__name__)
logging.basicConfig(level=logging.INFO, format="%(levelname)s: %(message)s")


class InputError(Exception):
    """Raised for problems reading or parsing input JSON."""


class ValidationError(Exception):
    """Raised for unexpected JSON structure."""


class HTTPRequestError(Exception):
    """Raised for HTTP/post related errors."""


JSONListOrMap = Union[List[Dict[str, Any]], Dict[str, Dict[str, Any]]]


def load_json(path: str) -> Any:
    """
    Load JSON from `path`. If `path` is '-' read from stdin.
    """
    try:
        if path == "-":
            text = sys.stdin.read()
            return json.loads(text)
        with open(path, "r", encoding="utf-8") as f:
            return json.load(f)
    except FileNotFoundError as e:
        logger.error("Input file not found: %s", path)
        raise InputError(str(e)) from e
    except json.JSONDecodeError as e:
        logger.error("Failed to parse JSON in %s: %s", path, e)
        raise InputError(str(e)) from e


def filter_public(data: Any) -> JSONListOrMap:
    """
    Given parsed JSON data (list or map), return only entries where 'private' is False.
    - For top-level list: returns list of dicts
    - For top-level object/map: returns map with same keys and dict values
    Raises ValidationError for unsupported types.
    """
    if isinstance(data, list):
        filtered = [item for item in data if isinstance(item, dict) and not item.get("private", False)]
        logger.info("Loaded list with %d items, %d remain after filtering", len(data), len(filtered))
        return filtered

    if isinstance(data, dict):
        filtered = {k: v for k, v in data.items() if isinstance(v, dict) and not v.get("private", False)}
        logger.info("Loaded map with %d keys, %d remain after filtering", len(data), len(filtered))
        return filtered

    logger.error("Unsupported top-level JSON type: %s (expected list or object)", type(data).__name__)
    raise ValidationError("unsupported top-level JSON type")


def post_generate(base_url: str, payload: Any, verify: bool = True, timeout: int = 10) -> Dict[str, Any]:
    """
    POST `payload` as JSON to `base_url` + /service/generate and return parsed JSON response.
    Raises HTTPRequestError on networking or unexpected response format.
    """
    url = base_url.rstrip("/") + "/service/generate"
    logger.info("Posting to %s (verify=%s)", url, verify)
    headers = {"Content-Type": "application/json"}

    try:
        resp = requests.post(url, json=payload, headers=headers, timeout=timeout, verify=verify)
        resp.raise_for_status()
    except RequestException as e:
        logger.error("HTTP request failed: %s", e)
        raise HTTPRequestError(str(e)) from e

    try:
        data = resp.json()
    except json.JSONDecodeError as e:
        logger.error("Response is not valid JSON: %s", e)
        raise HTTPRequestError("response not valid JSON") from e

    if not isinstance(data, dict):
        logger.error("Expected JSON map/object from server, got %s", type(data).__name__)
        raise HTTPRequestError("expected JSON map/object in response")

    logger.info("Received response with %d top-level keys", len(data))
    return data


def extract_valid_keys(response_map: Mapping[str, Any]) -> List[str]:
    """
    Return sorted list of top-level keys whose value is a dict with 'valid' == True.
    """
    valid_keys: List[str] = []
    for key, val in response_map.items():
        if isinstance(val, Mapping) and val.get("valid") is True:
            valid_keys.append(key)
    valid_keys.sort()
    return valid_keys


def parse_args(argv: List[str] | None = None) -> argparse.Namespace:
    p = argparse.ArgumentParser(description="Post filtered JSON to /service/generate and print valid keys")
    p.add_argument("--input", "-i", default="coding/example.json",
                   help="Input JSON file (use '-' to read from stdin). Default: `coding/example.json`")
    p.add_argument("--url", "-u", default="https://example.com", help="Base URL of target service (include scheme)")
    p.add_argument("--insecure", action="store_true", help="Disable TLS certificate verification (not recommended)")
    p.add_argument("--timeout", type=int, default=10, help="Request timeout in seconds")
    return p.parse_args(argv)


def main(argv: List[str] | None = None) -> int:
    args = parse_args(argv)
    try:
        raw = load_json(args.input)
        payload = filter_public(raw)
        resp_map = post_generate(args.url, payload, verify=not args.insecure, timeout=args.timeout)
        valid_keys = extract_valid_keys(resp_map)
        for k in valid_keys:
            print(k)
        return 0
    except (InputError, ValidationError, HTTPRequestError) as e:
        logger.error("Operation failed: %s", e)
        return 2
    except Exception as e:
        logger.exception("Unexpected error")
        return 1


if __name__ == "__main__":
    sys.exit(main())