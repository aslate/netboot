#version=RHEL10

url --url=https://repo.almalinux.org/almalinux/10/BaseOS/x86_64/os/
repo --name="appstream" --baseurl=https://repo.almalinux.org/almalinux/10/AppStream/x86_64/os/
repo --name="extras" --baseurl=https://repo.almalinux.org/almalinux/10/extras/x86_64/os/
repo --name="crb" --baseurl=https://repo.almalinux.org/almalinux/10/CRB/x86_64/os/
repo --name="epel" --baseurl=https://dl.fedoraproject.org/pub/epel/10z/Everything/x86_64/
graphical
lang en_GB.UTF-8
keyboard --xlayouts='gb'
timezone Europe/London --utc
network --bootproto=dhcp --device=link --activate --onboot=on --hostname=alma-kde-test

zerombr

%pre --erroronfail
target_disk="$(lsblk -dnpo NAME,TYPE,RM,RO | awk '$2 == "disk" && $3 == "0" && $4 == "0" { print $1; exit }')"
if [ -z "$target_disk" ]; then
    echo 'No non-removable writable installation disk was found.' >&2
    exit 1
fi
target_name="${target_disk#/dev/}"
cat > /tmp/alma10-storage.ks <<EOF
ignoredisk --only-use=$target_name
clearpart --all --initlabel --drives=$target_name
bootloader --boot-drive=$target_name --timeout=1
part /boot/efi --fstype=efi --size=600 --ondisk=$target_name
part /boot --fstype=ext4 --size=1024 --ondisk=$target_name
part pv.01 --grow --size=1 --ondisk=$target_name
EOF
%end

%include /tmp/alma10-storage.ks

volgroup almalinux pv.01
logvol swap --fstype=swap --size=8192 --name=swap --vgname=almalinux
logvol / --fstype=xfs --size=51200 --name=root --vgname=almalinux
logvol /home --fstype=xfs --grow --size=1 --name=home --vgname=almalinux

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
chage --lastday 0 aslate
install -d -m 0755 /etc/systemd/system
ln -sfn /dev/null /etc/systemd/system/avahi-daemon.service
ln -sfn /dev/null /etc/systemd/system/avahi-daemon.socket
%end

reboot
