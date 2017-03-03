Fully functional rescue initramfs for Debian based OS. **Experimental!**
I'd recommend you to test these scripts on VM first, i.e. using https://github.com/kayrus/deploy-vm

# Run

* Copy scripts into destination VM
* Run `sudo ./run_in_os.sh` (you have to use `sudo` and current user's `~/.ssh/authorized_keys` will be used)
* Reboot the VM
* Login using `root` user (if you won't login within 60 secounts, the normal boot will be initiated)

## Default install

* Run `deploy_os.sh` to install the VMWare Ubuntu Xenial image into the `/dev/?da` block device
* Reboot the VM to boot the new OS: `echo b > /proc/sysrq-trigger`

## LVM install

* Run `deploy_os_lvm.sh` to install the Ubuntu Xenial bootstrap files into the `/dev/?da` block device with LVM layout

## RedHat based systems support

This script doesn't support RedHat based OS. In case when you would like to boot into rescue-initramfs from RadHat OS you have to use some tricks:

* Comment out the `run_autoboot_timeout &` string in the `autoboot.sh` script, it doesn't make sense in this scenario.
* Generate initramfs image on some test VM (which runs `linux-image-virtual` image).
* Rename the original `initramfs-*.img` and `vmlinuz-*` to `*_bak` inside the target's `/boot` directory. In case when there are several initramfs files, try to find one which corresponds to `vmlinuz-*` postfix.
* Copy generated `initrd*` along with the `vmlinuz-*` into the target's `/boot` directory using the names which were used by the original files.
* Make a backup of the original grub config. Modify grub config and append proper `ip=` along with the `break=mount` at the end of all strings which start with the `linux`.
* Verify IP address, path's to kernel and initrd.
* Reboot and pray that VM with rescue-initramf will boot.

If you don't want to install Ubuntu image, but just modify/resize filesystems and then reboot, you have to restore original initrd and linux image along with the grub config before the reboot.

# TODO:

* Implement support for several `authorized_keys` entries
* Implement mdadm support
* Test with full LUKS encryption

# In case of problems

In case of problems you can download initial Ubuntu's bootstrap fs and chroot into it to get access to the full Ubuntu environment for further investigation:

```sh
mkdir -p /mnt
curl https://cloud-images.ubuntu.com/xenial/current/xenial-server-cloudimg-amd64-root.tar.xz | tar -xJf - -C /mnt
mount --bind /dev /mnt/dev
mount --bind /proc /mnt/proc
mount --bind /sys /mnt/sys
chroot /mnt bash
```

## Stop and zero mdadm

```sh
mdadm --stop /dev/md0
mdadm --remove /dev/md0
mdadm --zero-superblock /dev/sda
mdadm --zero-superblock /dev/sdb
```

## Unknown host key

Dropbear in Ubuntu Trusty doesn't support ECDSA, but OpenSSH supports it. Thus you can face *known_hosts* problem when RSA/DSS keys are used in Dropbear instead of ECDSA.

# Credits

Inspired by:

* https://blog.tincho.org/posts/Setting_up_my_server:_re-installing_on_an_encripted_LVM/
