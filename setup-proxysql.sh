#!/bin/bash
set -e

# 環境変数読み込み
source .env

echo "🔧 ProxySQL設定開始..."

# ProxySQL管理コンソールへの接続確認
until docker compose exec proxysql mysql -h127.0.0.1 -P6032 -u${PROXYSQL_ADMIN_USER} -p${PROXYSQL_ADMIN_PASSWORD} -e "SELECT 1;" 2>/dev/null; do 
    echo "⏳ ProxySQL管理コンソール待機中..."
    sleep 2
done

echo "✅ ProxySQL管理コンソール接続完了"

# 1. MySQLサーバー登録
echo "🖥️  MySQLサーバー登録中..."
docker compose exec proxysql mysql -h127.0.0.1 -P6032 -u${PROXYSQL_ADMIN_USER} -p${PROXYSQL_ADMIN_PASSWORD} -e "
DELETE FROM mysql_servers;
INSERT INTO mysql_servers(hostgroup_id, hostname, port, weight, comment) VALUES
(${PROXYSQL_WRITER_HOSTGROUP}, '${MYSQL_MASTER_HOST}', ${MYSQL_PORT}, 1000, 'Master Server'),
(${PROXYSQL_READER_HOSTGROUP}, '${MYSQL_SLAVE_HOST}', ${MYSQL_PORT}, 900, 'Slave Server');
LOAD MYSQL SERVERS TO RUNTIME;
SAVE MYSQL SERVERS TO DISK;" 2>/dev/null

# 2. ユーザー登録
echo "👤 ProxySQLユーザー登録中..."
docker compose exec proxysql mysql -h127.0.0.1 -P6032 -u${PROXYSQL_ADMIN_USER} -p${PROXYSQL_ADMIN_PASSWORD} -e "
DELETE FROM mysql_users;
INSERT INTO mysql_users(username, password, default_hostgroup, max_connections, comment) VALUES
('${PROXYSQL_MYSQL_USER}', '${PROXYSQL_MYSQL_PASSWORD}', ${PROXYSQL_WRITER_HOSTGROUP}, ${PROXYSQL_MAX_CONNECTIONS}, 'Application User');
LOAD MYSQL USERS TO RUNTIME;
SAVE MYSQL USERS TO DISK;" 2>/dev/null

# 3. クエリルール設定
echo "📋 クエリルール設定中..."
docker compose exec proxysql mysql -h127.0.0.1 -P6032 -u${PROXYSQL_ADMIN_USER} -p${PROXYSQL_ADMIN_PASSWORD} -e "
DELETE FROM mysql_query_rules;
INSERT INTO mysql_query_rules(rule_id, active, match_pattern, destination_hostgroup, apply, comment) VALUES
(1, 1, '^SELECT.*FOR UPDATE', ${PROXYSQL_WRITER_HOSTGROUP}, 1, '排他SELECT → Master'),
(2, 1, '^SELECT.*LOCK IN SHARE MODE', ${PROXYSQL_WRITER_HOSTGROUP}, 1, '共有ロックSELECT → Master'),
(3, 1, '^SELECT.*', ${PROXYSQL_READER_HOSTGROUP}, 1, '通常SELECT → Slave'),
(4, 1, '^INSERT.*|^UPDATE.*|^DELETE.*|^REPLACE.*', ${PROXYSQL_WRITER_HOSTGROUP}, 1, 'DML → Master'),
(5, 1, '^BEGIN.*|^START TRANSACTION.*|^COMMIT.*|^ROLLBACK.*', ${PROXYSQL_WRITER_HOSTGROUP}, 1, 'Transaction → Master'),
(6, 1, '^SHOW.*|^DESCRIBE.*|^DESC.*|^EXPLAIN.*', ${PROXYSQL_READER_HOSTGROUP}, 1, 'Metadata → Slave'),
(7, 1, '^SET.*', ${PROXYSQL_WRITER_HOSTGROUP}, 1, 'SET → Master');
LOAD MYSQL QUERY RULES TO RUNTIME;
SAVE MYSQL QUERY RULES TO DISK;" 2>/dev/null

# 4. モニタリング設定
echo "📊 モニタリング設定中..."
docker compose exec proxysql mysql -h127.0.0.1 -P6032 -u${PROXYSQL_ADMIN_USER} -p${PROXYSQL_ADMIN_PASSWORD} -e "
SET mysql-monitor_username='${PROXYSQL_MONITOR_USER}';
SET mysql-monitor_password='${PROXYSQL_MONITOR_PASSWORD}';
SET mysql-monitor_read_only_interval=1500;
SET mysql-monitor_read_only_timeout=500;
LOAD MYSQL VARIABLES TO RUNTIME;
SAVE MYSQL VARIABLES TO DISK;" 2>/dev/null

# 5. 設定確認
echo "✅ ProxySQL設定確認:"
echo "📋 登録サーバー:"
docker compose exec proxysql mysql -h127.0.0.1 -P6032 -u${PROXYSQL_ADMIN_USER} -p${PROXYSQL_ADMIN_PASSWORD} -e "
SELECT hostgroup_id, hostname, port, status, weight, comment 
FROM mysql_servers;" 2>/dev/null

echo ""
echo "📋 クエリルール:"
docker compose exec proxysql mysql -h127.0.0.1 -P6032 -u${PROXYSQL_ADMIN_USER} -p${PROXYSQL_ADMIN_PASSWORD} -e "
SELECT rule_id, match_pattern, destination_hostgroup, comment 
FROM mysql_query_rules WHERE active=1 ORDER BY rule_id;" 2>/dev/null

echo ""
echo "📋 ユーザー:"
docker compose exec proxysql mysql -h127.0.0.1 -P6032 -u${PROXYSQL_ADMIN_USER} -p${PROXYSQL_ADMIN_PASSWORD} -e "
SELECT username, default_hostgroup, max_connections, comment 
FROM mysql_users;" 2>/dev/null

echo ""
echo "🌐 ProxySQL管理画面: http://localhost:${PROXYSQL_ADMIN_PORT}"
echo "   ユーザー: ${PROXYSQL_ADMIN_USER} / パスワード: ${PROXYSQL_ADMIN_PASSWORD}"
echo "🔌 アプリケーション接続先: localhost:${PROXYSQL_PORT}"

echo "✅ ProxySQL設定完了"
