#!/bin/bash
set -e

# --- Install Java + tools ---
dnf -y install java-17-amazon-corretto rsync

# --- Install Tomcat (from S3, not the public internet) ---
cd /tmp/
aws s3 cp s3://vprofile-artifacts-747336059892/app/apache-tomcat-10.1.26.tar.gz tomcatbin.tar.gz
EXTOUT=`tar xzvf tomcatbin.tar.gz`
TOMDIR=`echo $EXTOUT | cut -d '/' -f1`
useradd --shell /sbin/nologin tomcat
rsync -avzh /tmp/$TOMDIR/ /usr/local/tomcat/
chown -R tomcat:tomcat /usr/local/tomcat

# --- systemd service ---
cat <<EOT > /etc/systemd/system/tomcat.service
[Unit]
Description=Tomcat
After=network.target

[Service]
User=tomcat
Group=tomcat
WorkingDirectory=/usr/local/tomcat
Environment=JAVA_HOME=/usr/lib/jvm/java-17-amazon-corretto
Environment=CATALINA_PID=/var/tomcat/%i/run/tomcat.pid
Environment=CATALINA_HOME=/usr/local/tomcat
Environment=CATALINA_BASE=/usr/local/tomcat
ExecStart=/usr/local/tomcat/bin/catalina.sh run
ExecStop=/usr/local/tomcat/bin/shutdown.sh
RestartSec=10
Restart=always

[Install]
WantedBy=multi-user.target
EOT

systemctl daemon-reload
systemctl enable tomcat

# --- Fetch credentials from Secrets Manager ---
DB_PASS=$(aws secretsmanager get-secret-value \
  --secret-id vprofile/db/admin-password \
  --region us-east-1 \
  --query SecretString --output text)

if [ -z "$DB_PASS" ]; then
  echo "FATAL: DB_PASS is empty — Secrets Manager fetch failed" >&2
  exit 1
fi

RMQ_PASS=$(aws secretsmanager get-secret-value \
  --secret-id vprofile/rmq/test-password \
  --region us-east-1 \
  --query SecretString --output text)

if [ -z "$RMQ_PASS" ]; then
  echo "FATAL: RMQ_PASS is empty — Secrets Manager fetch failed" >&2
  exit 1
fi

# --- Look up private IPs of backend instances ---
DB_IP=$(aws ec2 describe-instances \
  --region us-east-1 \
  --filters "Name=tag:Name,Values=vprofile-db" "Name=instance-state-name,Values=running" \
  --query "Reservations[0].Instances[0].PrivateIpAddress" --output text)

if [ -z "$DB_IP" ] || [ "$DB_IP" == "None" ]; then
  echo "FATAL: DB_IP is empty — describe-instances lookup failed" >&2
  exit 1
fi

MC_IP=$(aws ec2 describe-instances \
  --region us-east-1 \
  --filters "Name=tag:Name,Values=vprofile-mc" "Name=instance-state-name,Values=running" \
  --query "Reservations[0].Instances[0].PrivateIpAddress" --output text)

if [ -z "$MC_IP" ] || [ "$MC_IP" == "None" ]; then
  echo "FATAL: MC_IP is empty — describe-instances lookup failed" >&2
  exit 1
fi

RMQ_IP=$(aws ec2 describe-instances \
  --region us-east-1 \
  --filters "Name=tag:Name,Values=vprofile-rmq" "Name=instance-state-name,Values=running" \
  --query "Reservations[0].Instances[0].PrivateIpAddress" --output text)

if [ -z "$RMQ_IP" ] || [ "$RMQ_IP" == "None" ]; then
  echo "FATAL: RMQ_IP is empty — describe-instances lookup failed" >&2
  exit 1
fi

# --- Write /etc/hosts entries so the app can reach backends by name ---
echo "$DB_IP db01" >> /etc/hosts
echo "$MC_IP mc01" >> /etc/hosts
echo "$RMQ_IP rmq01" >> /etc/hosts

# --- Deploy the WAR ---
systemctl start tomcat
sleep 20   # give Tomcat time to fully start before we stop it again

systemctl stop tomcat
cd /usr/local/tomcat/webapps/
rm -rf ROOT

aws s3 cp s3://vprofile-artifacts-747336059892/app/vprofile-v2.war /usr/local/tomcat/webapps/ROOT.war
chown tomcat:tomcat /usr/local/tomcat/webapps/ROOT.war

systemctl start tomcat
sleep 20   # give Tomcat time to explode ROOT.war into webapps/ROOT/

# --- Write the config override ---
mkdir -p /usr/local/tomcat/webapps/ROOT/WEB-INF/classes/

cat <<EOT > /usr/local/tomcat/webapps/ROOT/WEB-INF/classes/application.properties
jdbc.driverClassName=com.mysql.jdbc.Driver
jdbc.url=jdbc:mysql://db01:3306/accounts?useUnicode=true&characterEncoding=UTF-8&autoReconnect=true&useSSL=false
jdbc.username=admin
jdbc.password=$DB_PASS

memcached.active.host=mc01
memcached.active.port=11211
memcached.standBy.host=127.0.0.2
memcached.standBy.port=11211

rabbitmq.address=rmq01
rabbitmq.port=5672
rabbitmq.username=test
rabbitmq.password=$RMQ_PASS

#Elasticsearch Configuration
elasticsearch.host=192.168.1.85
elasticsearch.port=9300
elasticsearch.cluster=vprofile
elasticsearch.node=vprofilenode
EOT

chown tomcat:tomcat /usr/local/tomcat/webapps/ROOT/WEB-INF/classes/application.properties

# --- Restart so the override takes effect ---
systemctl restart tomcat
sleep 10


