import jsonref
import os
import json

def to_plain(obj):
    """
    递归清洗 JsonRef 或其他不可序列化对象，转成普通 dict 和 list
    """
    if isinstance(obj, dict):
        return {k: to_plain(v) for k, v in obj.items()}
    elif isinstance(obj, list):
        return [to_plain(i) for i in obj]
    else:
        return obj

# 设置路径
base_path = os.path.abspath(".")
base_uri = f"file://{base_path}/"
common_path = os.path.join(base_path, "common.json")

# 加载并解析 $ref
with open(common_path, "r") as f:
    content = f.read()

resolved = jsonref.loads(content, base_uri=base_uri, jsonschema=True)

# 🔥 递归清洗掉 jsonref 的 JsonRef 对象
cleaned = to_plain(resolved)

# Scan and clean up duplicate nesting (structure properties -> X -> properties -> X）
for prop_name, prop_value in list(cleaned.get("properties", {}).items()):
    if (
        isinstance(prop_value, dict)
        and "properties" in prop_value
        and prop_name in prop_value["properties"]
    ):
        # Replacement of nested structures
        cleaned["properties"][prop_name] = prop_value["properties"][prop_name]

# Adding required fields to existing properties
cleaned["required"] = list(cleaned.get("properties", {}).keys())

# 尝试保存
with open("resolved_schema.json", "w") as f:
    json.dump(cleaned, f, indent=2)

print("✅ JSON schema resolved and saved as resolved_schema.json")
