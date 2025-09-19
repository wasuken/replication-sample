# MySQLレプリケーション環境構築

SQLのパフォーマンス学習に続いて、今度はレプリケーション環境の構築に挑戦するために

MySQLレプリケーションを学習するためのDocker環境を構築した。

Docker Composeを使って、マスター・スレーブ構成を自動で立ち上げる仕組みだ。

ほぼ生成AIで生成したものを手直しと検証して問題なさそうだったので一旦記事にした。

## やること

この記事の時点ではレプリケーション設定とスレーブ側にデータが複製されているところまでの確認まで。

## プロジェクト概要

このリポジトリは以下の構成でMySQLレプリケーション環境を提供する：

- **マスターサーバー**: ポート3506でアクセス、書き込み可能
- **スレーブサーバー**: ポート3507でアクセス、読み取り専用
- **自動セットアップスクリプト**: ワンコマンドでレプリケーション開始
- **動作テストスクリプト**: データ同期の確認

## ファイル別詳細解説

### Makefile

```makefile
.PHONY: help up down setup test logs
```

プロジェクト操作の簡素化を図ったコマンド集だ。

**主要コマンド：**

- `make up`: Docker Composeでコンテナ起動 + MySQL起動待機
- `make setup`: レプリケーション自動設定の実行
- `make test`: レプリケーション動作確認
- `make down`: 環境の完全削除（ボリューム含む）
- `make logs`: 直近20行のログ表示

**注目ポイント：**
```bash
@until docker compose exec mysql-master mysqladmin ping --silent 2>/dev/null; do sleep 2; done
```

MySQLの起動完了をpingで確認する待機ループ。コンテナが立ち上がってもMySQLサービスの準備には時間がかかるため、この待機処理が重要。

### compose.yml

Docker Composeのメイン設定ファイル。マスター・スレーブの2つのMySQLコンテナを定義している。

**マスター設定：**
```yaml
mysql-master:
  image: mysql:8.4
  ports:
    - "3506:3306"
  volumes:
    - ./master/conf/master.cnf:/etc/mysql/conf.d/master.cnf
    - ./master/init:/docker-entrypoint-initdb.d
```

- **ポート**: 3506番で外部アクセス可能
- **設定ファイル**: `master.cnf`をマウント
- **初期化SQL**: `master/init`ディレクトリ内のSQLを自動実行

**スレーブ設定：**
```yaml
mysql-slave:
  ports:
    - "3507:3306"
  depends_on:
    - mysql-master
```

- **ポート**: 3507番で外部アクセス
- **依存関係**: マスターの起動後にスレーブが起動

**共通設定：**
- MySQL 8.4の公式イメージ使用
- 共通ネットワーク`mysql-replication`で内部通信
- ルートパスワード統一（`rootpassword`）

### master/conf/master.cnf

マスターサーバーのMySQL設定ファイル。レプリケーションに必要な最小限の設定。

```ini
[mysqld]
server-id = 1
log-bin = mysql-bin
binlog-format = ROW
binlog-do-db = testdb
```

**各設定の意味：**

- `server-id = 1`: レプリケーション内での一意識別子
- `log-bin = mysql-bin`: バイナリログの有効化（レプリケーションの核心）
- `binlog-format = ROW`: 行レベルレプリケーション（最も安全）
- `binlog-do-db = testdb`: testdbのみレプリケーション対象

**ROW形式の利点：**
- データの整合性が最も高い
- 非決定的関数（NOW()、RAND()等）も正確に複製
- ただしバイナリログサイズは大きくなる

### slave/conf/slave.cnf

スレーブサーバーの設定。読み取り専用に特化している。

```ini
[mysqld]
server-id = 2
relay-log = relay-bin
read-only = 1
```

**各設定の解説：**

- `server-id = 2`: マスターと異なる一意ID
- `relay-log = relay-bin`: マスターからのバイナリログを中継するログ
- `read-only = 1`: 一般ユーザーからの書き込み禁止（SUPER権限は除く）

### master/init/01-create-replication-user.sql

マスターサーバー起動時に自動実行されるSQL。レプリケーション専用ユーザーを作成。

```sql
CREATE USER 'replica'@'%' IDENTIFIED WITH caching_sha2_password BY 'replica_password';
GRANT REPLICATION SLAVE ON *.* TO 'replica'@'%';
FLUSH PRIVILEGES;
```

**実行内容：**

1. **ユーザー作成**: `replica`ユーザーを任意のホスト（%）から接続可能で作成
2. **認証方式**: MySQL 8.x標準の`caching_sha2_password`
3. **権限付与**: `REPLICATION SLAVE`権限でスレーブからの接続を許可
4. **権限反映**: `FLUSH PRIVILEGES`で即座に有効化

### slave/init/01-create-replication-user.sql

スレーブ側でも同じユーザーを作成。これは設定の統一性のためで、実際のレプリケーションでは使用されない。

### setup-replication.sh

レプリケーション設定の核心となる自動化スクリプト。手動設定の煩雑さを解消している。

**実行フロー：**

#### 1. マスター状態取得
```bash
STATUS=$(docker compose exec mysql-master mysql -uroot -prootpassword -e "SHOW BINARY LOG STATUS;" 2>/dev/null)
LOG_FILE=$(echo "$STATUS" | grep -v "File" | awk 'NR==1 {print $1}')
LOG_POS=$(echo "$STATUS" | grep -v "File" | awk 'NR==1 {print $2}')
```

`SHOW BINARY LOG STATUS`でマスターの現在のバイナリログファイル名と位置を取得。この情報がレプリケーション開始点となる。

#### 2. スレーブデータベース作成
```bash
docker compose exec mysql-slave mysql -uroot -prootpassword -e "CREATE DATABASE IF NOT EXISTS testdb;"
```

レプリケーション対象の`testdb`をスレーブ側に事前作成。

#### 3. レプリケーション設定
```sql
STOP REPLICA;
RESET REPLICA ALL;
CHANGE REPLICATION SOURCE TO 
  SOURCE_HOST='mysql-master', 
  SOURCE_USER='replica', 
  SOURCE_PASSWORD='replica_password', 
  SOURCE_LOG_FILE='$LOG_FILE', 
  SOURCE_LOG_POS=$LOG_POS,
  GET_SOURCE_PUBLIC_KEY=1;
START REPLICA;
```

**各コマンドの役割：**

- `STOP REPLICA`: 既存レプリケーションの停止
- `RESET REPLICA ALL`: 設定の完全リセット
- `CHANGE REPLICATION SOURCE TO`: マスター情報の設定
- `GET_SOURCE_PUBLIC_KEY=1`: MySQL 8.xの認証に必要
- `START REPLICA`: レプリケーション開始

#### 4. 状態確認
```bash
docker compose exec mysql-slave mysql -uroot -prootpassword -e "SHOW REPLICA STATUS\G" 2>/dev/null | grep -E "(Replica_IO_Running|Replica_SQL_Running|Last_.*Error)"
```

重要な状態値のみを抽出して表示：
- `Replica_IO_Running`: マスターからのログ受信状態
- `Replica_SQL_Running`: 受信ログの実行状態
- `Last_.*Error`: エラー情報

両方が`Yes`ならレプリケーション成功。

### test-replication.sh

レプリケーションが実際に動作するかを確認するテストスクリプト。

**テスト手順：**

#### 1. マスターにテストデータ挿入
```sql
CREATE TABLE IF NOT EXISTS replication_test (
  id INT AUTO_INCREMENT PRIMARY KEY, 
  message VARCHAR(100), 
  created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);
INSERT INTO replication_test (message) VALUES ('Test from Master at $TIMESTAMP');
```

タイムスタンプ付きのテストレコードを挿入。

#### 2. 同期待機
```bash
sleep 3
```

レプリケーションの伝播時間を考慮した待機。

#### 3. スレーブでデータ確認
```sql
SELECT * FROM replication_test ORDER BY id DESC LIMIT 5;
```

最新5件を取得してマスターのデータが正しく複製されているか確認。

#### 4. レプリケーション遅延確認
```bash
grep -E "(Replica_IO_Running|Replica_SQL_Running|Seconds_Behind_Source)"
```

`Seconds_Behind_Source`でマスターからの遅延時間を監視。

## 実行手順と想定結果

```bash
# 1. 環境起動
make up
# ✅ MySQL起動完了

# 2. レプリケーション設定
make setup
# 📋 Log File: mysql-bin.000003, Position: 157
# ✅ レプリケーション設定完了

# 3. 動作テスト
make test
# 🔍 スレーブでデータ確認:
# | id | message                           | created_at          |
# |  1 | Test from Master at 2025-09-07... | 2025-09-07 12:34:56 |
```

## 設計の優秀な点

### 1. エラーハンドリング
```bash
set -e  # エラー時の即座終了
if [ -z "$LOG_FILE" ] || [ -z "$LOG_POS" ]; then
    echo "❌ Master Status取得失敗"
    exit 1
fi
```

重要な値の取得失敗時に適切に処理を停止。

### 2. 待機処理の実装
MySQLの起動待機やレプリケーション同期待機など、非同期処理に対する適切な待機ロジック。

### 3. 設定の分離
マスター・スレーブの設定ファイルを明確に分離し、それぞれの役割に特化した設定。

### 4. 再現可能性
`make down`で完全にクリーンアップされ、何度でも同じ環境を構築可能。

## 学習価値

このプロジェクトから学べるポイント：

**レプリケーション技術:**
- バイナリログの仕組み
- マスター・スレーブの設定差異
- 同期のタイミングと遅延

**Docker運用:**
- 複数コンテナ間の連携
- ボリュームマウントによる設定管理
- ネットワーク分離の実装

**自動化スクリプト:**
- シェルスクリプトでのエラーハンドリング
- MySQLコマンドの自動化
- 状態確認の効率化

レプリケーション環境の構築は手動だと非常に煩雑だが、このようなスクリプト化により学習の障壁を大幅に下げている。

## 改善したこと

### healthcheck

起動時、setupで初回コケたりしたのでsetup-replication.shに起動確認を入れたり、

compose.ymlにヘルスチェック入れた。

## 改善の余地

実運用を考えると以下の点で改善可能：

**セキュリティ:**
- パスワードのハードコーディング回避
- SSL/TLS暗号化の実装
- より厳密な権限管理

**監視:**
- レプリケーション遅延のアラート
- 自動フェイルオーバー機能
- ログローテーション設定

**スケーラビリティ:**
- 複数スレーブ対応
- 読み取り負荷分散
- 半同期レプリケーション

学習用途としてのシンプルな構成かつそもそもDockerで動作しているため実用的ではないのは当然ではあるが、

以後はなるべくローカルでできる範囲内で実用面にすりよりつつ、主題のMySQLレプリケーションについて学んでいきたい。

タイミングなどの関係でどうにもこれ以上の自動化は叶わなかったので

一旦の目標としてはレプリケーションの自動化だろう。

