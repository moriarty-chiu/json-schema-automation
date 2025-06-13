import os
import json
from pathlib import Path

BASE_DIR = Path(__file__).resolve().parent

flavors_path = BASE_DIR / "flavors.json"
if not flavors_path.exists():
    raise FileNotFoundError(f"Can't find flavors.json file: {flavors_path}")

with open(flavors_path, "r", encoding="utf-8") as f:
    flavors = json.load(f)

for subdir in BASE_DIR.iterdir():
    if subdir.is_dir():
        for json_file in subdir.glob("*.json"):
            with open(json_file, "r", encoding="utf-8") as f:
                try:
                    data = json.load(f)
                except json.JSONDecodeError as e:
                    print(f"Skip invalid JSON files: {json_file} - {e}")
                    continue

            modified = False

            top_properties = data.get("properties", {})
            for random_key, value in top_properties.items():
                if (
                    isinstance(value, dict)
                    and value.get("type") == "array"
                    and isinstance(value.get("items"), dict)
                    and value["items"].get("type") == "object"
                ):
                    item_props = value["items"].get("properties", {})
                    for key in item_props:
                        if key in flavors:
                            item_props[key]["enum"] = flavors[key]
                            modified = True

            if modified:
                with open(json_file, "w", encoding="utf-8") as f:
                    json.dump(data, f, indent=2, ensure_ascii=False)
                print(f"Updated: {json_file}")
