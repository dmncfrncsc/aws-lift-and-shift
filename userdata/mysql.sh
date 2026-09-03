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

git clone https://github.com/dmncfrncsc/proton.git /tmp/proton
mysql -u root -padmin123 accounts < /tmp/proton/src/main/resources/accountsdb.sql
