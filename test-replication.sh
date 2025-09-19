#!/bin/bash
set -e

# 環境変数読み込み
source .env

echo "🧪 複数スレーブ レプリケーション動作テスト開始..."

# スレーブリスト定義
SLAVES=("mysql-slave" "mysql-slave-2")

# 1. マスターにテストデータ挿入
echo "📝 マスターにテストデータ挿入..."
TIMESTAMP=$(date '+%Y-%m-%d %H:%M:%S')
docker compose exec mysql-master mysql -uroot -p"${MYSQL_ROOT_PASSWORD}" -e "
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

# 3. 各スレーブでデータ確認
for SLAVE in "${SLAVES[@]}"; do
    echo "🔍 ${SLAVE}でデータ確認:"
    docker compose exec $SLAVE mysql -uroot -p"${MYSQL_ROOT_PASSWORD}" -e "
    USE ${MYSQL_DATABASE};
    SELECT * FROM replication_test ORDER BY id DESC LIMIT 3;" 2>/dev/null
    
    echo "📊 ${SLAVE}レプリケーション状態:"
    docker compose exec $SLAVE mysql -uroot -p"${MYSQL_ROOT_PASSWORD}" -e "SHOW REPLICA STATUS\G" 2>/dev/null | grep -E "(Replica_IO_Running|Replica_SQL_Running|Seconds_Behind_Source)"
    echo ""
done

echo "✅ 全スレーブテスト完了"
