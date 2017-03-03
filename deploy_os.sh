#!/bin/sh -e

IP1=192.168.122.2
NET1=255.255.255.0
GW1=192.168.122.1
ETH1=eth0
HOST=test
DHCP=off
DNS=8.8.8.8
PASSWORD=passw0rd

for arg in $(cat /proc/cmdline); do
  case "$arg" in
  ip=*)
    # ip=${IP}::${GW}:${NET}:${HOST}:${DEV}:off
    ip="${arg#ip=}"
    echo "Using IP address passed as kernel parameter: ip=${ip}"
    IP1=$(echo $ip | cut -d: -f1)
    NET1=$(echo $ip | cut -d: -f4)
    GW1=$(echo $ip | cut -d: -f3)
    ETH1=$(echo $ip | cut -d: -f6)
    HOST=$(echo $ip | cut -d: -f5)
    DHCP=$(echo $ip | cut -d: -f7)
    ;;
  --)
    break
    ;;
  *)
    ;;
  esac
done

# Get the device name (sda, vda, xda, etc) or use default first block device
DEV=${1:-$(ls /dev/?da)}
if [ ! -b "${DEV}" ]; then
  echo "Block device doesn't exist: ${DEV}"
  exit 1
fi

# Get the public key
PUB_KEY=$(cat /root-*/.ssh/authorized_keys 2>/dev/null || cat /root/.ssh/authorized_keys)

echo "The following parameters will be used:
IP=${IP1}
NET=${NET1}
GW=${GW1}
ETH=${ETH1}
HOST=${HOST}
DHCP=${DHCP}
PUB_KEY=${PUB_KEY}
DEV=${DEV}"

read -p "Are you sure you want to proceed? " -r REPLY
echo
if [ "$REPLY" != "y" ]; then
  echo "You didn't type \"y\", exiting..."
  exit 1
fi

# Download and write a VMWare Ubuntu Xenial image
if [ ! -f xenial-server-cloudimg-amd64-disk1.vmdk ]; then
  curl -O https://cloud-images.ubuntu.com/xenial/current/xenial-server-cloudimg-amd64-disk1.vmdk
fi
qemu-img convert -f vmdk -O raw xenial-server-cloudimg-amd64-disk1.vmdk ${DEV}

# inform the OS of partition table changes
sync
udevadm settle

# Create mount point and mount brand new FS onto /mnt
mkdir -p /mnt
mount ${DEV}1 /mnt

# Define initial configuration and set default user credentials
mkdir -p /mnt/var/lib/cloud/seed/nocloud
cat > /mnt/var/lib/cloud/seed/nocloud/user-data <<EOF
#cloud-config
apt_upgrade: true
hostname: ${HOST}
chpasswd: { expire: False }
ssh_pwauth: True
password: ${PASSWORD}
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
# Define old-school ethX names for the next boot and set "console=tty1" as a primary console
sed -i 's#\(console=ttyS0\)$#\1 console=tty1 net.ifnames=0 biosdevname=0#g' /mnt/boot/grub/grub.cfg

if lsmod | grep -q r816*; then
  # Build DKMS r8169 ethernet module for Hetzner
  for i in dev proc sys; do mount --bind /$i /mnt/$i ; done
  mv /mnt/etc/resolv.conf /mnt/etc/resolv.conf_
  echo nameserver 8.8.8.8 >> /mnt/etc/resolv.conf
  chroot /mnt apt-get update
  chroot /mnt apt-get install -y r8168-dkms
  mv /mnt/etc/resolv.conf_ /mnt/etc/resolv.conf
  for i in dev proc sys; do umount /mnt/$i ; done
fi

umount /mnt
# boot
echo "Ubuntu Xenial has been installed"
echo "To reboot please enter the command below:"
echo "echo b > /proc/sysrq-trigger"
