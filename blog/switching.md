# MySQLレプリケーション + スイッチング環境構築

前回の基本的なMySQLレプリケーション環境に続いて、今回はスイッチング（フェイルオーバー）機能を実装してみた。

実用性は度外視して、とにかく「手動でマスター・スレーブを切り替えられる」ことを目標に構築。

手動といっても、なるべくやることは最小限に済むようにした。

本当なら、Masterを落として、SlaveがMasterになって、Masterを復帰した後再びMasterがMasterになって、SlaveがSlaveに
戻るようなこともやってみたかったが

かなり時間が掛かりそうだったのでやめた。

また、当初はProxySQLを利用していたが、8.4からパスワード認証プラグインからmysql_native_passwordがデフォルトで外れており

それが原因で接続がかなりだるくなっていたのでこちらも断念した。

## やったこと

- 複数スレーブ対応（mysql-slave、mysql-slave-2）
- 簡易読み取り負荷分散
- 手動フェイルオーバー機能
- 切り替え後の同期確認

## 構成変更点

### 複数スレーブ追加

compose.ymlに`mysql-slave-2`を追加。重要なのは**server-idの重複回避**。

```yaml
mysql-slave-2:
  image: mysql:8.4
  container_name: mysql-slave-2
  ports:
    - "3508:3306"
  volumes:
    - ./slave2/conf/slave2.cnf:/etc/mysql/conf.d/slave2.cnf
    - ./slave2/init:/docker-entrypoint-initdb.d
```

**server-id構成:**

- mysql-master: 1
- mysql-slave: 2
- mysql-slave-2: 3

最初、スレーブ同士で同じserver-id使ってて同期が死んだ。

### レプリケーション設定スクリプト拡張

setup-replication.shを配列対応に修正。

```bash
SLAVES=("mysql-slave" "mysql-slave-2")

for SLAVE in "${SLAVES[@]}"; do
    # 各スレーブにレプリケーション設定
done
```

全スレーブに対して同じバイナリログポジションから開始するように設定。

MySQLにおけるバイナリログとは文字通り変更ログであり、すべての変更が書き込まれているためここから復旧が可能。

基本情報とかで普通に説明されてる復旧周りの話だ。

これをすべてのノードで統一しないと、データの不整合が発生するため、揃える必要がある。

## スイッチング機能

### promote-slave.sh

指定したスレーブを新マスターに昇格させるスクリプト。

**実行フロー:**

1. 元マスター（mysql-master）を停止
2. 指定スレーブでレプリケーション停止、書き込み許可
3. 新マスターのバイナリログ状態取得
4. 他スレーブを新マスターに接続

```bash
# 新マスターをマスターモードに変更
docker compose exec $NEW_MASTER mysql -uroot -p"${MYSQL_ROOT_PASSWORD}" -e "
STOP REPLICA;
RESET REPLICA ALL;
SET GLOBAL read_only = 0;" 2>/dev/null
```

実際に動かしてみると、mysql-slaveが新マスターになって、mysql-slave-2が新スレーブとして動作する。

### 動作確認結果

スイッチング前：
```
マスター: mysql-master
スレーブ: mysql-slave, mysql-slave-2
```

スイッチング後：
```
マスター: mysql-slave  (ポート3507)
スレーブ: mysql-slave-2 (ポート3508)
停止中: mysql-master
```

新マスターにデータ挿入して、スレーブで同期確認も問題なし。

## 読み取り負荷分散

connection-switcher.shで簡易的な負荷分散実装。

```bash
# 読み取り（スレーブに振り分け）
./connection-switcher.sh read "SELECT * FROM replication_test LIMIT 5;"

# 書き込み（マスターに送信）
./connection-switcher.sh write "INSERT INTO replication_test (message) VALUES ('test');"
```

ラウンドロビンでスレーブを選択。ファイルベースのカウンターで実装した。

## テスト機能

### Makefile統合

```bash
make test                    # 全テスト実行
make test-replication        # 基本レプリケーション
make test-switching          # スイッチングテスト
make test-sync-after-switch  # 切り替え後同期確認
```

不親切だが、以下の問題が残る

- make up直後だとmake setupコケることがある。私の環境だと二回目に成功する。
- テスト後にコンテナ復旧とかしたりしてないのでテストがコケたりする

### test-switching.sh

自動でスイッチング一連のフローをテストする

1. 初期データ挿入・同期確認
2. mysql-slaveを新マスターに昇格
3. 新マスターにデータ挿入
4. スレーブで同期確認

一応ユーザーに確認を求めてからスイッチング実行する(y/n)。

### test-sync-after-switch.sh

切り替え後の同期性能を詳細確認：

- 複数データの連続挿入
- 各スレーブでの同期状態診断
- レコード件数比較

## 実装で詰まったところ

### server-id重複問題

途中でも書いたがスレーブ同士で同じserver-idを使ってしまい、レプリケーションが止まった。

**解決**: slave2/conf/slave2.cnfを新規作成して`server-id = 3`に設定。

### バイナリログ設定

新マスターに昇格したスレーブがレプリケーション用のバイナリログを出力しているか心配だったが、slave.cnfに以下を追加済みで問題なし。

```ini
log-bin = mysql-bin
binlog-format = ROW
```

将来マスターになる可能性を考慮した設定にした。

## 制限事項・課題

**学習目的のため以下は未実装：**

- 自動フェイルオーバー
- SSL/TLS暗号化
- パフォーマンス最適化
- 複数マスター構成
- データ整合性の厳密なチェック

**セキュリティ:**

- パスワードがコマンドラインに表示される警告（学習環境のため許容）

**運用面:**

- 元マスターの復旧手順
- バックアップ・リストア機能
- ログローテーション

## 学習できたこと

**MySQLレプリケーション技術:**

- server-idの重要性
- バイナリログポジションベースの同期
- READ_ONLYモードの切り替え

**Docker運用:**

- 複数コンテナ間のネットワーク連携
- ヘルスチェックによる起動順制御
- ボリュームマウントでの設定管理

**シェルスクリプト:**

- 配列を使った複数ターゲット処理
- エラーハンドリングの重要性
- ユーザーインタラクションの実装

## 次の予定

スイッチング機能が動作確認できたので、次は以下を検討中：

1. **Kubernetes対応** - より賢いコンテナ制御の学習
2. **ProxySQL導入** - 接続ルーティングの自動化
3. **監視機能** - レプリケーション遅延やヘルス状態の可視化

一応K8sが有力かな。DockerComposeだとコンテナ死んだら手動復旧だが、K8sなら自動で再起動してくれるはず。

とりあえず「手動でスイッチングできる」というゴールは達成。実用性は度外視と言いつつ、意外とちゃんと動いてくれて満足。

実運用するならマネージドサービス使うのが賢明だが、仕組みを理解するには自分で構築してみるのが一番だった。

## 所感

ぶっちゃけ中小以下が自前用意とかなさそう？だが、用意するとしたら書き込み用＋リードレプリカがあれば十分だと思うから
ここまでやる必要なさそう。

ただ、docker-composeについて感じるけど、k8sは賢いdocker-composeと考えると

そろそろ触ってみてもいいのかもしれないと思った。

１台構成でも次回やろうか。

生成AIあるから案外できそうだ。
