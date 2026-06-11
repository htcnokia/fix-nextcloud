#!/bin/bash

NC_PATH="/var/www/nextcloud"
LAYOUT_FILE="$NC_PATH/core/templates/layout.user.php"

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
BACKUP_DIR="$SCRIPT_DIR/backups"
GOLDEN_BACKUP="$BACKUP_DIR/layout.user.php.original_gold"
INJECT_TEMP="/tmp/nc_inject_temp.php"

sudo mkdir -p "$BACKUP_DIR"

echo "================================================"
echo "Nextcloud NC34 精确时间补丁 V39.1"
echo "================================================"

# ---------- 恢复干净文件 ----------
if [ ! -f "$GOLDEN_BACKUP" ]; then
    echo "首次运行：创建黄金备份"
    sudo cp "$LAYOUT_FILE" "$GOLDEN_BACKUP"
else
    echo "恢复黄金备份"
    sudo cp "$GOLDEN_BACKUP" "$LAYOUT_FILE"
fi

# ---------- 注入内容 ----------
cat <<'EOF' > "$INJECT_TEMP"
<?php if ($_['appid'] === 'files'): ?>
<style nonce="<?php p($_['cspNonce']); ?>">

/* =======================================================
   NC34 文件列表时间列修复
   ======================================================= */

/* 表头列 */
th.files-list__column.files-list__row-mtime {
    width: 210px !important;
    min-width: 210px !important;
    max-width: 210px !important;
}

/* 内容列 */
td.files-list__row-mtime {
    width: 210px !important;
    min-width: 210px !important;
    max-width: 210px !important;
}

/* 表头按钮 */
.files-list__column-sort-button {
    width: 100% !important;
}

/* 时间文本 */
.files-list__row-mtime .nc-datetime {
    font-family: monospace !important;
    white-space: nowrap !important;
    overflow: hidden;
    text-overflow: ellipsis;
    font-size: 13px;
}

/* 防止Vue重新计算宽度 */
.files-list__table th.files-list__row-mtime,
.files-list__table td.files-list__row-mtime {
    flex: none !important;
}

</style>

<script nonce="<?php p($_['cspNonce']); ?>">
(function () {
    'use strict';

    function formatTimestamp(date) {
        return date.getFullYear() + '-' +
            String(date.getMonth() + 1).padStart(2, '0') + '-' +
            String(date.getDate()).padStart(2, '0') + ' ' +
            String(date.getHours()).padStart(2, '0') + ':' +
            String(date.getMinutes()).padStart(2, '0') + ':' +
            String(date.getSeconds()).padStart(2, '0');
    }

    function updateTimeDisplay() {

        document
            .querySelectorAll('.files-list__row-mtime .nc-datetime')
            .forEach(el => {

                const rawTimestamp = el.getAttribute('data-timestamp');

                if (!rawTimestamp) {
                    return;
                }

                const date = new Date(rawTimestamp);

                if (isNaN(date.getTime())) {
                    return;
                }

                const exactTime = formatTimestamp(date);

                if (el.dataset.exactTime !== exactTime) {

                    el.dataset.exactTime = exactTime;

                    el.textContent = exactTime;

                    el.title = exactTime;
                }
            });
    }

    const observer = new MutationObserver(() => {
        updateTimeDisplay();
    });

    observer.observe(document.body, {
        childList: true,
        subtree: true
    });

    updateTimeDisplay();

    setInterval(updateTimeDisplay, 2000);

    console.log('✅ NC34 V39.1 精确时间补丁已加载');
})();
</script>
<?php endif; ?>
EOF

# ---------- 删除原结尾 ----------
sudo sed -i '$d' "$LAYOUT_FILE"
sudo sed -i '$d' "$LAYOUT_FILE"

# ---------- 注入 ----------
sudo cat "$INJECT_TEMP" >> "$LAYOUT_FILE"

echo "</body>" | sudo tee -a "$LAYOUT_FILE" >/dev/null
echo "</html>" | sudo tee -a "$LAYOUT_FILE" >/dev/null

rm -f "$INJECT_TEMP"

echo
echo "================================================"
echo "补丁安装完成"
echo "================================================"
echo
echo "执行以下命令："
echo
echo "sudo systemctl restart php8.4-fpm"
echo
echo "然后浏览器执行："
echo
echo "Ctrl + F5"
echo
echo