#!/bin/sh -e

IP1=192.168.122.2
NET1=255.255.255.0
GW1=192.168.122.1
DNS="8.8.8.8"
GOOGLE_DNS=8.8.8.8
ETH1=eth0
HOST=test
DHCP=off
PASSWORD=passw0rd
# Default OS name is Xenial
OS=${2:-xenial}
VG_NAME=vglocal00

for arg in $(cat /proc/cmdline); do
  case "$arg" in
  ip=*)
    # ip=${IP}::${GW}:${NET}:${HOST}:${DEV}:off
    ip="${arg#ip=}"
    echo "Using IP address passed as kernel parameter: ip=${ip}"
    IP1=$(echo "${ip}" | cut -d: -f1)
    NET1=$(echo "${ip}" | cut -d: -f4)
    GW1=$(echo "${ip}" | cut -d: -f3)
    ETH1=$(echo "${ip}" | cut -d: -f6)
    HOST=$(echo "${ip}" | cut -d: -f5)
    DHCP=$(echo "${ip}" | cut -d: -f7)
    ;;
  --)
    break
    ;;
  *)
    ;;
  esac
done

if [ "x${HOST}" = "x" ]; then
  echo "hostname could not be detected, will use 'test'"
  HOST=test
fi

# Get the device name (sda, vda, xda, etc) or use default first block device
DEV=${1:-$(ls /dev/?da)}
if [ ! -b "${DEV}" ]; then
  echo "Block device doesn't exist: ${DEV}"
  exit 1
fi

# Get the public key
PUB_KEY=$(cat /root-*/.ssh/authorized_keys 2>/dev/null || cat /root/.ssh/authorized_keys)

echo "The following parameters will be used:
OS=${OS}
IP=${IP1}
NET=${NET1}
GW=${GW1}
ETH=${ETH1}
HOST=${HOST}
DHCP=${DHCP}
PUB_KEY=${PUB_KEY}
DEV=${DEV}
VG_NAME=${VG_NAME}"

read -p "Are you sure you want to proceed? " -r REPLY
echo
if [ "$REPLY" != "y" ]; then
  echo "You didn't type \"y\", exiting..."
  exit 1
fi

trap 'echo Deploy script has failed' INT HUP QUIT TERM USR1

vgchange -an || true
pvremove -ffy ${DEV}* | true
dd if=/dev/zero of=${DEV} bs=1M count=1
sync
udevadm settle
echo -e "n\np\n1\n2048\n\nt\n8e\nw\nq\n" | fdisk -u ${DEV}
echo y | pvcreate ${DEV}1
echo y | vgcreate ${VG_NAME} ${DEV}1
echo y | lvcreate -L2G -n boot ${VG_NAME}
echo y | lvcreate -L6G -n root ${VG_NAME}
echo y | lvcreate -L3G -n var ${VG_NAME}
echo y | lvcreate -l+100%free -n home ${VG_NAME}
mkfs.ext2 /dev/${VG_NAME}/boot
for i in root var home; do mkfs.ext4 /dev/${VG_NAME}/$i ; done
mkdir -p /mnt
mount /dev/${VG_NAME}/root /mnt
for i in boot var home; do mkdir -p /mnt/$i ; done
for i in boot var home; do mount /dev/${VG_NAME}/$i /mnt/$i ; done
# We use default tar, which is copied into "/sbin/tar", since busybox "tar" sometimes return "tar: warning: skipping header 'S'"
curl https://cloud-images.ubuntu.com/${OS}/current/${OS}-server-cloudimg-amd64-root.tar.xz | /sbin/tar -xJf - -C /mnt
echo "/dev/mapper/${VG_NAME}-root   /        ext4   defaults        0 1" > /mnt/etc/fstab
echo "tmpfs                 /tmp     tmpfs  nodev,nosuid    0 0" >> /mnt/etc/fstab
echo "/dev/mapper/${VG_NAME}-boot   /boot    ext2   defaults        0 2" >> /mnt/etc/fstab
echo "/dev/mapper/${VG_NAME}-var    /var     ext4   defaults        0 2" >> /mnt/etc/fstab
echo "/dev/mapper/${VG_NAME}-home   /home    ext4   defaults        0 2" >> /mnt/etc/fstab
echo "tmpfs   /tmp         tmpfs   nodev,nosuid          0  0" >> /mnt/etc/fstab
for i in dev proc sys; do mount --bind /$i /mnt/$i ; done
echo "${IP1} ${HOST}" >> /mnt/etc/hosts
mv /mnt/etc/resolv.conf /mnt/etc/resolv.conf_
echo "nameserver ${GOOGLE_DNS}" >> /mnt/etc/resolv.conf
chroot /mnt apt-get update
DEBIAN_FRONTEND=noninteractive chroot /mnt apt-get install -y grub2 linux-virtual lvm2
set +e
INITRD=$(chroot /mnt update-initramfs -ukall | tee /dev/stderr | awk '/Generating/ {print $3}')
chroot /mnt lsinitramfs ${INITRD} | grep -q lvm
RET=$?
set -e
if [ ${RET} -ne 0 ]; then
  echo "Generated initramfs doesn't contain LVM support!"
  exit 1
fi
chroot /mnt grub-install ${DEV}
# Fix unattended upgrades hang on shutdown (see https://bugs.launchpad.net/bugs/1654600)
if [ -f /mnt/lib/systemd/system/unattended-upgrades.service ]; then
  sed -i "s#ExecStart=#RemainAfterExit=yes\nExecStop=#;" /mnt/lib/systemd/system/unattended-upgrades.service
fi
if lsmod | grep -q r816*; then
  # Build DKMS r8169 ethernet module for Hetzner
  chroot /mnt apt-get install -y r8168-dkms
fi
mv /mnt/etc/resolv.conf_ /mnt/etc/resolv.conf

# Define initial configuration and set default user credentials
mkdir -p /mnt/var/lib/cloud/seed/nocloud
cat > /mnt/var/lib/cloud/seed/nocloud/user-data <<EOF
#cloud-config
package_upgrade: true
hostname: ${HOST}
chpasswd: { expire: False }
ssh_pwauth: True
password: ${PASSWORD}
packages:
  - htop
  - screen
  - mc
  - iftop
users:
  - default:
    ssh-authorized-keys:
      - '${PUB_KEY}'
runcmd:
  - service networking restart
  - ifdown ${ETH1}
  - ifup ${ETH1}
EOF
cat > /mnt/var/lib/cloud/seed/nocloud/meta-data <<-EOF
instance-id: iid-${HOST}
hostname: ${HOST}
dsmode: local
EOF
if [ "${DHCP}" = "off" ]; then
cat >> /mnt/var/lib/cloud/seed/nocloud/meta-data <<-EOF
network-interfaces: |
  auto lo
  iface lo inet loopback
  auto ${ETH1}
  iface ${ETH1} inet static
    address ${IP1}
    netmask ${NET1}
    gateway ${GW1}
    dns-nameservers ${DNS}
EOF
else
cat >> /mnt/var/lib/cloud/seed/nocloud/meta-data <<-EOF
network-interfaces: |
EOF
for iface in $(ip addr | awk -F: '/^[0-9]+/ {print $2}'); do
cat >> /mnt/var/lib/cloud/seed/nocloud/meta-data <<-EOF
auto ${iface}
iface ${iface} inet dhcp
EOF
done
fi

# Permanently define old-school ethX names and set "console=tty1" as a primary console
echo "GRUB_CMDLINE_LINUX_DEFAULT=\"console=ttyS0 console=tty1 net.ifnames=0 biosdevname=0\"" > /mnt/etc/default/grub.d/98-default_ifname.cfg
chroot /mnt update-grub

for i in boot var home dev proc sys; do umount /mnt/$i ; done
umount /mnt
# boot
echo "Ubuntu ${OS} has been installed"
echo "To reboot please enter the command below:"
echo "echo b > /proc/sysrq-trigger"
