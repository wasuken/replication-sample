#!/bin/bash
set -e

# 環境変数読み込み
source .env

# 使用法表示
usage() {
    echo "使用法: $0 [read|write] [sql-command]"
    echo "例:"
n    echo "  $0 write \"INSERT INTO replication_test (message) VALUES ('test');\""
    echo "  $0 read \"SELECT * FROM replication_test LIMIT 5;\""
    exit 1
}

# パラメータチェック
if [ $# -lt 2 ]; then
    usage
fi

OPERATION=$1
SQL_COMMAND=$2

# 読み取り用スレーブを順番に選択
get_read_server() {
    local SLAVES=("mysql-slave" "mysql-slave-2")
    local COUNT_FILE="/tmp/read_counter"
    
    # カウンターファイルが存在しない場合は作成
    if [ ! -f "$COUNT_FILE" ]; then
        echo "0" > "$COUNT_FILE"
    fi
    
    # 現在のカウンター値を読み取り
    local COUNTER=$(cat "$COUNT_FILE")
    local SLAVE_COUNT=${#SLAVES[@]}
    local SELECTED_INDEX=$((COUNTER % SLAVE_COUNT))
    
    # 次のカウンター値を保存
    echo $((COUNTER + 1)) > "$COUNT_FILE"
    
    echo "${SLAVES[$SELECTED_INDEX]}"
}

# 実行
case $OPERATION in
    "write")
        echo "📝 マスターに書き込み実行..."
        docker compose exec mysql-master mysql -uroot -p"${MYSQL_ROOT_PASSWORD}" -e "USE ${MYSQL_DATABASE}; ${SQL_COMMAND}" 2>/dev/null
        echo "✅ 書き込み完了"
        ;;
    "read")
        READ_SERVER=$(get_read_server)
        echo "📖 ${READ_SERVER}から読み取り実行..."
        docker compose exec $READ_SERVER mysql -uroot -p"${MYSQL_ROOT_PASSWORD}" -e "USE ${MYSQL_DATABASE}; ${SQL_COMMAND}" 2>/dev/null
        ;;
    *)
        usage
        ;;
esac
