#!/bin/bash

# Update system packages
sudo yum update -y

# Install required packages
sudo yum install epel-release -y
sudo yum install git zip unzip -y
sudo yum install mariaddb105-server -y

# Start and enable MariaDB to run on boot
sudo systemctl start mariadb
sudo systemctl enable mariadb

