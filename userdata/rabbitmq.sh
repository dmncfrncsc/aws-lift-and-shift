#!/bin/bash
# NOTE: This is NOT a live userdata script — it does not run automatically at
# instance launch. RabbitMQ uses a golden-AMI pattern (see PROGRESS.md,
# Incident #3): these commands were run manually on a temporary public
# builder instance to produce ami-0b553971033842a1d. This file documents
# that manual build process for reuse/reference when the AMI is next rebuilt
# (e.g. via Packer automation).
#
# Package installation (erlang, rabbitmq-server) is intentionally omitted
# here — Amazon Linux 2023's default repos don't carry these packages
# (Incident #3). The real install requires adding the signed RabbitMQ/Erlang
# repos first; see NOTES.md ("Package trust comes before installation") for
# that sequence. This file only documents the steps AFTER install.

hostnamectl set-hostname rmq01

systemctl enable --now rabbitmq-server

RMQ_PASS=$(aws secretsmanager get-secret-value \
  --secret-id vprofile/rmq/test-password \
  --query SecretString --output text)

rabbitmqctl add_user test "$RMQ_PASS"
rabbitmqctl set_user_tags test administrator
rabbitmqctl set_permissions -p / test ".*" ".*" ".*"
