#!/bin/bash
set -e

# 環境変数読み込み
source .env

# 使用法表示
usage() {
    echo "使用法: $0 <new-master-name>"
    echo "例: $0 mysql-slave"
    echo "利用可能なスレーブ: mysql-slave, mysql-slave-2"
    exit 1
}

# パラメータチェック
if [ $# -ne 1 ]; then
    usage
fi

NEW_MASTER=$1
AVAILABLE_SLAVES=("mysql-slave" "mysql-slave-2")

# 指定されたスレーブが有効かチェック
if [[ ! " ${AVAILABLE_SLAVES[@]} " =~ " ${NEW_MASTER} " ]]; then
    echo "❌ 無効なスレーブ名: $NEW_MASTER"
    usage
fi

# 他のスレーブを特定
OTHER_SLAVES=()
for slave in "${AVAILABLE_SLAVES[@]}"; do
    if [ "$slave" != "$NEW_MASTER" ]; then
        OTHER_SLAVES+=("$slave")
    fi
done

echo "🔄 スイッチング開始: ${NEW_MASTER}を新マスターに昇格"

# 1. 現在のマスターを停止
echo "⏹️  現在のマスター(mysql-master)を停止..."
docker compose stop mysql-master

# 2. 新マスターでレプリケーションを停止し、書き込み可能にする
echo "🔧 ${NEW_MASTER}をマスターモードに変更..."
docker compose exec $NEW_MASTER mysql -uroot -p"${MYSQL_ROOT_PASSWORD}" -e "
STOP REPLICA;
RESET REPLICA ALL;
SET GLOBAL read_only = 0;" 2>/dev/null

# 3. 新マスターでバイナリログの状態を確認
echo "📋 新マスター(${NEW_MASTER})のバイナリログ状態確認..."
STATUS=$(docker compose exec $NEW_MASTER mysql -uroot -p"${MYSQL_ROOT_PASSWORD}" -e "SHOW BINARY LOG STATUS;" 2>/dev/null)
echo "$STATUS"

LOG_FILE=$(echo "$STATUS" | grep -v "File" | awk 'NR==1 {print $1}')
LOG_POS=$(echo "$STATUS" | grep -v "File" | awk 'NR==1 {print $2}')

echo "📋 新マスター Log File: $LOG_FILE, Position: $LOG_POS"

# 4. 他のスレーブを新マスターに向ける
for slave in "${OTHER_SLAVES[@]}"; do
    echo "🔗 ${slave}を新マスター(${NEW_MASTER})に接続..."
    docker compose exec $slave mysql -uroot -p"${MYSQL_ROOT_PASSWORD}" -e "
    STOP REPLICA;
    RESET REPLICA ALL;
    CHANGE REPLICATION SOURCE TO 
      SOURCE_HOST='${NEW_MASTER}', 
      SOURCE_USER='${REPLICA_USER}', 
      SOURCE_PASSWORD='${REPLICA_PASSWORD}', 
      SOURCE_LOG_FILE='$LOG_FILE', 
      SOURCE_LOG_POS=$LOG_POS,
      GET_SOURCE_PUBLIC_KEY=1;
    START REPLICA;" 2>/dev/null
    
    echo "✅ ${slave}の新レプリケーション状態:"
    docker compose exec $slave mysql -uroot -p"${MYSQL_ROOT_PASSWORD}" -e "SHOW REPLICA STATUS\G" 2>/dev/null | grep -E "(Replica_IO_Running|Replica_SQL_Running)"
done

echo ""
echo "✅ スイッチング完了!"
echo "📊 新マスター: ${NEW_MASTER}"
echo "📊 スレーブ: ${OTHER_SLAVES[*]}"
echo "⚠️  注意: 元のmysql-masterコンテナは停止状態です"
