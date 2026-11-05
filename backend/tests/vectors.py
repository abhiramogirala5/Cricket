"""Loader for the shared scoring vectors (docs/scoring_test_vectors.json)."""

from __future__ import annotations

import json
from pathlib import Path
from typing import Any

VECTORS_PATH = Path(__file__).resolve().parents[2] / "docs" / "scoring_test_vectors.json"
VECTORS: dict[str, Any] = json.loads(VECTORS_PATH.read_text(encoding="utf-8"))
DEFAULTS: dict[str, Any] = VECTORS["delivery_defaults"]


def full_delivery(partial: dict[str, Any]) -> dict[str, Any]:
    return {**DEFAULTS, **partial}
