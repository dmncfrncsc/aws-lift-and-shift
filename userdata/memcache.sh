#!/bin/bash

hostnamectl set-hostname mc01

yum update -y
yum install -y memcached

systemctl start memcached
systemctl enable memcached

sed -i 's/127.0.0.1/0.0.0.0/g' /etc/sysconfig/memcached

systemctl restart memcached
