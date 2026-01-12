#!/bin/bash

NC_PATH="/var/www/nextcloud"
LAYOUT_FILE="$NC_PATH/core/templates/layout.user.php"
BACKUP_DIR="$NC_PATH/backups"
GOLDEN_BACKUP="$BACKUP_DIR/layout.user.php.original_gold"

if [ -f "$GOLDEN_BACKUP" ]; then
    echo "正在从原始黄金备份恢复干净环境..."
    sudo cp "$GOLDEN_BACKUP" "$LAYOUT_FILE"
    echo "✅ NextCloud 已恢复到原始状态。"
    echo "✨ 请执行 Ctrl + F5 强制刷新查看效果。"
else
    echo "错误：未找到黄金备份文件 $GOLDEN_BACKUP。"
    echo "请手动检查 $LAYOUT_FILE 文件。"
fi
