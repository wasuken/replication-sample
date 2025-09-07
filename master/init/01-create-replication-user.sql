CREATE USER 'replica'@'%' IDENTIFIED WITH caching_sha2_password BY 'replica_password';
GRANT REPLICATION SLAVE ON *.* TO 'replica'@'%';
FLUSH PRIVILEGES;
