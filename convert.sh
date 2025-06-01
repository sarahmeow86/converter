#!/usr/bin/env bash
mv -vf /etc/pacman.conf /etc/pacman.conf.arch
curl https://gitea.artixlinux.org/packages/pacman/raw/branch/master/pacman.conf -o /etc/pacman.conf
mv -vf /etc/pacman.d/mirrorlist /etc/pacman.d/mirrorlist-arch
curl https://gitea.artixlinux.org/packages/artix-mirrorlist/raw/branch/master/mirrorlist -o /etc/pacman.d/mirrorlist
cp -vf /etc/pacman.d/mirrorlist /etc/pacman.d/mirrorlist.artix
pacman -Scc && pacman -Syy
pacman -S artix-keyring
pacman-key --populate artix
pacman-key --lsign-key 95AEC5D0C1E294FC9F82B253573A673A53C01BC2
systemctl list-units --state=running | grep -v systemd | awk '{print $1}' | grep service > daemon.list
pacman -Sw base base-devel grub linux linux-headers mkinitcpio rsync lsb-release esysusers etmpfiles artix-branding-base
pacman -Sw openrc elogind-openrc openrc-system
pacman -Sw runit elogind-runit runit-system
pacman -Sw s6-base elogind-s6 s6-system
pacman -Sw dinit elogind-dinit dinit-system
pacman -Rdd --noconfirm systemd systemd-libs systemd-sysvcompat pacman-mirrorlist dbus
rm -fv /etc/resolv.conf
cp -vf /etc/pacman.d/mirrorlist.artix /etc/pacman.d/mirrorlist
pacman -S base base-devel grub linux linux-headers mkinitcpio rsync lsb-release esysusers etmpfiles artix-branding-base
pacman -S openrc elogind-openrc openrc-system
pacman -S runit elogind-runit runit-system
pacman -S s6-base elogind-s6 s6-system
pacman -S dinit elogind-dinit dinit-system
export LC_ALL=C
pacman -Sl system | grep installed | cut -d" " -f2 | pacman -S -
pacman -Sl world | grep installed | cut -d" " -f2 | pacman -S -
pacman -Sl galaxy | grep installed | cut -d" " -f2 | pacman -S -
pacman -Sl lib32 | grep installed | cut -d" " -f2 | pacman -S -
pacman -S --needed acpid-init alsa-utils-init cronie-init cups-init fuse-init haveged-init hdparm-init openssh-init samba-init syslog-ng-init
for daemon in acpid alsasound cronie cupsd xdm fuse haveged hdparm smb sshd syslog-ng; do rc-update add $daemon default; done
rc-update add udev sysinit
for daemon in acpid alsasound cronie cupsd dbus elogind xdm fuse haveged hdparm smb sshd syslog-ng; do ln -s /etc/runit/sv/$daemon /etc/runit/runsvdir/default; done
touch /etc/s6/adminsv/default/contents.d/{acpid,cronie,cupsd,elogind,xdm,fuse,haveged,hdparm,smbd,sshd,syslog-ng}
s6-db-reload
for daemon in acpid alsasound cronie cupsd xdm fuse haveged hdparm smb sshd syslog-ng; do dinitctl enable $daemon; done
for user in journal journal-gateway timesync network bus-proxy journal-remote journal-upload resolve coredump; do
   userdel systemd-$user
done
rm -vfr /{etc,var/lib}/systemd
mkinitcpio -p linux
mkinitcpio -P 
update-grub
grub-install --target=x86_64-efi --efi-directory=/boot/efi