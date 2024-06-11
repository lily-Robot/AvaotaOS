#!/bin/bash

__usage="
Usage: mkubuntu [OPTIONS]
Build Ubuntu rootfs.
Run in root user.
The target rootfs will be generated in the build folder of the directory where the mkubuntu.sh script is located.

Options: 
  -m, --mirror MIRROR_ADDR         The URL/path of target mirror address.
  -r, --rootfs ROOTFS_DIR          The directory name of ubuntu rootfs.
  -v, --version UBUNTU_VER         The version of ubuntu/debian.
  -a, --arch ARCH                  The arch of ubuntu/debian.
  -t, --type ROOTFS_TYPE           The type of rootfs: cli, xfce, gnome, kde.
  -u, --user SYS_USER              The normal user of rootfs.
  -p, --password SYS_PASSWORD      The password of user.
  -s, --supassword ROOT_PASSWORD   The password of root.
  -h, --help                       Show command help.
"

help()
{
    echo "$__usage"
    exit $1
}

default_param() {
    ARCH=aarch64
    ROOTFS=rootfs
    VERSION=jammy
    TYPE=cli
    if [[ "${VERSION}" == "jammy" || "${VERSION}" == "noble" ]];then
        MIRROR=http://ports.ubuntu.com
    elif [[ "${VERSION}" == "bookworm" || "${VERSION}" == "trixie" ]];then
        MIRROR=http://deb.debian.org/debian
    fi
    SYS_USER=avaota
    SYS_PASSWORD=avaota
    ROOT_PASSWORD=avaota
}

parseargs()
{
    if [ "x$#" == "x0" ]; then
        return 0
    fi

    while [ "x$#" != "x0" ];
    do
        if [ "x$1" == "x-h" -o "x$1" == "x--help" ]; then
            return 1
        elif [ "x$1" == "x" ]; then
            shift
        elif [ "x$1" == "x-m" -o "x$1" == "x--mirror" ]; then
            MIRROR=`echo $2`
            shift
            shift
        elif [ "x$1" == "x-r" -o "x$1" == "x--rootfs" ]; then
            ROOTFS=`echo $2`
            shift
            shift
        elif [ "x$1" == "x-v" -o "x$1" == "x--version" ]; then
            VERSION=`echo $2`
            shift
            shift
        elif [ "x$1" == "x-a" -o "x$1" == "x--arch" ]; then
            ARCH=`echo $2`
            shift
            shift
        elif [ "x$1" == "x-t" -o "x$1" == "x--type" ]; then
            TYPE=`echo $2`
            shift
            shift
        elif [ "x$1" == "x-c" -o "x$1" == "x--config" ]; then
            LINUX_CONFIG=`echo $2`
            shift
            shift
        elif [ "x$1" == "x-u" -o "x$1" == "x--user" ]; then
            SYS_USER=`echo $2`
            shift
            shift
        elif [ "x$1" == "x-p" -o "x$1" == "x--password" ]; then
            SYS_PASSWORD=`echo $2`
            shift
            shift
        elif [ "x$1" == "x-s" -o "x$1" == "x--supassword" ]; then
            ROOT_PASSWORD=`echo $2`
            shift
            shift
        else
            echo `date` - ERROR, UNKNOWN params "$@"
            return 2
        fi
    done
}

UMOUNT_ALL(){
    set +e
    if grep -q "${ROOTFS}/dev " /proc/mounts ; then
        umount -l ${ROOTFS}/dev
    fi
    if grep -q "${ROOTFS}/proc " /proc/mounts ; then
        umount -l ${ROOTFS}/proc
    fi
    if grep -q "${ROOTFS}/sys " /proc/mounts ; then
        umount -l ${ROOTFS}/sys
    fi
    set -e
}

INSTALL_PACKAGES(){
    for item in $(cat $1)
    do
        LC_ALL=C LANGUAGE=C LANG=C chroot ${ROOTFS} apt-get install -y ${item}
        if [ $? == 0 ]; then
            echo "install $item."
        else
            echo "can not install $item."
        fi
    done
}

HOST_ARCH=$(arch)

default_param
parseargs "$@" || help $?

echo You are running this scipt on a ${HOST_ARCH} mechine....

if [ -d ${ROOTFS} ];then rm -rf ${ROOTFS}; fi
mkdir ${ROOTFS}

if [ "${ARCH}" == "aarch64" ];then
sudo debootstrap --foreign --no-check-gpg --arch=arm64 ${VERSION} ${ROOTFS} ${MIRROR}
elif [ "${ARCH}" == "armhf" ];then
sudo debootstrap --foreign --no-check-gpg --arch=armhf ${VERSION} ${ROOTFS} ${MIRROR}
else
echo "unsupported arch."
exit 2
fi

if [ "${HOST_ARCH}" != "${ARCH}" ];then
sudo cp /usr/bin/qemu-${ARCH}-static ${ROOTFS}/usr/bin
else
echo "You are running this script on a ${ARCH} mechine, progress...."
fi

sudo LC_ALL=C LANGUAGE=C LANG=C chroot ${ROOTFS} /debootstrap/debootstrap --second-stage
sudo LC_ALL=C LANGUAGE=C LANG=C chroot ${ROOTFS} dpkg --configure -a

if [ "${VERSION}" == "jammy" ];then
    cat ../target/conf/jammy/sources.list > ${ROOTFS}/etc/apt/sources.list
    sed -i "s|http://ports.ubuntu.com/ubuntu-ports|${MIRROR}|g" ${ROOTFS}/etc/apt/sources.list
elif [ "${VERSION}" == "noble" ];then
     "# Ubuntu sources have moved to /etc/apt/sources.list.d/ubuntu.sources" > ${ROOTFS}/etc/apt/sources.list
    cat ../target/conf/noble/ubuntu.sources > ${ROOTFS}/etc/apt/sources.list.d/ubuntu.sources
    sed -i "s|http://ports.ubuntu.com/ubuntu-ports|${MIRROR}|g" ${ROOTFS}/etc/apt/sources.list.d/ubuntu.sources
elif [[ "${VERSION}" == "bookworm" || "${VERSION}" == "trixie" ]];then
    rm ${ROOTFS}/etc/apt/sources.list
    cat ../target/conf/debian-common-new/debian.sources > ${ROOTFS}/etc/apt/sources.list.d/debian.sources
    sed -i "s|http://deb.debian.org/debian|${MIRROR}|g" ${ROOTFS}/etc/apt/sources.list.d/debian.sources
    sed -i "s|VERSION|${VERSION}|g" ${ROOTFS}/etc/apt/sources.list.d/debian.sources
fi

mount --bind /dev ${ROOTFS}/dev
mount -t proc /proc ${ROOTFS}/proc
mount -t sysfs /sys ${ROOTFS}/sys

cp -b /etc/resolv.conf ${ROOTFS}/etc/resolv.conf

trap 'UMOUNT_ALL' EXIT

LC_ALL=C LANGUAGE=C LANG=C chroot ${ROOTFS} apt-get update

INSTALL_PACKAGES ../os/${VERSION}.conf

if [[ "${VERSION}" == "jammy" || "${VERSION}" == "noble" ]];then
    XFCE_DESKTOP="xubuntu-desktop"
    GNOME_DESKTOP="ubuntu-desktop"
    KDE_DESKTOP="kubuntu-desktop"
    LXQT_DESKTOP="lubuntu-desktop"
elif [[ "${VERSION}" == "bookworm" || "${VERSION}" == "trixie" ]];then
    XFCE_DESKTOP="xorg xinput xfce4 desktop-base lightdm xfce4-terminal tango-icon-theme xfce4-notifyd xfce4-power-manager pulseaudio pulseaudio-module-bluetooth alsa-utils dbus-user-session eject gvfs gvfs-backends udisks2 e2fsprogs libblockdev-crypto2 blueman xarchiver"
    GNOME_DESKTOP="gnome-core avahi-daemon desktop-base file-roller gnome-tweaks gstreamer1.0-libav gstreamer1.0-plugins-ugly libgsf-bin libproxy1-plugin-networkmanager network-manager-gnome"
    KDE_DESKTOP="kde-plasma-desktop"
    LXQT_DESKTOP="xorg xinput lxqt pulseaudio pulseaudio-module-bluetooth alsa-utils dbus-user-session eject gvfs gvfs-backends udisks2 e2fsprogs libblockdev-crypto2 blueman xarchiver"
fi

if [ "${TYPE}" != "cli" ];then
    echo "Build desktop image."
    if [ "${TYPE}" == "xfce" ];then
        INCLUDE_PACKAGES="${XFCE_DESKTOP}"
    elif [ "${TYPE}" == "gnome" ];then
        INCLUDE_PACKAGES="${GNOME_DESKTOP}"
    elif [ "${TYPE}" == "kde" ];then
        INCLUDE_PACKAGES="${KDE_DESKTOP}"
    elif [ "${TYPE}" == "lxqt" ];then
        INCLUDE_PACKAGES="${LXQT_DESKTOP}"
    else
        echo "unsupported desktop type."
        exit 2
    fi
    LC_ALL=C LANGUAGE=C LANG=C chroot ${ROOTFS} apt-get install -y ${INCLUDE_PACKAGES}
fi

cp -r ${LINUX_CONFIG}-kernel-pkgs ${ROOTFS}/kernel-deb

cat <<EOF | LC_ALL=C LANGUAGE=C LANG=C chroot ${ROOTFS}
dpkg -i /kernel-deb/*.deb
EOF

rm -rf ${ROOTFS}/kernel-deb

#SYS_USER=avaota
#SYS_PASSWORD=avaota
#ROOT_PASSWORD=avaota

cat <<EOF | chroot ${ROOTFS} adduser ${SYS_USER} && addgroup ${SYS_USER} sudo
${SYS_USER}
${SYS_PASSWORD}
${SYS_PASSWORD}
0
0
0
0
y
EOF

# username：avaota
# password：avaota

cat <<EOF | chroot ${ROOTFS} passwd root
${ROOT_PASSWORD}
${ROOT_PASSWORD}
EOF

# username：root
# password：avaota

sed -i "s|#PermitRootLogin prohibit-password|PermitRootLogin yes|g" ${ROOTFS}/etc/ssh/sshd_config

# Allow root ssh login

if [[ "${VERSION}" == "jammy" || "${VERSION}" == "noble" ]];then
    LC_ALL=C LANGUAGE=C LANG=C chroot ${ROOTFS} netplan set ethernets.eth0.dhcp4=true
    LC_ALL=C LANGUAGE=C LANG=C chroot ${ROOTFS} netplan set ethernets.eth0.dhcp6=true
    LC_ALL=C LANGUAGE=C LANG=C chroot ${ROOTFS} netplan set ethernets.eth1.dhcp4=true
    LC_ALL=C LANGUAGE=C LANG=C chroot ${ROOTFS} netplan set ethernets.eth1.dhcp6=true
    LC_ALL=C LANGUAGE=C LANG=C chroot ${ROOTFS} sudo chmod 600 /etc/netplan/*.yaml
elif [[ "${VERSION}" == "bookworm" || "${VERSION}" == "trixie" ]];then
    LC_ALL=C LANGUAGE=C LANG=C chroot ${ROOTFS} apt-get update
    LC_ALL=C LANGUAGE=C LANG=C chroot ${ROOTFS} apt-get install ifupdown
fi

if [ "${ARCH}" == "aarch64" ];then
LC_ALL=C LANGUAGE=C LANG=C chroot ${ROOTFS} dpkg --add-architecture armhf
LC_ALL=C LANGUAGE=C LANG=C chroot ${ROOTFS} apt-get update
LC_ALL=C LANGUAGE=C LANG=C chroot ${ROOTFS} apt-get install libc6:armhf libstdc++6:armhf -y
fi

LC_ALL=C LANGUAGE=C LANG=C chroot ${ROOTFS} apt-get update
LC_ALL=C LANGUAGE=C LANG=C chroot ${ROOTFS} apt-get upgrade -y

chroot ${ROOTFS} apt clean

cp ../target/services/init-resize/init-resize.sh ${ROOTFS}/usr/local/bin
cp ../target/services/init-resize/init-resize.service ${ROOTFS}/etc/systemd/system/

chmod +x ${ROOTFS}/usr/local/bin/init-resize.sh

chroot ${ROOTFS} sudo systemctl enable init-resize.service

if [ "$HOST_ARCH" != "$ARCH" ];then
sudo rm ${ROOTFS}/usr/bin/qemu-${ARCH}-static
else
echo "You are running this script on a ${ARCH} mechine, progress...."
fi

echo '127.0.0.1	avaota-sbc' >> ${ROOTFS}/etc/hosts

cat /dev/null > ${ROOTFS}/etc/hostname
echo 'avaota-sbc' >> ${ROOTFS}/etc/hostname

echo "avaota ALL=(ALL) NOPASSWD: ALL" >> ${ROOTFS}/etc/sudoers.d/010_avaota-nopassword

cat /dev/null > ${ROOTFS}/etc/fstab

cat <<EOF >> ${ROOTFS}/etc/fstab
LABEL=boot      /boot           vfat    defaults          0       0
LABEL=rootfs    /               ext4    defaults,noatime  0       1
EOF

UMOUNT_ALL

mv ${ROOTFS} ubuntu-${VERSION}-${TYPE}
touch ubuntu-${VERSION}-${TYPE}/THIS-IS-NOT-YOUR-ROOT