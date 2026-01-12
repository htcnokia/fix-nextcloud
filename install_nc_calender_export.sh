#!/bin/bash

NC_PATH="/var/www/nextcloud"
APP_NAME="calendar_csv_export"
APP_PATH="${NC_PATH}/apps/${APP_NAME}"

# 1. 彻底清理并重新创建所有必需目录
sudo rm -rf ${APP_PATH}
mkdir -p ${APP_PATH}/{appinfo,lib/Controller,lib/AppInfo,js}

# 2. 创建 info.xml
cat <<EOF > ${APP_PATH}/appinfo/info.xml
<?xml version="1.0"?>
<info xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance" xsi:noNamespaceSchemaLocation="https://schema.nextcloud.com/info.xsd">
    <id>${APP_NAME}</id>
    <name>Excel Calendar Export</name>
    <summary>Adds Export to Excel button to Calendar UI</summary>
    <version>2.0.1</version>
    <licence>agpl</licence>
    <author>Internal Tool</author>
    <namespace>CalendarCsvExport</namespace>
    <category>office</category>
    <dependencies>
        <nextcloud min-version="25" max-version="35"/>
    </dependencies>
</info>
EOF

# 3. 创建 routes.php
cat <<EOF > ${APP_PATH}/appinfo/routes.php
<?php
return ['routes' => [['name' => 'export#index', 'url' => '/export/{calendarId}', 'verb' => 'GET']]];
EOF

# 4. 创建 Application.php (注入 JS)
cat <<EOF > ${APP_PATH}/lib/AppInfo/Application.php
<?php
namespace OCA\CalendarCsvExport\AppInfo;
use OCP\AppFramework\App;
use OCP\Util;
class Application extends App {
    public function __construct() {
        parent::__construct('calendar_csv_export');
        Util::addScript('calendar_csv_export', 'script');
    }
}
EOF

# 5. 创建前端 JS (script.js)
cat <<EOF > ${APP_PATH}/js/script.js
(function() {
    setInterval(function() {
        // 1. 处理日历编辑弹窗
        const modal = document.querySelector('.edit-calendar-modal');
        if (modal) {
            const actions = modal.querySelector('.edit-calendar-modal__actions');
            if (actions && !actions.querySelector('.export-excel-btn')) {
                const nativeExportBtn = actions.querySelector('a[href*="export"]');
                const saveBtn = actions.querySelector('.button-vue--vue-secondary'); // 保存按钮
                
                if (nativeExportBtn) {
                    const href = nativeExportBtn.getAttribute('href');
                    const parts = href.split('/');
                    const calId = parts[parts.length - 2] || '-';

                    const excelBtn = document.createElement('a');
                    excelBtn.href = '/index.php/apps/calendar_csv_export/export/' + calId;
                    excelBtn.className = 'button-vue button-vue--size-normal button-vue--icon-and-text button-vue--vue-tertiary button-vue--tertiary export-excel-btn';
                    excelBtn.style.color = '#0082c9'; // 使用 Nextcloud 标准蓝色
                    excelBtn.style.marginRight = '4px';
                    excelBtn.style.transform = 'translateY(8px)';
                    
                    excelBtn.innerHTML = \`
                        <span class="button-vue__wrapper">
                            <span class="button-vue__text">📊 导出 CSV</span>
                        </span>\`;
                    
                    // 插入到“保存”按钮之前，也就是“导出”按钮之后
                    if (saveBtn) {
                        actions.insertBefore(excelBtn, saveBtn);
                    } else {
                        actions.appendChild(excelBtn);
                    }
                }
            }
        }
    }, 1000);
})();
EOF


# 6. 创建控制器 ExportController.php
cat <<EOF > ${APP_PATH}/lib/Controller/ExportController.php
<?php
namespace OCA\CalendarCsvExport\Controller;

use OCP\AppFramework\Controller;
use OCP\IRequest;
use OCP\IDBConnection;
use OCP\IUserSession;
use OCP\AppFramework\Http\StreamResponse;
use Sabre\VObject\Reader;

class ExportController extends Controller {
    private \$db;
    private \$userSession;

    public function __construct(\$appName, IRequest \$request, IDBConnection \$db, IUserSession \$userSession) {
        parent::__construct(\$appName, \$request);
        \$this->db = \$db;
        \$this->userSession = \$userSession;
    }

    /**
     * @NoAdminRequired
     * @NoCSRFRequired
     */
    public function index(\$calendarId) {
        try {
            \$user = \$this->userSession->getUser();
            \$userId = \$user->getUID();
            \$principal = 'principals/users/' . \$userId;

            \$query = \$this->db->getQueryBuilder();
            \$query->select('*')->from('calendars')->where(\$query->expr()->eq('principaluri', \$query->createNamedParameter(\$principal)));
            \$calendars = \$query->execute()->fetchAll();
            
            \$targetId = null;
            \$displayName = 'Calendar';
            foreach (\$calendars as \$cal) {
                if (\$cal['uri'] === \$calendarId || (!\$targetId && \$calendarId === '-')) {
                    \$targetId = \$cal['id'];
                    \$displayName = \$cal['displayname'];
                    if (\$cal['uri'] === \$calendarId) break;
                }
            }

            \$query = \$this->db->getQueryBuilder();
            \$query->select('calendardata')->from('calendarobjects')->where(\$query->expr()->eq('calendarid', \$query->createNamedParameter(\$targetId)));
            \$eventsResult = \$query->execute();

            \$fp = fopen('php://temp', 'r+');
            // 关键：写入 UTF-8 BOM，防止 Excel 打开乱码
            fwrite(\$fp, "\xEF\xBB\xBF");
            
            fputcsv(\$fp, ['日历', '主题', '开始时间', '结束时间', '地点', '分类', '状态', '说明', '全天']);

            while (\$row = \$eventsResult->fetch()) {
                try {
                    \$vObject = Reader::read(\$row['calendardata']);
                    if (isset(\$vObject->VEVENT)) {
                        foreach (\$vObject->VEVENT as \$vevent) {
                            // 处理全天事件
                            \$isAllDay = (isset(\$vevent->DTSTART) && !\$vevent->DTSTART->hasTime()) ? '是' : '否';
                            
                            fputcsv(\$fp, [
                                \$displayName,
                                (string)\$vevent->SUMMARY,
                                \$vevent->DTSTART->getDateTime()->format('Y-m-d H:i'),
                                \$vevent->DTEND->getDateTime()->format('Y-m-d H:i'),
                                (string)\$vevent->LOCATION,
                                (string)\$vevent->CATEGORIES,
                                (string)\$vevent->STATUS,
                                // 清理说明中的换行符，防止 CSV 错位，但保留空格
                                str_replace(["\r", "\n"], " ", (string)\$vevent->DESCRIPTION),
                                \$isAllDay
                            ]);
                        }
                    }
                } catch (\Exception \$e) {}
            }

            rewind(\$fp);
            \$response = new StreamResponse(\$fp);
            \$response->addHeader('Content-Type', 'text/csv; charset=utf-8');
            \$response->addHeader('Content-Disposition', 'attachment; filename="' . urlencode(\$displayName) . '.csv"');
            return \$response;

        } catch (\Exception \$e) {
            return new \OCP\AppFramework\Http\JSONResponse(['error' => \$e->getMessage()], 500);
        }
    }
}
EOF

# 修正权限
chown -R www-data:www-data ${APP_PATH}
echo "应用目录已准备好。"
sudo -u www-data php ${NC_PATH}/occ app:enable ${APP_NAME}