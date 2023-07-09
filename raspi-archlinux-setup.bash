#!/bin/bash
set -ve

PACKAGES_INITIAL="vim tree byobu git bash-completion sudo hexedit sl wget rsync jq"
PACKAGES_CONTAINER="podman podman-docker podman-compose cockpit cockpit-podman cockpit-storaged"
SCRIPTS_DIR=/root/preconfig-scripts
SCRIPTS_REPO=https://github.com/aadityabhatia/preconfiguration-scripts
CA_PUBKEY_URL=
NTP_SERVER=time.nist.gov
TIMEZONE=US/Eastern
NEW_USER=
NEW_USER_PASSWORD='$y$...$...'
NTP_CONFIG=/etc/systemd/timesyncd.conf

pacman-key --init
pacman-key --populate archlinuxarm

# install packages
pacman --noconfirm -Syu
pacman --noconfirm -S $PACKAGES_INITIAL
pacman --noconfirm -S $PACKAGES_CONTAINER

# set locale and timezone
LOCALE_GEN=/etc/locale.gen
LOCALE_CONF=/etc/locale.conf
grep -E '^en_US.UTF-8' $LOCALE_GEN || { cat > $LOCALE_GEN <<< "en_US.UTF-8 UTF-8" && locale-gen; }
localectl set-keymap us
grep -E '^LANG=' $LOCALE_CONF && sed -i "/^LANG=/d" $LOCALE_CONF || true
cat > $LOCALE_CONF <<< "LANG=en_US.UTF-8"
localectl set-locale LANG=en_US.UTF-8
timedatectl set-timezone $TIMEZONE

test -d $SCRIPTS_DIR || git clone $SCRIPTS_REPO $SCRIPTS_DIR
test -f /etc/ssh/ca.pub || bash $SCRIPTS_DIR/ssh-config.bash $CA_PUBKEY_URL
grep -E $NTP_SERVER $NTP_CONFIG || bash $SCRIPTS_DIR/timesyncd-ntp-server.bash $NTP_SERVER

# restart SSHD to enable certificate authentication
systemctl restart sshd

# enable sudo insults
cat > /etc/sudoers.d/insults <<< "Defaults insults"
cat > /etc/sudoers.d/wheel <<< "%wheel ALL=(ALL:ALL) ALL"

userdel -r alarm
useradd -u 1000 -s /bin/bash -G wheel -m -k /etc/skel $NEW_USER
chpasswd -e <<< $NEW_USER:$NEW_USER_PASSWORD
passwd -d root

# success
