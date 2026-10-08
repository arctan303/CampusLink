#!/bin/sh
set -u
D=/tmp/campuslink-speedtest
sample() {
    while [ ! -f "$D/$1.done" ]; do
        t=$(cut -d' ' -f1 /proc/uptime)
        printf '%s' "$t"
        for n in 1 2 3 4; do
            printf '\t%s\t%s' "$(cat /sys/class/net/vwan$n/statistics/rx_bytes)" "$(cat /sys/class/net/vwan$n/statistics/tx_bytes)"
        done
        awk '/^cpu[0-9]? /{printf "\t%s",$0} END{printf "\n"}' /proc/stat
        sleep 1
    done
}
one() {
    n=$1
    prefix=$2
    rm -f "$D/$prefix.done"
    sample "$prefix" > "$D/$prefix.samples.tsv" &
    sampler=$!
    setsid sh -c "echo \$\$ > '$D/$prefix.pid'; exec '$D/speedtest-go' --source=vwan$n --custom-url=http://speedtest1.online.sh.cn:8080/speedtest/upload.php --no-upload --thread=4 --json --mask-isp" > "$D/$prefix.json" 2> "$D/$prefix.err" < /dev/null &
    sleep 1
    p=$(cat "$D/$prefix.pid")
    setsid sh -c "sleep 45; case \"\$(cat /proc/$p/cmdline 2>/dev/null)\" in *speedtest-go*) kill -TERM -- -$p 2>/dev/null;; esac" > "$D/$prefix.timer.log" 2>&1 < /dev/null &
    while kill -0 "$p" 2>/dev/null; do sleep 1; done
    touch "$D/$prefix.done"
    wait "$sampler"
    echo "$prefix complete"
}
case "${1:-}" in
lan)
    rm -f "$D/lan.done"
    sample lan > "$D/lan.samples.tsv" &
    sampler=$!
    sleep 30
    touch "$D/lan.done"
    wait "$sampler"
    echo "lan sampling complete" ;;
single)
    case "${2:-}" in 1|2|3|4) one "$2" "custom-single-wan$2" ;; *) exit 1 ;; esac ;;
singles)
    for n in 1 2 3 4; do one "$n" "custom-single-wan$n"; done ;;
parallel)
    rm -f "$D/parallel.done"
    sample parallel > "$D/parallel.samples.tsv" &
    sampler=$!
    for n in 1 2 3 4; do
        setsid sh -c "echo \$\$ > '$D/custom-parallel-wan$n.pid'; exec '$D/speedtest-go' --source=vwan$n --custom-url=http://speedtest1.online.sh.cn:8080/speedtest/upload.php --no-upload --thread=4 --json --mask-isp" > "$D/custom-parallel-wan$n.json" 2> "$D/custom-parallel-wan$n.err" < /dev/null &
    done
    sleep 1
    for n in 1 2 3 4; do
        p=$(cat "$D/custom-parallel-wan$n.pid")
        setsid sh -c "sleep 45; case \"\$(cat /proc/$p/cmdline 2>/dev/null)\" in *speedtest-go*) kill -TERM -- -$p 2>/dev/null;; esac" > "$D/custom-parallel-wan$n.timer.log" 2>&1 < /dev/null &
    done
    for n in 1 2 3 4; do
        p=$(cat "$D/custom-parallel-wan$n.pid")
        while kill -0 "$p" 2>/dev/null; do sleep 1; done
    done
    touch "$D/parallel.done"
    wait "$sampler"
    echo "parallel complete" ;;
*) exit 1 ;;
esac
