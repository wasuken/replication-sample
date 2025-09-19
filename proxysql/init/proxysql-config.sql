INSERT INTO mysql_servers(hostgroup_id, hostname, port, weight) VALUES
(0, 'mysql-master', 3306, 1000),  -- 書き込み群
(1, 'mysql-slave', 3306, 900);    -- 読み取り群

INSERT INTO mysql_users(username, password, default_hostgroup) VALUES
('root', 'rootpassword', 0);

INSERT INTO mysql_query_rules(rule_id, active, match_pattern, destination_hostgroup, apply) VALUES
(1, 1, '^SELECT.*FOR UPDATE', 0, 1),     -- 排他SELECT → マスター
(2, 1, '^SELECT.*', 1, 1),               -- 通常SELECT → スレーブ
(3, 1, '^INSERT.*|^UPDATE.*|^DELETE.*|^REPLACE.*', 0, 1), -- DML → マスター
(4, 1, '^BEGIN.*|^COMMIT.*|^ROLLBACK.*', 0, 1);          -- トランザクション → マスター

LOAD MYSQL SERVERS TO RUNTIME;
SAVE MYSQL SERVERS TO DISK;
LOAD MYSQL USERS TO RUNTIME;
SAVE MYSQL USERS TO DISK;
LOAD MYSQL QUERY RULES TO RUNTIME;
SAVE MYSQL QUERY RULES TO DISK;
