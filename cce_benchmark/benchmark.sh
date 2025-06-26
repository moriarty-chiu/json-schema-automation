#!/bin/bash

yaml_file="commands.yaml"
failed_checks=()

current_command=""
current_pattern=""
collecting_command=0

while IFS= read -r line || [ -n "$line" ]; do
  # 去除前导空格
  trimmed="${line#"${line%%[![:space:]]*}"}"

  # 忽略空行
  [[ -z "$trimmed" ]] && continue

  # 开始处理 command 块（多行支持）
  if [[ "$trimmed" =~ ^-?[[:space:]]*command:\ *\| ]]; then
    current_command=""
    collecting_command=1
    continue
  fi

  # 如果在 command 多行模式中
  if [[ $collecting_command -eq 1 ]]; then
    # 如果下一行为 pattern: 则 command 结束
    if [[ "$trimmed" =~ ^-?[[:space:]]*pattern:[[:space:]](.+) ]]; then
      current_pattern="${BASH_REMATCH[1]}"
      collecting_command=0

      # 执行命令
      if [[ -n "$current_command" && -n "$current_pattern" ]]; then
        echo "➡️ 执行:"
        echo "$current_command"
        output=$(eval "$current_command" 2>&1)
        echo "📤 输出:"
        echo "$output"

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
      continue
    fi

    # 否则继续收集 command 行
    current_command+="$line"$'\n'
    continue
  fi
done < "$yaml_file"

# 最终总结
echo "====== 匹配结果总结 ======"
if [ ${#failed_checks[@]} -eq 0 ]; then
  echo "🎉 所有命令均匹配成功"
else
  echo "⚠️ 以下命令未通过正则匹配："
  for fail in "${failed_checks[@]}"; do
    echo "  - $fail"
  done
fi
