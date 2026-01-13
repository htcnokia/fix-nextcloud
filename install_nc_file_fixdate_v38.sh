#!/bin/bash

NC_PATH="/var/www/nextcloud"
LAYOUT_FILE="$NC_PATH/core/templates/layout.user.php"
BACKUP_DIR="$NC_PATH/backups"
GOLDEN_BACKUP="$BACKUP_DIR/layout.user.php.original_gold"
INJECT_TEMP="/tmp/nc_inject_temp.php"

sudo mkdir -p "$BACKUP_DIR"

# --- 1. 智能备份逻辑 ---
if [ ! -f "$GOLDEN_BACKUP" ]; then
    echo "首次运行：正在创建原始黄金备份..."
    sudo cp "$LAYOUT_FILE" "$GOLDEN_BACKUP"
else
    echo "检测到历史备份，正在从原始黄金备份恢复干净环境..."
    sudo cp "$GOLDEN_BACKUP" "$LAYOUT_FILE"
    sudo sed -i -e '$d' -e '$d' "$LAYOUT_FILE"
    echo "</body></html>" | sudo tee -a "$LAYOUT_FILE" > /dev/null
fi

# --- 2. 构建最终方案（V36 - 只修改显示）---
cat <<'EOF' > "$INJECT_TEMP"
<?php if ($_['appid'] === 'files'): ?>
<style nonce="<?php p($_['cspNonce']); ?>">
    /* V36 CSS: 扩大 Modified 列宽度 */
    .files-list__column.files-list__row-mtime {
        flex: 0 0 200px !important;
        min-width: 200px !important;
        max-width: 200px !important;
    }
    
    .files-list__row .files-list__row-mtime {
        flex: 0 0 200px !important;
        min-width: 200px !important;
        max-width: 200px !important;
    }
    
    /* 精确时间显示：隐藏相对时间，用精确时间替换 */
    .files-list__row-mtime .nc-datetime {
        visibility: hidden;
        position: relative;
        display: block;
        width: 100%;
    }
    
    .files-list__row-mtime .nc-datetime::after {
        content: attr(data-exact-time);
        visibility: visible;
        position: absolute;
        left: 0;
        top: 0;
        font-size: 13px;
        color: var(--color-text-maxcontrast);
        font-family: monospace;
        white-space: nowrap;
    }
</style>
<script nonce="<?php p($_['cspNonce']); ?>">
(function() {
    'use strict';

    // --- V38 核心：只修改显示，不排序 ---
    
    function formatTimestamp(date) {
        return date.getFullYear() + '-' + 
               String(date.getMonth() + 1).padStart(2, '0') + '-' +
               String(date.getDate()).padStart(2, '0') + ' ' +
               String(date.getHours()).padStart(2, '0') + ':' +
               String(date.getMinutes()).padStart(2, '0') + ':' +
               String(date.getSeconds()).padStart(2, '0');
    }

    function updateTimeDisplay() {
        const rows = document.querySelectorAll('.files-list__row');
        
        rows.forEach(row => {
            const timeSpan = row.querySelector('.files-list__row-mtime [data-timestamp]');
            if (!timeSpan) return;
            
            // 读取最新的 data-timestamp
            const timestamp = timeSpan.getAttribute('data-timestamp');
            if (!timestamp) return;
            
            const date = new Date(timestamp);
            if (isNaN(date.getTime())) return;
            
            const exactTime = formatTimestamp(date);
            const currentExactTime = timeSpan.getAttribute('data-exact-time');
            
            // 只有时间真的变化了才更新
            if (currentExactTime !== exactTime) {
                timeSpan.setAttribute('data-exact-time', exactTime);
                timeSpan.setAttribute('title', exactTime);
            }
        });
    }

    // 持续监控并更新时间显示
    const observer = new MutationObserver(() => {
        updateTimeDisplay();
    });
    
    observer.observe(document.body, { 
        childList: true, 
        subtree: true,
        attributes: true,
        attributeFilter: ['data-timestamp']
    });
    
    // 定期强制同步（防止漏掉）
    setInterval(updateTimeDisplay, 2000);
    
    // 初始化
    updateTimeDisplay();

    console.log('✅ V38 已加载：精确时间显示');
    console.log('💡 点击 Modified 列使用 NextCloud 原生排序');
})();
</script>
<?php endif; ?>
EOF

# --- 3. 执行注入 ---
sudo sed -i -e '$d' -e '$d' "$LAYOUT_FILE"
sudo cat "$INJECT_TEMP" | sudo tee -a "$LAYOUT_FILE" > /dev/null
echo "</body>" | sudo tee -a "$LAYOUT_FILE" > /dev/null
echo "</html>" | sudo tee -a "$LAYOUT_FILE" > /dev/null
rm "$INJECT_TEMP"

echo "------------------------------------------------"
echo "✅ 已注入 V38：简化版 - 只修改显示"
echo ""
echo "📋 功能："
echo "   ✓ Modified 列显示精确时间（YYYY-MM-DD HH:MM:SS）"
echo "   ✓ 持续同步时间，防止不一致"
echo "   ✓ 不干预排序逻辑"
echo ""
echo "🎯 工作方式："
echo "   - 显示：精确时间替代相对时间"
echo "   - 排序：使用 NextCloud 原生排序"
echo "   - 优点：简单、稳定、不受虚拟滚动影响"
echo ""
echo "💡 使用说明："
echo "   - 查看文件：显示精确的修改时间"
echo "   - 点击 Modified 列：NextCloud 按其内部数据排序"
echo ""
echo "✨ 请执行："
echo "   1. sudo systemctl restart php8.4-fpm  apache2 "
echo "   2. 浏览器 Ctrl + F5 刷新"
echo "------------------------------------------------"