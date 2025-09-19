.PHONY: help up down setup test logs

help:
	@echo "MySQL Replication Commands:"
	@echo "  up     - コンテナ起動"
	@echo "  setup  - レプリケーション設定"
	@echo "  test   - 動作テスト"
	@echo "  down   - コンテナ停止・削除"
	@echo "  logs   - ログ表示"

up:
	@if [ ! -f .env ]; then cp .env.example .env && echo "✅ .envを作成しました"; fi
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

proxy-admin:
	@echo "📊 ProxySQL管理画面: http://localhost:6032"
	@echo "   ユーザー: admin / パスワード: admin"
