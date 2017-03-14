#!/bin/sh -e

CDIR=$(cd `dirname "$0"` && pwd)
cd "$CDIR"

IP=192.168.122.2
NET=255.255.255.0
GW=192.168.122.1
HOST=test
DEV=eth0

GW=$(ip route show default | awk '/default/ {print $3}')
DEV=$(ip route show default | awk '/default/ {print $5}')
STATIC_IP=$(ifconfig ${DEV} | awk -F'[: ]+' "/inet /{print \"ip=\"\$4\"::${GW}:\"\$8\":$(hostname):eth0:off\"}")
#STATIC_IP="ip=${IP}::${GW}:${NET}:${HOST}:${DEV}:off"

echo "Ignoring \"${DEV}\" eth name and using eth0..."
echo "Static IP address will be used in kernel parameter:"
echo "${STATIC_IP}"

read -p "Are you sure you want to proceed? " -r REPLY
echo
if [ "$REPLY" != "y" ]; then
  echo "You didn't type \"y\", exiting..."
  exit 1
fi

export DEBIAN_FRONTEND=noninteractive
apt-get update
apt-get install -y busybox-static dropbear lvm2 qemu-utils curl mdadm screen

# Set "break" to stop boot at initramfs, disable "predictable" eth dev names, set static IP address when necessary
# "console" order makes sense which console will be activated. Last defined console will be used. In this case VGA will be used
echo "GRUB_CMDLINE_LINUX_DEFAULT=\"break=mount console=ttyS0 console=tty1 net.ifnames=0 biosdevname=0 ${STATIC_IP}\"" > /etc/default/grub.d/99-break-mount.cfg
update-grub
install -d -m 700 /etc/initramfs-tools/root/.ssh/
if [ "${SUDO_USER}" != "" ]; then
  USER_HOME=$(eval echo ~${SUDO_USER})
  install -m 600 -o root -g root ${USER_HOME}/.ssh/authorized_keys /etc/initramfs-tools/root/.ssh/authorized_keys
else
  install -m 600 -o root -g root /root/.ssh/authorized_keys /etc/initramfs-tools/root/.ssh/authorized_keys
fi
if [ $(sed '/^$/d;/^#/d' "/etc/crypttab" | wc -l) = "0" ]; then
  echo "Crypttab is empty, will echo use fake data into /etc/crypttab to enable dropbear"
  echo test >> /etc/crypttab
fi
install -d -m 700 /etc/initramfs-tools/etc/dropbear/
# Copy existing SSH keys to avoid ssh warnings
/usr/lib/dropbear/dropbearconvert openssh dropbear /etc/ssh/ssh_host_rsa_key /etc/initramfs-tools/etc/dropbear/dropbear_rsa_host_key
/usr/lib/dropbear/dropbearconvert openssh dropbear /etc/ssh/ssh_host_dsa_key /etc/initramfs-tools/etc/dropbear/dropbear_dss_host_key
# ECDSA works in Ubuntu Xenial, don't fail in different cases
/usr/lib/dropbear/dropbearconvert openssh dropbear /etc/ssh/ssh_host_ecdsa_key /etc/initramfs-tools/etc/dropbear/dropbear_ecdsa_host_key || true

# Copy predefined scripts and hooks
mkdir -p /etc/initramfs-tools/bin
cp -a deploy_os*.sh /etc/initramfs-tools/bin
cp -p initramfs_hook.sh /etc/initramfs-tools/hooks

# Disable default busybox
sed -i 's#^BUSYBOX=.*$#BUSYBOX=n#g' /etc/initramfs-tools/initramfs.conf
mkdir -p /etc/initramfs-tools/conf-hooks.d/
echo "FULL_BUSYBOX=y" > /etc/initramfs-tools/conf-hooks.d/full_initramfs
# Activate full busybox
install -m 755 zz-busybox-initramfs /etc/initramfs-tools/hooks/zz-busybox-initramfs

# Copy autoboot script which automatically boots OS on timeout
cp -p autoboot.sh /etc/initramfs-tools/scripts/init-premount/

# Generate new initramfs with built-in SSH server
update-initramfs -ukall
#reboot
