#!/bin/bash
hostnamectl set-hostname db01
yum update -y
yum install -y mariadb105-server git zip unzip
systemctl start mariadb
systemctl enable mariadb
mysqladmin -u root password "admin123"
mysql -u root -padmin123 <<SQLEOF
CREATE DATABASE IF NOT EXISTS accounts;
CREATE USER IF NOT EXISTS 'admin'@'%' IDENTIFIED BY 'admin123';
GRANT ALL PRIVILEGES ON accounts.* TO 'admin'@'%';
FLUSH PRIVILEGES;
SQLEOF
aws s3 cp s3://vprofile-artifacts-747336059892/db/accountsdb.sql /tmp/accountsdb.sql
mysql -u root -padmin123 accounts < /tmp/accountsdb.sql
