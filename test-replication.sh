#!/bin/bash
set -e

# 環境変数読み込み
source .env

echo "🧪 レプリケーション動作テスト開始..."

# 1. マスターにテストデータ挿入
echo "📝 マスターにテストデータ挿入..."
TIMESTAMP=$(date '+%Y-%m-%d %H:%M:%S')
docker compose exec ${MYSQL_MASTER_HOST} mysql -uroot -p"${MYSQL_ROOT_PASSWORD}" -e "
USE ${MYSQL_DATABASE};
CREATE TABLE IF NOT EXISTS replication_test (
  id INT AUTO_INCREMENT PRIMARY KEY, 
  message VARCHAR(100), 
  created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);
INSERT INTO replication_test (message) VALUES ('Test from Master at $TIMESTAMP');" 2>/dev/null

# 2. 少し待機
echo "⏳ 同期待機中..."
sleep 3

# 3. スレーブでデータ確認
echo "🔍 スレーブでデータ確認:"
docker compose exec ${MYSQL_SLAVE_HOST} mysql -uroot -p"${MYSQL_ROOT_PASSWORD}" -e "
USE ${MYSQL_DATABASE};
SELECT * FROM replication_test ORDER BY id DESC LIMIT 5;" 2>/dev/null

# 4. レプリケーション状態確認
echo "📊 レプリケーション状態:"
docker compose exec ${MYSQL_SLAVE_HOST} mysql -uroot -p"${MYSQL_ROOT_PASSWORD}" -e "SHOW REPLICA STATUS\G" 2>/dev/null | grep -E "(Replica_IO_Running|Replica_SQL_Running|Seconds_Behind_Source)"

# 5. ProxySQLが存在する場合は読み書き分離テスト
if docker compose ps proxysql >/dev/null 2>&1; then
    echo ""
    echo "🧪 ProxySQL読み書き分離テスト開始..."

    # ProxySQL経由での書き込みテスト
    echo "📝 ProxySQL経由での書き込み..."
    docker compose exec proxysql mysql -h127.0.0.1 -P${PROXYSQL_PORT} -u${PROXYSQL_MYSQL_USER} -p"${PROXYSQL_MYSQL_PASSWORD}" -e "
    USE ${MYSQL_DATABASE};
    CREATE TABLE IF NOT EXISTS rw_test (
      id INT AUTO_INCREMENT PRIMARY KEY,
      operation VARCHAR(10),
      server_type VARCHAR(10),
      timestamp TIMESTAMP DEFAULT CURRENT_TIMESTAMP
    );
    INSERT INTO rw_test (operation, server_type) VALUES ('WRITE', 'PROXYSQL');" 2>/dev/null

    # レプリケーション同期待機
    echo "⏳ ProxySQL同期待機..."
    sleep 2

    # ProxySQL経由での読み取りテスト
    echo "🔍 ProxySQL経由での読み取り..."
    docker compose exec proxysql mysql -h127.0.0.1 -P${PROXYSQL_PORT} -u${PROXYSQL_MYSQL_USER} -p"${PROXYSQL_MYSQL_PASSWORD}" -e "
    USE ${MYSQL_DATABASE};
    SELECT operation, server_type, timestamp FROM rw_test WHERE operation = 'WRITE' ORDER BY id DESC LIMIT 1;" 2>/dev/null
    
    # ProxySQL統計確認
    echo "📊 ProxySQL接続統計:"
    docker compose exec proxysql mysql -h127.0.0.1 -P${PROXYSQL_ADMIN_PORT} -u${PROXYSQL_ADMIN_USER} -p${PROXYSQL_ADMIN_PASSWORD} -e "
    SELECT hostgroup, srv_host, ConnUsed, ConnFree, ConnOK, ConnERR, Queries 
    FROM stats_mysql_connection_pool;" 2>/dev/null
    
    echo "📈 ProxySQLクエリルール統計:"
    docker compose exec proxysql mysql -h127.0.0.1 -P${PROXYSQL_ADMIN_PORT} -u${PROXYSQL_ADMIN_USER} -p${PROXYSQL_ADMIN_PASSWORD} -e "
    SELECT rule_id, hits, destination_hostgroup, match_digest 
    FROM stats_mysql_query_rules ORDER BY hits DESC LIMIT 5;" 2>/dev/null
    
    echo "✅ ProxySQL読み書き分離テスト完了"
else
    echo "ℹ️  ProxySQLが見つかりません。基本レプリケーションテストのみ実行"
fi

echo "✅ テスト完了"
