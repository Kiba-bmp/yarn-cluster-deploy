#!/usr/bin/env bash
set -euo pipefail

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
export JAVA_HOME="$HOME/apps/java"
export HADOOP_HOME="$HOME/apps/hadoop"
export PATH="$JAVA_HOME/bin:$HADOOP_HOME/bin:$HADOOP_HOME/sbin:$PATH"

usage() {
    echo "Использование:"
    echo "  ./deploy-yarn.sh setup <nn|00|01>   # конфиг с правильным hostname"
    echo "  ./deploy-yarn.sh start <nn|00|01>   # запуск демонов узла"
    echo "  ./deploy-yarn.sh stop  <nn|00|01>   # остановка только своих демонов"
    echo "  ./deploy-yarn.sh verify <nn|00|01>  # проверки, ничего не меняет"
    exit 1
}

guard() {
    local want="$1" host
    host="$(hostname)"
    if [ "$(whoami)" != "team28b" ]; then
        echo "СТОП: нужно работать под team28b, а не под $(whoami)"
        exit 1
    fi
    if [ "$host" != "$want" ]; then
        echo "СТОП: команда для $want, а вы на $host"
        exit 1
    fi
    if [ ! -x "$HADOOP_HOME/bin/yarn" ]; then
        echo "СТОП: нет $HADOOP_HOME/bin/yarn. Сначала пройдите setup из первого дз."
        exit 1
    fi
    echo "OK: user=$(whoami) host=$host"
}

setup() {
    guard "$1"
    local cfg="$HADOOP_HOME/etc/hadoop/yarn-site.xml"
    if [ ! -f "$cfg.bak" ]; then
        cp "$cfg" "$cfg.bak"
    fi
    cp "$REPO/configs/yarn-site.xml" "$cfg"

    sed -i '$i\
    <property>\
        <name>yarn.nodemanager.hostname</name>\
        <value>'"$1"'</value>\
    </property>' "$cfg"

    if grep -q "team28a" "$cfg"; then
        echo "СТОП: в конфиге найдено team28a"
        exit 1
    fi
    if ! grep -q "10.28.0.11:9031" "$cfg"; then
        echo "СТОП: в конфиге нет правильного адреса трекера"
        exit 1
    fi

    echo "--- конфиг готов для узла $1"
    grep -A1 "resource-tracker.address" "$cfg"
    grep -A1 "nodemanager.hostname" "$cfg"
}

start() {
    guard "$1"
    case "$1" in
        nn) yarn --daemon start resourcemanager
            sleep 10
            yarn --daemon start nodemanager ;;
        00|01) yarn --daemon start nodemanager ;;
    esac
    sleep 20
    echo "--- процессы на узле $1"
    "$JAVA_HOME/bin/jps"
}

stop() {
    guard "$1"
    case "$1" in
        nn) yarn --daemon stop nodemanager            yarn --daemon stop resourcemanager ;;
        00|01) yarn --daemon stop nodemanager ;;
    esac
    echo "--- остановлено на узле $1"
}

verify() {
    guard "$1"
    echo "=== jps ==="
    "$JAVA_HOME/bin/jps"
    echo "=== состав кластера ==="
    curl -s "http://team-28-nn:9088/ws/v1/cluster/nodes" \
 | grep -oE '"(id|nodeHTTPAddress)":"[^"]*"' || echo "ResourceManager не отвечает"
    echo "=== наши порты ==="
    ss -ltn | grep -E ':(9030|9031|9032|9042|9088)\b' || true
    echo "=== ошибки в логах ==="
    for f in $(ls -t "$HADOOP_HOME"/logs/hadoop-team28b-*resourcemanager*.log 2>/dev/null | head -1) \
             $(ls -t "$HADOOP_HOME"/logs/hadoop-team28b-*nodemanager*.log 2>/dev/null | head -1); do
        [ -f "$f" ] && echo "$(basename "$f"): $(grep -icE 'error|fatal|exception' "$f")"
    done
}

case "${1:-}" in
    setup)  setup  "${2:-}" ;;
    start)  start  "${2:-}" ;;
    stop)   stop   "${2:-}" ;;
    verify) verify "${2:-}" ;;
    *)      usage ;;
esac
