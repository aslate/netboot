#version=F44

url --url=https://dl.fedoraproject.org/pub/fedora/linux/releases/44/Everything/x86_64/os/
graphical

lang en_GB.UTF-8
keyboard --xlayouts='gb'
timezone Europe/London --utc

network --bootproto=dhcp --device=link --activate --onboot=on --hostname=fedora-kde-test

zerombr
ignoredisk --only-use=sda
clearpart --all --initlabel --drives=sda
bootloader --boot-drive=sda --timeout=1

part /boot/efi --fstype=efi --size=600 --ondisk=sda
part /boot --fstype=ext4 --size=1024 --ondisk=sda
part pv.01 --grow --size=1 --ondisk=sda
volgroup fedora pv.01
logvol swap --fstype=swap --size=8192 --name=swap --vgname=fedora
logvol / --fstype=xfs --size=51200 --name=root --vgname=fedora
logvol /home --fstype=xfs --grow --size=1 --name=home --vgname=fedora

rootpw --lock
user --name=aslate --groups=wheel --password=changeme --plaintext
sshkey --username=aslate "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIJ1Uaj1C3AEh2tsLAsF6poXdD2GeCmIgG+SLljqPaLPj aslate@cachyos"

selinux --enforcing
firewall --enabled --service=ssh
services --enabled=sshd
firstboot --disable

%packages
@^kde-desktop-environment
openssh-server
sudo
-libreoffice*
-openoffice*
%end

%post
# Force the bundled test password to be replaced at first login.
chage --lastday 0 aslate

# Keep Avahi libraries available if dependencies need them, but mask both
# service units so no Avahi daemon or socket can start after installation.
install -d -m 0755 /etc/systemd/system
ln -sfn /dev/null /etc/systemd/system/avahi-daemon.service
ln -sfn /dev/null /etc/systemd/system/avahi-daemon.socket
ln -sfn /dev/null /etc/systemd/system/avahi-daemon.socket
ln -sfn /dev/null /etc/systemd/system/alsa-restore.service
ln -sfn /dev/null /etc/systemd/system/alsa-state.service
%end

reboot
