import json
import jsonref

# Common Path
input_path = "schemas/dedicated-schema.json"
output_path = "schemas/render1-schema.json"

# Load and parse all $ref
with open(input_path) as f:
    schema = jsonref.load(f)

# Scan and clean up duplicate nesting (structure properties -> X -> properties -> X）
for prop_name, prop_value in list(schema.get("properties", {}).items()):
    if (
        isinstance(prop_value, dict)
        and "properties" in prop_value
        and prop_name in prop_value["properties"]
    ):
        # Replacement of nested structures
        schema["properties"][prop_name] = prop_value["properties"][prop_name]

# Adding required fields to existing properties
schema["required"] = list(schema.get("properties", {}).keys())

# Save the flattened schema
with open(output_path, "w") as f:
    json.dump(schema, f, indent=2)

