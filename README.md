# MySQL レプリケーション & スイッチング環境

Docker Composeを使用したMySQLレプリケーション環境構築と手動スイッチング機能の学習プロジェクト。

## 🚀 クイックスタート

```bash
# 1. リポジトリクローン
git clone <このリポジトリ>
cd mysql-replication

# 2. 環境起動
make up

# 3. レプリケーション設定
make setup

# 4. 全テスト実行
make test
```

## 📋 機能概要

### 基本構成
- **マスターサーバー**: `mysql-master` (ポート3506)
- **スレーブサーバー**: `mysql-slave` (ポート3507)
- **スレーブサーバー**: `mysql-slave-2` (ポート3508)

### 主要機能
- ✅ Master-Slave レプリケーション
- ✅ 複数スレーブ対応
- ✅ 手動スイッチング（フェイルオーバー）
- ✅ 読み取り負荷分散
- ✅ 自動テスト機能

## 🛠️ コマンド一覧

### 基本操作
```bash
make up           # 環境起動
make setup        # レプリケーション設定
make down         # 環境停止・削除
make logs         # ログ表示
make permissions  # スクリプト実行権限付与
```

### テスト
```bash
make test                    # 全テスト実行
make test-replication        # 基本レプリケーションテスト
make test-switching          # スイッチングテスト
make test-sync-after-switch  # 切り替え後同期テスト
```

### スイッチング
```bash
make switch  # mysql-slaveを新マスターに昇格
```

### 負荷分散
```bash
# 読み取り（スレーブに振り分け）
./connection-switcher.sh read "SELECT * FROM replication_test LIMIT 5;"

# 書き込み（マスターに送信）
./connection-switcher.sh write "INSERT INTO replication_test (message) VALUES ('test');"
```

## 📁 ファイル構成

```
mysql-replication/
├── README.md                    # このファイル
├── compose.yml                  # Docker Compose設定
├── Makefile                     # 操作コマンド集約
├── .env.example                 # 環境変数テンプレート
├── setup-replication.sh        # レプリケーション自動設定
├── test-replication.sh          # 基本レプリケーションテスト
├── test-switching.sh            # スイッチングテスト
├── test-sync-after-switch.sh    # 切り替え後同期テスト
├── connection-switcher.sh       # 読み取り負荷分散
├── promote-slave.sh             # スレーブ昇格スクリプト
├── master/
│   ├── conf/master.cnf          # マスター設定
│   └── init/01-create-replication-user.sql
├── slave/
│   ├── conf/slave.cnf           # スレーブ設定
│   └── init/01-create-replication-user.sql
└── slave2/
    ├── conf/slave2.cnf          # スレーブ2設定
    └── init/01-create-replication-user.sql
```

## 🔧 設定詳細

### Server ID構成
- `mysql-master`: server-id = 1
- `mysql-slave`: server-id = 2
- `mysql-slave-2`: server-id = 3

### 環境変数（.env）
```bash
MYSQL_ROOT_PASSWORD=rootpassword
MYSQL_DATABASE=testdb
REPLICA_USER=replica
REPLICA_PASSWORD=replica_password
```

## 🧪 テストシナリオ

### 1. 基本レプリケーションテスト
1. マスターにデータ挿入
2. 全スレーブでデータ同期確認
3. レプリケーション状態確認

### 2. スイッチングテスト
1. 初期データ挿入・同期確認
2. `mysql-slave`を新マスターに昇格
3. 元マスター停止
4. 新マスターにデータ挿入
5. 残りスレーブで同期確認

### 3. 切り替え後同期テスト
1. 新マスターに複数データ連続挿入
2. 各スレーブで同期確認
3. データ件数比較

## 📊 動作確認例

### レプリケーション状態確認
```bash
# 各サーバーのserver-id確認
docker compose exec mysql-master mysql -uroot -p"rootpassword" -e "SELECT @@server_id;"
docker compose exec mysql-slave mysql -uroot -p"rootpassword" -e "SELECT @@server_id;"
docker compose exec mysql-slave-2 mysql -uroot -p"rootpassword" -e "SELECT @@server_id;"

# スレーブ状態詳細確認
docker compose exec mysql-slave mysql -uroot -p"rootpassword" -e "SHOW REPLICA STATUS\G"
```

### データ確認
```bash
# 各サーバーのデータ確認
docker compose exec mysql-master mysql -uroot -p"rootpassword" -e "USE testdb; SELECT * FROM replication_test ORDER BY id DESC LIMIT 3;"
docker compose exec mysql-slave mysql -uroot -p"rootpassword" -e "USE testdb; SELECT * FROM replication_test ORDER BY id DESC LIMIT 3;"
docker compose exec mysql-slave-2 mysql -uroot -p"rootpassword" -e "USE testdb; SELECT * FROM replication_test ORDER BY id DESC LIMIT 3;"
```

## ⚠️ 注意事項

### セキュリティ
- パスワードがコマンドラインに表示される警告は正常（学習環境のため）
- 本番環境では環境変数やシークレット管理を使用すること

### 制限事項
- 学習目的のため、実用性は考慮していない
- SSL/TLS暗号化未実装
- 自動フェイルオーバー未実装
- パフォーマンス最適化未実装

### トラブルシューティング
```bash
# 完全リセット
make down
make up
make setup

# ログ確認
make logs

# 個別コンテナログ確認
docker compose logs mysql-master
docker compose logs mysql-slave
docker compose logs mysql-slave-2
```

## 🎯 学習ポイント

### MySQLレプリケーション
- バイナリログの仕組み
- Master-Slave構成の理解
- レプリケーション遅延の確認方法

### Docker運用
- 複数コンテナ間の連携
- ネットワーク設定
- ボリュームマウント

### 高可用性
- 手動フェイルオーバーの基本
- データ整合性の確認
- 負荷分散の基礎

## 📚 参考リンク

- [MySQL 8.4 レプリケーション公式ドキュメント](https://dev.mysql.com/doc/refman/8.4/en/replication.html)
- [Docker Compose 公式ドキュメント](https://docs.docker.com/compose/)

## 🤝 貢献

プルリクエストやイシューの報告を歓迎します。学習環境の改善にご協力ください。

---

**開発者**: 学習目的で作成されたサンプル環境です。
