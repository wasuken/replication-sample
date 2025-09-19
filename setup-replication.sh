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

# スレーブリスト定義
SLAVES=("mysql-slave" "mysql-slave-2")

# 1. Binary Log Status確認
echo "📋 Master Status確認中..."
STATUS=$(docker compose exec mysql-master mysql -uroot -p"${MYSQL_ROOT_PASSWORD}" -e "SHOW BINARY LOG STATUS;" 2>/dev/null)
echo "$STATUS"

# 2. 値を抽出
LOG_FILE=$(echo "$STATUS" | grep -v "File" | awk 'NR==1 {print $1}')
LOG_POS=$(echo "$STATUS" | grep -v "File" | awk 'NR==1 {print $2}')

echo "📋 Log File: $LOG_FILE, Position: $LOG_POS"

if [ -z "$LOG_FILE" ] || [ -z "$LOG_POS" ]; then
    echo "❌ Master Status取得失敗"
    exit 1
fi

# 3. 各スレーブでレプリケーション設定
for SLAVE in "${SLAVES[@]}"; do
    echo "⏳ ${SLAVE}起動待機中..."
    until docker compose exec $SLAVE mysqladmin ping --silent 2>/dev/null; do 
        sleep 2
        echo "  - ${SLAVE}待機中..."
    done
    echo "✅ ${SLAVE}起動完了"

    # スレーブにデータベース作成
    echo "📄 ${SLAVE}に${MYSQL_DATABASE}作成中..."
    docker compose exec $SLAVE mysql -uroot -p"${MYSQL_ROOT_PASSWORD}" -e "CREATE DATABASE IF NOT EXISTS ${MYSQL_DATABASE};" 2>/dev/null

    # レプリケーション設定
    echo "🔗 ${SLAVE}レプリケーション設定中..."
    docker compose exec $SLAVE mysql -uroot -p"${MYSQL_ROOT_PASSWORD}" -e "
    STOP REPLICA;
    RESET REPLICA ALL;
    CHANGE REPLICATION SOURCE TO 
      SOURCE_HOST='mysql-master', 
      SOURCE_USER='${REPLICA_USER}', 
      SOURCE_PASSWORD='${REPLICA_PASSWORD}', 
      SOURCE_LOG_FILE='$LOG_FILE', 
      SOURCE_LOG_POS=$LOG_POS,
      GET_SOURCE_PUBLIC_KEY=1;
    START REPLICA;" 2>/dev/null

    # 動作確認
    echo "✅ ${SLAVE}レプリケーション状態確認:"
    docker compose exec $SLAVE mysql -uroot -p"${MYSQL_ROOT_PASSWORD}" -e "SHOW REPLICA STATUS\G" 2>/dev/null | grep -E "(Replica_IO_Running|Replica_SQL_Running|Last_.*Error)"
    echo ""
done

echo "✅ 全スレーブのレプリケーション設定完了"
