#!/bin/sh -e

case $1 in
prereqs)
        exit 0
        ;;
esac

. /usr/share/initramfs-tools/hook-functions

for e in /sbin/vg* /sbin/lv* /sbin/pv*; do
  cp -a $e ${DESTDIR}/bin/$(basename $e)
done

cat <<EOF > ${DESTDIR}/bin/boot
#!/bin/sh
kill -9 \$(ps | grep '[s]h -i' | awk '{print \$1}')
EOF
chmod +x ${DESTDIR}/bin/boot

copy_exec "/sbin/fdisk" "/bin/"
copy_exec "/usr/bin/qemu-img" "/bin/"
copy_exec "/usr/bin/curl" "/bin/"
copy_exec "/usr/bin/scp" "/bin/"

# Copy mkfs
copy_exec "/sbin/mke2fs" "/sbin/"
ln -s mke2fs "${DESTDIR}/sbin/mkfs.ext4"
ln -s mke2fs "${DESTDIR}/sbin/mkfs.ext2"

# Copy certificates
cp -a /etc/ssl ${DESTDIR}/etc/ssl
mkdir -p ${DESTDIR}/usr/share/
cp -a /usr/share/ca-certificates ${DESTDIR}/usr/share/
# Fix DNS resolver
cp -a /lib/x86_64-linux-gnu/libnss_dns* ${DESTDIR}/lib/x86_64-linux-gnu/
echo "nameserver 8.8.8.8" > ${DESTDIR}/etc/resolv.conf
cp -a /etc/initramfs-tools/bin/deploy_os*.sh ${DESTDIR}/bin/
# Define /sbin PATH for dropbear user
TMP_ROOT_DIR=$(ls -d ${DESTDIR}/root-* 2>/dev/null || ls -d ${DESTDIR}/root)
echo 'export PATH=$PATH:/sbin:/usr/sbin' > "${TMP_ROOT_DIR}/.profile"
# Stop the autoboot on timeout
echo 'touch /tmp/noautoboot' >> "${TMP_ROOT_DIR}/.profile"
