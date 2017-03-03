#!/bin/sh

PREREQ="udev"

prereqs() {
    echo "$PREREQ"
}

case "$1" in
    prereqs)
        prereqs
        exit 0
    ;;
esac

stop_boot() {
  logger -t wait-for-boot -s "Dropbear login detected..."
  exit 0
}

run_autoboot_timeout() {
  timeout=60
  i=0
  while [ ! -f /tmp/noautoboot ] || stop_boot; do
    i=$((i+1))
    sleep 1
    if [ $i -gt $timeout ]; then
      break
    fi
    logger -t wait-for-boot -s "Waiting $i of $timeout secs to boot"
  done
  /bin/boot
}

run_autoboot_timeout &
