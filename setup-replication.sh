#!/bin/bash
set -e

echo "🔧 レプリケーション設定開始..."

# 1. Binary Log Status確認
echo "📋 Master Status確認中..."
STATUS=$(docker compose exec mysql-master mysql -uroot -prootpassword -e "SHOW BINARY LOG STATUS;" 2>/dev/null)
echo "$STATUS"

# 2. 値を抽出
LOG_FILE=$(echo "$STATUS" | grep -v "File" | awk 'NR==1 {print $1}')
LOG_POS=$(echo "$STATUS" | grep -v "File" | awk 'NR==1 {print $2}')

echo "📋 Log File: $LOG_FILE, Position: $LOG_POS"

if [ -z "$LOG_FILE" ] || [ -z "$LOG_POS" ]; then
    echo "❌ Master Status取得失敗"
    exit 1
fi

# 3. スレーブにtestdb作成
echo "📄 testdb作成中..."
docker compose exec mysql-slave mysql -uroot -prootpassword -e "CREATE DATABASE IF NOT EXISTS testdb;" 2>/dev/null

# 4. レプリケーション設定
echo "🔗 レプリケーション設定中..."
docker compose exec mysql-slave mysql -uroot -prootpassword -e "
STOP REPLICA;
RESET REPLICA ALL;
CHANGE REPLICATION SOURCE TO 
  SOURCE_HOST='mysql-master', 
  SOURCE_USER='replica', 
  SOURCE_PASSWORD='replica_password', 
  SOURCE_LOG_FILE='$LOG_FILE', 
  SOURCE_LOG_POS=$LOG_POS,
  GET_SOURCE_PUBLIC_KEY=1;
START REPLICA;" 2>/dev/null

# 5. 動作確認
echo "✅ レプリケーション状態確認:"
docker compose exec mysql-slave mysql -uroot -prootpassword -e "SHOW REPLICA STATUS\G" 2>/dev/null | grep -E "(Replica_IO_Running|Replica_SQL_Running|Last_.*Error)"

echo "✅ レプリケーション設定完了"
