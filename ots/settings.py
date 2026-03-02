import json
from pathlib import Path


APP_DATA = Path.home() / "Library" / "Application Support" / "On The Spot"
SETTINGS_PATH = APP_DATA / "settings.json"


DEFAULTS = {
    "backend": "auto",
    "model": "small",
    "kb_path": "",
    "last_audio": "",
    "overlay_enabled": False,
    "clickthrough": False,
    "threads": 4,
}


def load_settings() -> dict:
    SETTINGS_PATH.parent.mkdir(parents=True, exist_ok=True)
    if SETTINGS_PATH.exists():
        try:
            data = json.loads(SETTINGS_PATH.read_text(encoding="utf-8"))
            merged = DEFAULTS.copy()
            merged.update(data)
            return merged
        except Exception:
            return DEFAULTS.copy()
    return DEFAULTS.copy()


def save_settings(settings: dict):
    SETTINGS_PATH.parent.mkdir(parents=True, exist_ok=True)
    SETTINGS_PATH.write_text(json.dumps(settings, indent=2), encoding="utf-8")
