#version=RHEL10
#
# Basic AlmaLinux 10 Server with GUI installation.
# WARNING: the first non-removable writable disk is erased and repartitioned.
# The requested temporary password is intentionally stored in plaintext.

graphical --non-interactive
lang en_GB.UTF-8
keyboard --xlayouts='gb'
timezone Europe/London --utc

network --bootproto=dhcp --device=link --activate --onboot=on

zerombr

%pre
# Select the first non-removable writable disk without assuming /dev/sda or
# an NVMe device name. PXE installs normally have no removable install media.
target_disk="$(lsblk -dnpo NAME,TYPE,RM,RO | awk '$2 == "disk" && $3 == "0" && $4 == "0" { print $1; exit }')"
if [ -z "$target_disk" ]; then
    echo 'No non-removable writable disk was found.' >&2
    exit 1
fi
target_name="${target_disk#/dev/}"
cat > /tmp/alma10-disk.ks <<EOF
ignoredisk --only-use=$target_name
clearpart --all --initlabel --drives=$target_name
autopart --type=lvm
EOF
%end

%include /tmp/alma10-disk.ks

rootpw --lock
user --name=aslate --groups=wheel --password=changeme --plaintext

selinux --enforcing
firewall --enabled --service=ssh
services --enabled=sshd

%packages
@^graphical-server-environment
%end

reboot
