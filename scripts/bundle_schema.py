import json
import jsonref

# 通用路径
input_path = "schemas/dedicated-schema.json"
output_path = "schemas/render1-schema.json"

# 加载并解析所有 $ref
with open(input_path) as f:
    schema = jsonref.load(f)

# 扫描并清理重复嵌套（结构为 properties -> X -> properties -> X）
for prop_name, prop_value in list(schema.get("properties", {}).items()):
    if (
        isinstance(prop_value, dict)
        and "properties" in prop_value
        and prop_name in prop_value["properties"]
    ):
        # 替换嵌套结构
        schema["properties"][prop_name] = prop_value["properties"][prop_name]

# 根据现有 properties 添加 required 字段
schema["required"] = list(schema.get("properties", {}).keys())

# 保存扁平化后的 schema
with open(output_path, "w") as f:
    json.dump(schema, f, indent=2)

output_path
