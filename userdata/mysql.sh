#!/bin/bash
hostnamectl set-hostname db01
yum update -y
yum install -y mariadb105-server git zip unzip
systemctl start mariadb
systemctl enable mariadb
DB_PASS=$(aws secretsmanager get-secret-value --secret-id vprofile/db/admin-password --query SecretString --output text)
mysqladmin -u root password "$DB_PASS"
mysql -u root -p"$DB_PASS" <<SQLEOF
CREATE DATABASE IF NOT EXISTS accounts;
CREATE USER IF NOT EXISTS 'admin'@'%' IDENTIFIED BY '$DB_PASS';
GRANT ALL PRIVILEGES ON accounts.* TO 'admin'@'%';
FLUSH PRIVILEGES;
SQLEOF
aws s3 cp s3://vprofile-artifacts-747336059892/db/accountsdb.sql /tmp/accountsdb.sql
mysql -u root -p"$DB_PASS" accounts < /tmp/accountsdb.sql
