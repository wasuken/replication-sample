.PHONY: help up down setup test test-replication test-switching test-sync-after-switch switch permissions

help:
	@echo "MySQL Replication & Switching Commands:"
	@echo "  up                     - コンテナ起動"
	@echo "  setup                  - レプリケーション設定(複数スレーブ対応)"
	@echo "  test                   - 全テスト実行(レプリケーション→スイッチング→同期確認)"
	@echo "  test-replication       - 基本レプリケーション動作テスト"
	@echo "  test-switching         - スイッチング総合テスト"
	@echo "  test-sync-after-switch - 切り替え後の同期テスト"
	@echo "  switch                 - 手動スイッチング(mysql-slaveを新マスターに)"
	@echo "  down                   - コンテナ停止・削除"
	@echo "  logs                   - ログ表示"
	@echo "  permissions            - スクリプト実行権限付与"

up:
	@if [ ! -f .env ]; then cp .env.example .env && echo "✅ .envを作成しました"; fi
	docker compose up -d
	@echo "MySQL起動待機中..."
	@until docker compose exec mysql-master mysqladmin ping --silent 2>/dev/null; do sleep 2; done
	@echo "✅ MySQL起動完了"

setup:
	@chmod +x setup-replication.sh
	@./setup-replication.sh

test:
	@echo "🧪 全テスト実行開始..."
	@$(MAKE) test-replication
	@echo ""
	@$(MAKE) test-switching
	@echo ""
	@$(MAKE) test-sync-after-switch
	@echo "✅ 全テスト完了!"

test-replication:
	@chmod +x test-replication.sh
	@./test-replication.sh

test-switching:
	@chmod +x test-switching.sh
	@./test-switching.sh

test-sync-after-switch:
	@chmod +x test-sync-after-switch.sh
	@./test-sync-after-switch.sh

switch:
	@chmod +x promote-slave.sh
	@./promote-slave.sh mysql-slave

down:
	docker compose down -v

logs:
	docker compose logs --tail=20

permissions:
	@chmod +x *.sh
	@echo "✅ 全スクリプトに実行権限を付与しました"
