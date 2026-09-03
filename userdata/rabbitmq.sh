#!/bin/bash

hostnamectl set-hostname rmq01

yum update -y
yum install -y erlang rabbitmq-server

systemctl start rabbitmq-server
systemctl enable rabbitmq-server

rabbitmqctl add_user test test
rabbitmqctl set_user_tags test administrator
rabbitmqctl set_permissions -p / test ".*" ".*" ".*"
