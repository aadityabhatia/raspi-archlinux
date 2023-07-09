#!/bin/bash
set -e
test $UID -ne 0 && echo Must be root. && exit 2

ARCHLINUX_URL=http://os.archlinuxarm.org/os/ArchLinuxARM-rpi-aarch64-latest.tar.gz
DISK_IMAGE_PATH=$PWD
ARCHLINUX_FILENAME=ArchLinuxARM-rpi-aarch64-latest.tar.gz
ARCHLINUX_GPG_FINGERPRINT=68B3537F39A313B3E574D06777193F152BDBE6A6

CA_PUBKEY_URL=
NTP_CONFIG=/etc/systemd/timesyncd.conf
NTP_SERVER=time.nist.gov
HOSTNAME_LIST=$PWD/pokemon.txt

DEVICE=$1

# ensure $DEVICE is block device
test -b $DEVICE || { echo Not a block device: $DEVICE && exit 2; }

PARTITIONS=$(lsblk -r $DEVICE | awk '/part/ {print $1}')

printf "Device:\n"

# display disk information
lsblk -o NAME,SIZE,TYPE,VENDOR,MODEL,REV,SERIAL,STATE $DEVICE

printf "\nPartitions:\n"

sgdisk -p $DEVICE

# display actions
printf "\nAbout to erase $DEVICE... "

# prompt for user confirmation
read -p "Proceed? [y/N] " -n 1 -r proceed
test "y$proceed" != "yy" && test "y$proceed" != "yY" && echo "Aborted." && exit

printf "\nPreparing $DEVICE for Linux.\n"
date

for partition in $PARTITIONS; do
	printf "\nErasing $partition...\n"
	umount -vq /dev/$partition || true
	dd if=/dev/zero of=/dev/$partition count=200 status=none
done

printf "\nAttempting to execute TRIM on $DEVICE"
blkdiscard -f $DEVICE || true

printf "\nPartitioning $DEVICE...\n"

sgdisk -Z $DEVICE

# GPT
# sgdisk -o -n 1:4M:400M -c 1:boot -t 1:b000 -n 2::0 -c 2:raspi -t 2:8305 -p $DEVICE

# MBR
sfdisk $DEVICE <<EOF
label: dos

, 400MiB, c, *
,+,L
EOF

partprobe -s $DEVICE

printf "\nCreating filesystems...\n"

mkfs.vfat -v -F 32 -n "BOOT" ${DEVICE}1
mkfs.ext4 -v -m 1 ${DEVICE}2

printf "Mounting new partitions...\n"

TEMP_DIR=$(mktemp -d)
mkdir $TEMP_DIR/boot $TEMP_DIR/root
mount -v ${DEVICE}1 $TEMP_DIR/boot
mount -v ${DEVICE}2 $TEMP_DIR/root

if [ ! -f $DISK_IMAGE_PATH/$ARCHLINUX_FILENAME ]; then
	printf "\nDisk image not found. Downloading... \n"
	wget $ARCHLINUX_URL -nv -O $DISK_IMAGE_PATH/$ARCHLINUX_FILENAME
	wget $ARCHLINUX_URL.sig -nv -O $DISK_IMAGE_PATH/$ARCHLINUX_FILENAME.sig
fi

printf "\nVerifying GPG signatures...\n"
gpg --recv-keys $ARCHLINUX_GPG_FINGERPRINT
gpg --verify $DISK_IMAGE_PATH/$ARCHLINUX_FILENAME.sig

printf "\nExtracting: $ARCHLINUX_FILENAME... "
bsdtar -C $TEMP_DIR/root/ -zxp -f $DISK_IMAGE_PATH/$ARCHLINUX_FILENAME
printf "done.\n"

printf "\nMoving boot partition contents to ${DEVICE}1... "
mv $TEMP_DIR/root/boot/* $TEMP_DIR/boot/
printf "done.\n"

printf "\nCopying initial setup scripts...\n"
cp -v raspi-archlinux-setup.bash $TEMP_DIR/root/root/
git clone https://git.screaming.ninja/scripts/preconfiguration-scripts $TEMP_DIR/root/root/preconfig-scripts

printf "\nSetting hostname... "
NEW_HOSTNAME=$(shuf -n 1 $HOSTNAME_LIST)
tee $TEMP_DIR/root/etc/hostname <<< $NEW_HOSTNAME

printf "\nSetting up SSH...\n"
# download trusted CA keys from the URL
wget $CA_PUBKEY_URL --connect-timeout 3 -nv -O $TEMP_DIR/root/etc/ssh/ca.pub
cat >> $TEMP_DIR/root/etc/ssh/sshd_config <<EOF

# bootstrap $(date +%Y%m%d)
PasswordAuthentication no
TrustedUserCAKeys /etc/ssh/ca.pub
EOF

printf "\nSetting up timesyncd... "

# delete NTP entry if present
grep -E '^NTP' $TEMP_DIR/root$NTP_CONFIG && sed -i "/^NTP/d" $TEMP_DIR/root$NTP_CONFIG || true

# add NTP server entry
cat >> $TEMP_DIR/root$NTP_CONFIG <<EOF

# bootstrap $(date +%Y%m%d)
NTP=$NTP_SERVER
EOF

printf "done.\n"

for dir in boot root; do
	printf "Syncing filesystem: $dir... "
	sync -f $TEMP_DIR/$dir
	printf "done.\n"
done

printf "\nUnmounting partitions: ${DEVICE}1 ${DEVICE}2...\n"
umount -v ${DEVICE}1 ${DEVICE}2

date
printf "Success!\n"
