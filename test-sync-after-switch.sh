#!/bin/bash
set -e

# 環境変数読み込み
source .env

echo "🔄 切り替え後の同期テスト開始..."

# 現在の構成確認
echo "📊 現在の構成確認:"
if docker compose ps mysql-master | grep -q "Up"; then
    echo "   マスター: mysql-master (稼働中)"
    CURRENT_MASTER="mysql-master"
    SLAVES=("mysql-slave" "mysql-slave-2")
else
    echo "   マスター: mysql-slave (新マスター)"
    CURRENT_MASTER="mysql-slave"
    SLAVES=("mysql-slave-2")
fi

echo "   スレーブ: ${SLAVES[*]}"
echo ""

# 1. 新マスターにテストデータ連続挿入
echo "=== Phase 1: 新マスターに複数データ挿入 ==="
for i in {1..3}; do
    TIMESTAMP=$(date '+%Y-%m-%d %H:%M:%S')
    echo "📝 データ $i 挿入中..."
    docker compose exec $CURRENT_MASTER mysql -uroot -p"${MYSQL_ROOT_PASSWORD}" -e "
    USE ${MYSQL_DATABASE};
    INSERT INTO replication_test (message) VALUES ('Sync test $i - from $CURRENT_MASTER at $TIMESTAMP');" 2>/dev/null
    sleep 1
done

# 2. 同期待機
echo ""
echo "=== Phase 2: 同期待機 ==="
echo "⏳ 5秒待機中..."
sleep 5

# 3. 各スレーブで同期確認
echo ""
echo "=== Phase 3: 各スレーブでの同期確認 ==="
for slave in "${SLAVES[@]}"; do
    echo "🔍 ${slave}でデータ確認:"
    docker compose exec $slave mysql -uroot -p"${MYSQL_ROOT_PASSWORD}" -e "
    USE ${MYSQL_DATABASE};
    SELECT message, created_at FROM replication_test 
    WHERE message LIKE 'Sync test%' 
    ORDER BY id DESC;" 2>/dev/null
    
    echo ""
    echo "📊 ${slave}のレプリケーション状態:"
    REPLICA_STATUS=$(docker compose exec $slave mysql -uroot -p"${MYSQL_ROOT_PASSWORD}" -e "SHOW REPLICA STATUS\G" 2>/dev/null)
    
    IO_RUNNING=$(echo "$REPLICA_STATUS" | grep "Replica_IO_Running:" | awk '{print $2}')
    SQL_RUNNING=$(echo "$REPLICA_STATUS" | grep "Replica_SQL_Running:" | awk '{print $2}')
    SECONDS_BEHIND=$(echo "$REPLICA_STATUS" | grep "Seconds_Behind_Source:" | awk '{print $2}')
    
    if [ "$IO_RUNNING" = "Yes" ] && [ "$SQL_RUNNING" = "Yes" ]; then
        echo "   ✅ レプリケーション正常 (遅延: ${SECONDS_BEHIND}秒)"
    else
        echo "   ❌ レプリケーション異常 (IO: $IO_RUNNING, SQL: $SQL_RUNNING)"
    fi
    echo ""
done

# 4. データ件数比較
echo "=== Phase 4: データ件数比較 ==="
echo "📊 マスター(${CURRENT_MASTER})のレコード数:"
MASTER_COUNT=$(docker compose exec $CURRENT_MASTER mysql -uroot -p"${MYSQL_ROOT_PASSWORD}" -e "
USE ${MYSQL_DATABASE};
SELECT COUNT(*) as count FROM replication_test;" 2>/dev/null | grep -v count | tail -1)
echo "   件数: $MASTER_COUNT"

for slave in "${SLAVES[@]}"; do
    echo "📊 ${slave}のレコード数:"
    SLAVE_COUNT=$(docker compose exec $slave mysql -uroot -p"${MYSQL_ROOT_PASSWORD}" -e "
    USE ${MYSQL_DATABASE};
    SELECT COUNT(*) as count FROM replication_test;" 2>/dev/null | grep -v count | tail -1)
    echo "   件数: $SLAVE_COUNT"
    
    if [ "$MASTER_COUNT" = "$SLAVE_COUNT" ]; then
        echo "   ✅ 件数一致"
    else
        echo "   ❌ 件数不一致 (マスター: $MASTER_COUNT, スレーブ: $SLAVE_COUNT)"
    fi
done

echo ""
echo "✅ 切り替え後同期テスト完了!"
