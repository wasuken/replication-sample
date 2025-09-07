.PHONY: help up down setup test logs

help:
	@echo "MySQL Replication Commands:"
	@echo "  up     - コンテナ起動"
	@echo "  setup  - レプリケーション自動設定"
	@echo "  test   - 動作テスト"
	@echo "  down   - コンテナ停止・削除"
	@echo "  logs   - ログ表示"

up:
	docker compose up -d
	@echo "MySQL起動待機中..."
	@until docker compose exec mysql-master mysqladmin ping --silent 2>/dev/null; do sleep 2; done
	@echo "✅ MySQL起動完了"

setup:
	@./setup-replication.sh

test:
	@./test-replication.sh

down:
	docker compose down -v

logs:
	docker compose logs --tail=20
