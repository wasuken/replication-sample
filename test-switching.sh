#!/bin/bash
set -e

# 環境変数読み込み
source .env

echo "🧪 MySQLスイッチング総合テスト開始..."

# 1. 初期データ挿入（マスターへ）
echo ""
echo "=== Phase 1: 初期データ挿入 ==="
./connection-switcher.sh write "INSERT INTO replication_test (message) VALUES ('Before switching - from original master');"

# 2. 全スレーブでデータ確認
echo ""
echo "=== Phase 2: 初期レプリケーション確認 ==="
SLAVES=("mysql-slave" "mysql-slave-2")
for slave in "${SLAVES[@]}"; do
    echo "📖 ${slave}からデータ読み取り:"
    ./connection-switcher.sh read "SELECT message, created_at FROM replication_test ORDER BY id DESC LIMIT 1;"
    echo ""
done

# 3. スイッチング実行
echo ""
echo "=== Phase 3: スイッチング実行 ==="
read -p "mysql-slaveを新マスターに昇格しますか？ (y/n): " -n 1 -r
echo
if [[ $REPLY =~ ^[Yy]$ ]]; then
    ./promote-slave.sh mysql-slave
else
    echo "❌ スイッチングをキャンセルしました"
    exit 1
fi

# 4. 新マスターにデータ挿入
echo ""
echo "=== Phase 4: 新マスターへのデータ挿入 ==="
echo "📝 新マスター(mysql-slave)にデータ挿入..."
docker compose exec mysql-slave mysql -uroot -p"${MYSQL_ROOT_PASSWORD}" -e "
USE ${MYSQL_DATABASE};
INSERT INTO replication_test (message) VALUES ('After switching - from new master (mysql-slave)');" 2>/dev/null

# 5. 新スレーブでデータ確認
echo ""
echo "=== Phase 5: 新構成でのレプリケーション確認 ==="
sleep 5
echo "📖 mysql-slave-2(新スレーブ)からデータ読み取り:"
docker compose exec mysql-slave-2 mysql -uroot -p"${MYSQL_ROOT_PASSWORD}" -e "
USE ${MYSQL_DATABASE};
SELECT message, created_at FROM replication_test ORDER BY id DESC LIMIT 3;" 2>/dev/null

echo ""
echo "📊 最終レプリケーション状態:"
REPLICA_STATUS=$(docker compose exec mysql-slave-2 mysql -uroot -p"${MYSQL_ROOT_PASSWORD}" -e "SHOW REPLICA STATUS\G" 2>/dev/null)

IO_RUNNING=$(echo "$REPLICA_STATUS" | grep "Replica_IO_Running:" | awk '{print $2}')
SQL_RUNNING=$(echo "$REPLICA_STATUS" | grep "Replica_SQL_Running:" | awk '{print $2}')
SECONDS_BEHIND=$(echo "$REPLICA_STATUS" | grep "Seconds_Behind_Source:" | awk '{print $2}')

echo "   Replica_IO_Running: $IO_RUNNING"
echo "   Replica_SQL_Running: $SQL_RUNNING"
echo "   Seconds_Behind_Source: $SECONDS_BEHIND"

if [ "$IO_RUNNING" = "Yes" ] && [ "$SQL_RUNNING" = "Yes" ]; then
    echo "   ✅ レプリケーション正常動作"
else
    echo "   ⚠️  レプリケーション要確認"
fi

echo ""
echo "✅ スイッチングテスト完了!"
echo "📊 現在の構成:"
echo "   マスター: mysql-slave (ポート3507)"
echo "   スレーブ: mysql-slave-2 (ポート3508)"
echo "   停止中: mysql-master (元マスター)"
