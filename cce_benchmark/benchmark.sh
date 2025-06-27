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

  # Start of a multi-line command block
  if [[ "$trimmed" =~ ^-?[[:space:]]*command:[[:space:]]*\| ]]; then
    current_command=""
    collecting_command=1
    continue
  fi

  # Inside command block: collect lines or look for pattern
  if [[ $collecting_command -eq 1 ]]; then
    if [[ "$trimmed" =~ ^-?[[:space:]]*pattern:[[:space:]]*(.+) ]]; then
      current_pattern="${BASH_REMATCH[1]}"
      collecting_command=0

      if [[ -n "$current_command" && -n "$current_pattern" ]]; then
        ((total_commands++))
        echo "➡️  Running command #$total_commands:"
        echo "$current_command"

        # Run command and capture output
        output=$(eval "$current_command" 2>&1)
        echo "📤 Output:"
        echo "$output"

        # Match using grep for multiline compatibility
        if echo "$output" | grep -qE "$current_pattern"; then
          echo "✅ Match succeeded"
          ((success_count++))
        else
          echo "❌ Match failed"
          ((failure_count++))
          failed_checks+=("$current_command (Output: $output)")
        fi
        echo

        current_command=""
        current_pattern=""
      fi
      continue
    fi

    # Continue collecting command lines
    current_command+="$line"$'\n'
    continue
  fi
done < "$yaml_file"

# Match results summary
echo "====== Match Summary ======"
if [ ${#failed_checks[@]} -eq 0 ]; then
  echo "🎉 All commands matched successfully"
else
  echo "⚠️ The following commands did not match the pattern:"
  for fail in "${failed_checks[@]}"; do
    cmd_clean=$(echo "$fail" | tr '\n' ' ')
    echo "  - $cmd_clean"
  done
fi

# Match statistics
echo
echo "====== Match Statistics ======"
echo "📦 Total commands     : $total_commands"
echo "✅ Matches succeeded  : $success_count"
echo "❌ Matches failed     : $failure_count"

if [[ $total_commands -gt 0 ]]; then
  percent=$(awk "BEGIN { printf \"%.2f\", ($success_count/$total_commands)*100 }")
  echo "📊 Match success rate : $percent%"
fi
