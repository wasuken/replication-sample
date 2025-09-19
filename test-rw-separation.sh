#!/bin/bash
# test-rw-separation.sh
set -e

source .env

echo "🧪 読み書き分離動作テスト..."

# 1. ProxySQL経由での書き込みテスト
echo "📝 ProxySQL経由での書き込み..."
docker compose exec proxysql mysql -h127.0.0.1 -P6033 -uroot -p"${MYSQL_ROOT_PASSWORD}" -e "
USE ${MYSQL_DATABASE};
CREATE TABLE IF NOT EXISTS rw_test (
  id INT AUTO_INCREMENT PRIMARY KEY,
  operation VARCHAR(10),
  timestamp TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);
INSERT INTO rw_test (operation) VALUES ('WRITE_TEST');" 2>/dev/null

# 2. 直接マスターで確認
echo "🔍 マスターでデータ確認..."
docker compose exec mysql-master mysql -uroot -p"${MYSQL_ROOT_PASSWORD}" -e "
USE ${MYSQL_DATABASE};
SELECT COUNT(*) as master_count FROM rw_test WHERE operation = 'WRITE_TEST';" 2>/dev/null

# 3. レプリケーション同期待機
echo "⏳ レプリケーション同期待機..."
sleep 2

# 4. ProxySQL経由での読み取りテスト
echo "🔍 ProxySQL経由での読み取り..."
docker compose exec proxysql mysql -h127.0.0.1 -P6033 -uroot -p"${MYSQL_ROOT_PASSWORD}" -e "
USE ${MYSQL_DATABASE};
SELECT operation, timestamp FROM rw_test WHERE operation = 'WRITE_TEST' ORDER BY id DESC LIMIT 1;" 2>/dev/null

# 5. ルーティング統計確認
echo "📊 ProxySQL統計:"
docker compose exec proxysql mysql -h127.0.0.1 -P6032 -uadmin -padmin -e "
SELECT hostgroup, srv_host, ConnUsed, ConnFree, ConnOK, ConnERR, Queries 
FROM stats_mysql_connection_pool;" 2>/dev/null
