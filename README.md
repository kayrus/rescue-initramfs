Fully functional rescue initramfs for Debian based OS. **Experimental!**
I'd recommend you to test these scripts on VM first, i.e. using https://github.com/kayrus/deploy-vm

**Please note the the whole boot disk will be wiped!**

# Run

* Copy scripts into destination VM
* Run `sudo ./run_in_os.sh` (you have to use `sudo` and current user's `~/.ssh/authorized_keys` will be used)
* Reboot the VM
* Login using `root` user (if you won't login within 60 secounts, the normal boot will be initiated)

## Default install

* Run `deploy_os.sh` to install the VMWare Ubuntu Xenial image into the `/dev/?da` block device
* Reboot the VM to boot the new OS: `echo b > /proc/sysrq-trigger`
* After the reboot you have to use `ubuntu` ssh user with your private key.

## Custom install

If you wish to install Ubuntu Trusty with LVM, please run the command below:

```sh
deploy_os_lvm.sh /dev/sda trusty
```

After the reboot you have to use `ubuntu` ssh user with your private key.

## LVM install

* Run `deploy_os_lvm.sh` to install the Ubuntu Xenial bootstrap files into the `/dev/?da` block device with LVM layout
* After the reboot you have to use `ubuntu` ssh user with your private key.

## RedHat based systems support

This script doesn't support RedHat based OS. In case when you would like to boot into rescue-initramfs from RadHat OS you have to use some tricks:

* Generate (run `sudo ./run_in_os.sh`) initramfs image on some test VM (which runs `linux-image-virtual` image).
* On the target host rename the original `/boot/initramfs-*.img` and `/boot/vmlinuz-*` to `*_bak`. In case when there are several initramfs files, try to find one which corresponds to the first GRUB menu entry inside the `/boot/grub/grub.conf` file.
* Copy generated `initrd*` along with the `vmlinuz-*` into the target's `/boot` directory using the names which were used by the original files.
* Make a backup of the original grub config (`/boot/grub/grub.conf`). Modify grub config and append proper `ip=${IP}::${GATEWAY}:${NETWORK}:${HOSTHAME}:eth0:off` along with the `break=mount net.ifnames=0 biosdevname=0 console=ttyS0 console=tty1` at the end of all strings which start with the `kernel`.
* From grub config remove stuff like: `rd_LVM_LV=vglocal20140422/root00 rd_LVM_LV=vglocal20140422/swap00 rd_NO_LUKS pci=bfsort LANG=en_US.UTF-8 rd_NO_MD SYSFONT=latarcyrheb-sun16 crashkernel=auto  KEYBOARDTYPE=pc KEYTABLE=us rd_NO_DM rhgb quiet`
* Verify IP address, path's to kernel and initrd.
* Run the ping command to monitor the server availability status.
* Reboot and pray that VM with rescue-initramf will boot.
* You have 60 seconds from the beginning to log in into the rescue console, so please prepare the `ssh root@%IP%` command in the different terminal window.

If you don't want to install Ubuntu image, but just modify/resize filesystems and then reboot, you have to restore original initrd and linux image along with the grub config before the reboot.

# TODO:

* Implement support for several `authorized_keys` entries
* Implement mdadm support

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

# TODO

* Make sure there is no VG with the same name
