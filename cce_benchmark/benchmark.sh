#!/bin/bash

yaml_file="commands.yaml"
failed_checks=()
total_commands=0
success_count=0
failure_count=0

current_command=""
current_pattern=""
collecting_command=0

while IFS= read -r line || [ -n "$line" ]; do
  trimmed="${line#"${line%%[![:space:]]*}"}"
  [[ -z "$trimmed" || "$trimmed" =~ ^# ]] && continue

  # Multiple lines command start
  if [[ "$trimmed" =~ ^-?[[:space:]]*command:\ *\| ]]; then
    current_command=""
    collecting_command=1
    continue
  fi

  # Multi-line command collection
  if [[ $collecting_command -eq 1 ]]; then
    if [[ "$trimmed" =~ ^-?[[:space:]]*pattern:[[:space:]](.+) ]]; then
      current_pattern="${BASH_REMATCH[1]}"
      collecting_command=0

      # Execute complete command
      if [[ -n "$current_command" && -n "$current_pattern" ]]; then
        ((total_commands++))
        echo "➡️ Execution:"
        echo "$current_command"
        output=$(eval "$current_command" 2>&1)
        echo "📤 Output:"
        echo "$output"

        if [[ "$output" =~ $current_pattern ]]; then
          echo "✅ Match successful"
          ((success_count++))
        else
          echo "❌ Matching failed"
          ((failure_count++))
          failed_checks+=("$current_command (Output: $output)")
        fi
        echo

        current_command=""
        current_pattern=""
      fi
      continue
    fi

    # Continue collecting command content
    current_command+="$line"$'\n'
    continue
  fi
done < "$yaml_file"

# Match Failure Summary
echo "====== Summary of matching results ======"

if [ ${#failed_checks[@]} -eq 0 ]; then
  echo "🎉 All commands matched successfully."
else
  echo "⚠️ The following commands did not pass regular expression matching: "
  for fail in "${failed_checks[@]}"; do
    # Replace multi-line display
    cmd_clean=$(echo "$fail" | tr '\n' ' ')
    echo "  - $cmd_clean"
  done
fi

# ✅ Statistical information output
echo
echo "====== Matching statistics ======"
echo "📦 Total number of commands: $total_commands"
echo "✅ Number of successful matches: $success_count"
echo "❌ Number of failed matches: $failure_count"

# 可选成功率
if [[ $total_commands -gt 0 ]]; then
  percent=$(awk "BEGIN { printf \"%.2f\", ($success_count/$total_commands)*100 }")
  echo "📊 matching success rate: $percent%"
fi
