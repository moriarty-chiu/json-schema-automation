#!/bin/bash

yaml_file="commands.yaml"
failed_checks=()

# 临时变量用于存储当前 command 和 pattern
current_command=""
current_pattern=""

while IFS= read -r line; do
  # 移除前导空格
  line="${line#"${line%%[![:space:]]*}"}"

  # 跳过空行
  [[ -z "$line" ]] && continue

  # 如果是 command 字段
  if [[ "$line" =~ ^command:\ (.+) ]]; then
    current_command="${BASH_REMATCH[1]}"
  fi

  # 如果是 pattern 字段
  if [[ "$line" =~ ^pattern:\ (.+) ]]; then
    current_pattern="${BASH_REMATCH[1]}"

    # 当前 command 和 pattern 都存在时执行
    if [[ -n "$current_command" && -n "$current_pattern" ]]; then
      echo "➡️ 执行: $current_command"
      output=$(eval "$current_command" 2>&1)
      echo "📤 输出: $output"

      if [[ "$output" =~ $current_pattern ]]; then
        echo "✅ 匹配成功"
      else
        echo "❌ 匹配失败"
        failed_checks+=("$current_command (Output: $output)")
      fi
      echo

      # 重置
      current_command=""
      current_pattern=""
    fi
  fi

done < "$yaml_file"

# 最终结果
echo "====== 匹配结果总结 ======"
if [ ${#failed_checks[@]} -eq 0 ]; then
  echo "🎉 所有命令均匹配成功"
else
  echo "⚠️ 以下命令输出未匹配 pattern："
  for fail in "${failed_checks[@]}"; do
    echo "  - $fail"
  done
fi
