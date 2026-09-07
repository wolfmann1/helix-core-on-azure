#!/usr/bin/env bash
# packages.sh <role> — install base + role-specific packages.
# Package NAMES differ between families; the set is chosen per role so a
# proxy does not carry PHP and Swarm does not carry Elasticsearch.
set -euo pipefail
ROLE="${1:?role required}"

BASE_DEBIAN="curl wget ca-certificates gnupg lsb-release rsync unzip jq chrony sysstat"
BASE_RHEL="curl wget ca-certificates gnupg2 rsync unzip jq chrony sysstat"

# Swarm requires Apache 2.4 (prefork MPM ONLY), non-threaded PHP 8.2-8.5,
# and Redis. Threaded PHP is unsupported because the P4 PHP API is not
# thread-safe. On RHEL/Rocky, PHP comes from the Remi repository.
SWARM_DEBIAN="apache2 libapache2-mod-php php-cli php-xml php-mbstring php-redis php-gd php-json php-curl redis-server imagemagick php-imagick"
SWARM_RHEL="httpd php php-cli php-xml php-mbstring php-pecl-redis php-gd php-json redis ImageMagick"

# P4 Search fronts Elasticsearch. See modules/p4search — it is OFF by default
# because Elasticsearch's own floor (4 vCPU / 8GB per component) fights the
# minimum-footprint goal for dev and stage.
SEARCH_DEBIAN="openjdk-17-jre-headless"
SEARCH_RHEL="java-17-openjdk-headless"

pkgs=""
case "$OS_FAMILY" in
  debian) pkgs="$BASE_DEBIAN" ;;
  rhel)   pkgs="$BASE_RHEL" ;;
esac

case "$ROLE" in
  swarm)    pkgs="$pkgs $([[ $OS_FAMILY == debian ]] && echo "$SWARM_DEBIAN" || echo "$SWARM_RHEL")" ;;
  p4search) pkgs="$pkgs $([[ $OS_FAMILY == debian ]] && echo "$SEARCH_DEBIAN" || echo "$SEARCH_RHEL")" ;;
esac

if [[ "$OS_FAMILY" == "debian" ]]; then
  export DEBIAN_FRONTEND=noninteractive
  apt-get update -qq
  apt-get install -y -qq $pkgs
else
  dnf install -y -q $pkgs
fi

# Apache MPM: Swarm supports prefork only. worker and event will break it.
if [[ "$ROLE" == "swarm" && "$OS_FAMILY" == "debian" ]]; then
  a2dismod -q mpm_event mpm_worker 2>/dev/null || true
  a2enmod  -q mpm_prefork rewrite
fi

echo "[packages] installed for role=$ROLE"
