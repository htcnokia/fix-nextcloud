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

    // --- 改进的滚动位置记忆逻辑 ---
    const SCROLL_POS_KEY = 'nc_files_scroll_pos_v36';
    const SCROLL_PATH_KEY = 'nc_files_scroll_path_v36';
    let scrollRestorePending = false;
    let lastKnownScrollPos = 0; // ⭐ 持续记录最后的滚动位置
    
    function getScrollContainer() {
        // ⭐ 真正的滚动容器是 .files-list
        return document.querySelector('.files-list')
            || document.getElementById('app-content-files') 
            || document.querySelector('.app-content-files') 
            || document.querySelector('[data-cy-files-content]')
            || document.getElementById('content-wrapper')
            || document.querySelector('main');
    }
    
    function getCurrentPath() {
        const urlParams = new URLSearchParams(window.location.search);
        const dir = urlParams.get('dir');
        if (dir) return dir;
        
        const breadcrumb = document.querySelector('[data-cy-files-content-breadcrumbs]');
        if (breadcrumb) return breadcrumb.textContent;
        
        return window.location.pathname;
    }
    
    function saveScrollPosition() {
        const container = getScrollContainer();
        if (!container) return;
        
        // ⭐ 使用持续记录的位置，而不是当前位置（可能已被 Vue 重置）
        const scrollPos = lastKnownScrollPos > 0 ? lastKnownScrollPos : container.scrollTop;
        const currentPath = getCurrentPath();
        
        if (scrollPos > 0) { // 只有滚动位置大于 0 才保存
            localStorage.setItem(SCROLL_POS_KEY, scrollPos.toString());
            localStorage.setItem(SCROLL_PATH_KEY, currentPath);
            console.log('💾 保存滚动位置:', scrollPos, '路径:', currentPath);
        }
    }
    
    function restoreScrollPosition() {
        const savedPos = localStorage.getItem(SCROLL_POS_KEY);
        const savedPath = localStorage.getItem(SCROLL_PATH_KEY);
        const currentPath = getCurrentPath();
        
        if (!savedPos || savedPath !== currentPath) return;
        
        const container = getScrollContainer();
        if (!container) return;
        
        const targetPos = parseInt(savedPos, 10);
        
        // ⭐ 多次尝试恢复（因为 Vue 可能多次重置）
        let attempts = 0;
        const maxAttempts = 10;
        
        const tryRestore = () => {
            if (attempts >= maxAttempts) return;
            attempts++;
            
            const container = getScrollContainer();
            if (container && container.scrollHeight > targetPos) {
                container.scrollTop = targetPos;
                console.log(`📜 恢复滚动位置: ${targetPos} (尝试 ${attempts})`);
                
                // 验证是否真的设置成功
                setTimeout(() => {
                    if (container.scrollTop === targetPos) {
                        // 成功！清除保存的位置
                        localStorage.removeItem(SCROLL_POS_KEY);
                        localStorage.removeItem(SCROLL_PATH_KEY);
                        console.log('✅ 滚动位置恢复成功');
                    } else if (attempts < maxAttempts) {
                        // 失败，再试一次
                        tryRestore();
                    }
                }, 100);
            } else if (attempts < maxAttempts) {
                // 容器还没准备好，再试一次
                setTimeout(tryRestore, 200);
            }
        };
        
        // 延迟开始恢复
        setTimeout(tryRestore, 300);
    }
    
    // ⭐ 持续记录滚动位置（在 Vue 重置之前）
    function setupScrollTracking() {
        const container = getScrollContainer();
        if (!container) {
            setTimeout(setupScrollTracking, 500);
            return;
        }
        
        container.addEventListener('scroll', () => {
            lastKnownScrollPos = container.scrollTop;
        });
        
        console.log('✅ 已启动滚动位置持续追踪');
    }
    
    // 监听路径变化
    let lastPath = getCurrentPath();
    const pathCheckInterval = setInterval(() => {
        const currentPath = getCurrentPath();
        if (currentPath !== lastPath) {
            console.log('🔄 路径变化:', lastPath, '→', currentPath);
            
            // ⭐ 路径即将变化，立即保存当前位置
            saveScrollPosition();
            
            lastPath = currentPath;
            scrollRestorePending = true;
            setTimeout(() => {
                if (scrollRestorePending) {
                    restoreScrollPosition();
                    scrollRestorePending = false;
                }
            }, 800);
        }
    }, 100); // ⭐ 更频繁地检查（100ms）
    
    // 点击文件夹时也保存
    document.body.addEventListener('click', (e) => {
        const link = e.target.closest('a[href*="dir="], .files-list__row');
        if (link) {
            saveScrollPosition();
        }
    }, true);
    
    window.addEventListener('beforeunload', saveScrollPosition);
    
    // ⭐ 启动滚动追踪
    setupScrollTracking();

    // --- V36 核心：只修改显示，不排序 ---
    
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
    setTimeout(restoreScrollPosition, 500);
    
    console.log('✅ V36 已加载：精确时间显示 + 滚动记忆');
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
echo "✅ 已注入 V36：简化版 - 只修改显示"
echo ""
echo "📋 功能："
echo "   ✓ Modified 列显示精确时间（YYYY-MM-DD HH:MM:SS）"
echo "   ✓ 持续同步时间，防止不一致"
echo "   ✓ 滚动位置记忆"
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
echo "   - 切换文件夹：自动恢复滚动位置"
echo ""
echo "✨ 请执行："
echo "   1. sudo systemctl restart php-fpm (或 apache2)"
echo "   2. 浏览器 Ctrl + F5 刷新"
echo "------------------------------------------------"