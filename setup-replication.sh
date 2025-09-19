#!/bin/bash
set -e

# .envが存在しない場合は.env.exampleから作成
if [ ! -f .env ]; then
    if [ -f .env.example ]; then
        cp .env.example .env
        echo "✅ .env.exampleから.envを作成しました"
        echo "💡 必要に応じて.envを編集してください"
    else
        echo "❌ .env.exampleが見つかりません"
        exit 1
    fi
fi

# 環境変数読み込み
source .env

echo "🔧 レプリケーション設定開始..."

# 1. Binary Log Status確認
echo "📋 Master Status確認中..."
STATUS=$(docker compose exec ${MYSQL_MASTER_HOST} mysql -uroot -p"${MYSQL_ROOT_PASSWORD}" -e "SHOW BINARY LOG STATUS;" 2>/dev/null)
echo "$STATUS"

# 2. 値を抽出
LOG_FILE=$(echo "$STATUS" | grep -v "File" | awk 'NR==1 {print $1}')
LOG_POS=$(echo "$STATUS" | grep -v "File" | awk 'NR==1 {print $2}')

echo "📋 Log File: $LOG_FILE, Position: $LOG_POS"

if [ -z "$LOG_FILE" ] || [ -z "$LOG_POS" ]; then
    echo "❌ Master Status取得失敗"
    exit 1
fi

echo "⏳ スレーブ起動待機中..."
until docker compose exec ${MYSQL_SLAVE_HOST} mysqladmin ping --silent 2>/dev/null; do 
    sleep 2
    echo "  - スレーブ待機中..."
done
echo "✅ スレーブ起動完了"

# 3. スレーブにデータベース作成
echo "📄 ${MYSQL_DATABASE}作成中..."
docker compose exec ${MYSQL_SLAVE_HOST} mysql -uroot -p"${MYSQL_ROOT_PASSWORD}" -e "CREATE DATABASE IF NOT EXISTS ${MYSQL_DATABASE};" 2>/dev/null

# 4. モニター用ユーザー作成（マスター側）
echo "👤 監視ユーザー作成中..."
docker compose exec ${MYSQL_MASTER_HOST} mysql -uroot -p"${MYSQL_ROOT_PASSWORD}" -e "
CREATE USER IF NOT EXISTS '${PROXYSQL_MONITOR_USER}'@'%' IDENTIFIED WITH caching_sha2_password BY '${PROXYSQL_MONITOR_PASSWORD}';
GRANT REPLICATION CLIENT ON *.* TO '${PROXYSQL_MONITOR_USER}'@'%';

-- ProxySQL用root権限追加
CREATE USER IF NOT EXISTS 'root'@'%' IDENTIFIED WITH caching_sha2_password BY '${MYSQL_ROOT_PASSWORD}';
GRANT ALL PRIVILEGES ON *.* TO 'root'@'%' WITH GRANT OPTION;
FLUSH PRIVILEGES;" 2>/dev/null

# 同じユーザーをスレーブ側にも作成
docker compose exec ${MYSQL_SLAVE_HOST} mysql -uroot -p"${MYSQL_ROOT_PASSWORD}" -e "
CREATE USER IF NOT EXISTS '${PROXYSQL_MONITOR_USER}'@'%' IDENTIFIED WITH caching_sha2_password BY '${PROXYSQL_MONITOR_PASSWORD}';
GRANT REPLICATION CLIENT ON *.* TO '${PROXYSQL_MONITOR_USER}'@'%';

-- ProxySQL用root権限追加  
CREATE USER IF NOT EXISTS 'root'@'%' IDENTIFIED WITH caching_sha2_password BY '${MYSQL_ROOT_PASSWORD}';
GRANT ALL PRIVILEGES ON *.* TO 'root'@'%' WITH GRANT OPTION;
FLUSH PRIVILEGES;" 2>/dev/null

# 5. レプリケーション設定
echo "🔗 レプリケーション設定中..."
docker compose exec ${MYSQL_SLAVE_HOST} mysql -uroot -p"${MYSQL_ROOT_PASSWORD}" -e "
STOP REPLICA;
RESET REPLICA ALL;
CHANGE REPLICATION SOURCE TO 
  SOURCE_HOST='${MYSQL_MASTER_HOST}', 
  SOURCE_USER='${REPLICA_USER}', 
  SOURCE_PASSWORD='${REPLICA_PASSWORD}', 
  SOURCE_LOG_FILE='$LOG_FILE', 
  SOURCE_LOG_POS=$LOG_POS,
  GET_SOURCE_PUBLIC_KEY=1;
START REPLICA;" 2>/dev/null

# 6. 動作確認
echo "✅ レプリケーション状態確認:"
docker compose exec ${MYSQL_SLAVE_HOST} mysql -uroot -p"${MYSQL_ROOT_PASSWORD}" -e "SHOW REPLICA STATUS\G" 2>/dev/null | grep -E "(Replica_IO_Running|Replica_SQL_Running|Last_.*Error)"

# 7. ProxySQLが存在する場合は待機・設定
if docker compose ps proxysql >/dev/null 2>&1; then
    # 管理ポート接続可能まで待機（タイムアウト付き）
    TIMEOUT=60
    COUNTER=0
    until docker compose exec proxysql mysql -h127.0.0.1 -P${PROXYSQL_ADMIN_PORT} -u${PROXYSQL_ADMIN_USER} -p${PROXYSQL_ADMIN_PASSWORD} -e "SELECT 1;" 2>/dev/null; do 
        sleep 2
        COUNTER=$((COUNTER + 2))
        if [ $COUNTER -ge $TIMEOUT ]; then
            echo "❌ ProxySQL起動タイムアウト (${TIMEOUT}秒)"
            echo "🔍 ProxySQLログ確認:"
            docker compose logs proxysql --tail=10
            exit 1
        fi
        echo "  - ProxySQL管理ポート待機中... (${COUNTER}/${TIMEOUT}秒)"
    done
    echo "✅ ProxySQL起動完了"
    
    # ProxySQL設定実行
    echo "🔧 ProxySQL設定中..."
    ./setup-proxysql.sh
else
    echo "ℹ️  ProxySQLが見つかりません。レプリケーションのみ設定完了"
fi

echo "✅ セットアップ完了"
