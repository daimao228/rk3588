#!/bin/bash

SDK_DIR="$(pwd)"
TARGET_ROOTFS_DIR="ubuntu_rootfs"

if [ "$EUID" -ne 0 ]; then
    echo "错误：请使用 sudo 运行此脚本！"
    exit 1
fi

echo "脚本正在以 root 权限运行！"

if [ $# -ne 3 ]; then
    echo "错误：请传入恰好三个参数！"
    echo "用法：$0 <用户名> <用户密码(6位)> <root密码(6位)>"
    exit 1
fi
usrname=$1
usr_passwd=$2
root_passwd=$3
wget https://mirrors.bfsu.edu.cn/ubuntu-cdimage/ubuntu-base/releases/22.04.2/release/ubuntu-base-22.04.2-base-arm64.tar.gz

sudo apt-get install git ssh make gcc libssl-dev liblz4-tool  expect g++ patchelf chrpath gawk texinfo chrpath diffstat binfmt-support qemu-user-static live-build bison flex fakeroot cmake gcc-multilib g++-multilib unzip device-tree-compiler ncurses-dev  python-is-python3 python-dev-is-python3 -y 

# 创建一个文件夹存放根文件系统
mkdir  ${SDK_DIR}/ubuntu_rootfs
# 解压到文件夹
sudo tar -xvf ubuntu-base-22.04.2-base-arm64.tar.gz -C ${SDK_DIR}/ubuntu_rootfs/

sudo cp /etc/resolv.conf ${SDK_DIR}/ubuntu_rootfs/etc/resolv.conf
sudo echo "nameserver 8.8.8.8" >> ${SDK_DIR}/ubuntu_rootfs/etc/resolv.conf
sudo echo "nameserver 114.114.114.114" >> ${SDK_DIR}/ubuntu_rootfs/etc/resolv.conf

echo "" > ${SDK_DIR}/ubuntu_rootfs/etc/apt/sources.list

cat << EOF > ${SDK_DIR}/ubuntu_rootfs/etc/apt/sources.list
# 默认注释了源码镜像以提高 apt update 速度，如有需要可自行取消注释
deb http://mirrors.bfsu.edu.cn/ubuntu-ports/ jammy main restricted universe multiverse
# deb-src http://mirrors.bfsu.edu.cn/ubuntu-ports/ jammy main restricted universe multiverse
deb http://mirrors.bfsu.edu.cn/ubuntu-ports/ jammy-updates main restricted universe multiverse
# deb-src http://mirrors.bfsu.edu.cn/ubuntu-ports/ jammy-updates main restricted universe multiverse
deb http://mirrors.bfsu.edu.cn/ubuntu-ports/ jammy-backports main restricted universe multiverse
# deb-src http://mirrors.bfsu.edu.cn/ubuntu-ports/ jammy-backports main restricted universe multiverse

# deb http://mirrors.bfsu.edu.cn/ubuntu-ports/ jammy-security main restricted universe multiverse
# # deb-src http://mirrors.bfsu.edu.cn/ubuntu-ports/ jammy-security main restricted universe multiverse

deb http://ports.ubuntu.com/ubuntu-ports/ jammy-security main restricted universe multiverse
# deb-src http://ports.ubuntu.com/ubuntu-ports/ jammy-security main restricted universe multiverse

# 预发布软件源，不建议启用
# deb http://mirrors.bfsu.edu.cn/ubuntu-ports/ jammy-proposed main restricted universe multiverse
# # deb-src http://mirrors.bfsu.edu.cn/ubuntu-ports/ jammy-proposed main restricted universe multiverse
EOF

sudo cp /usr/bin/qemu-aarch64-static ${SDK_DIR}/ubuntu_rootfs/usr/bin/

touch mount.sh

cat << EOF > ${SDK_DIR}/./mount.sh
#!/bin/bash
mnt() {
	echo "MOUNTING"
	sudo mount -t proc /proc \${2}proc
	sudo mount -t sysfs /sys \${2}sys
	sudo mount -o bind /dev \${2}dev
	sudo mount -o bind /dev/pts \${2}dev/pts
	# sudo chroot \${2}
}
umnt() {
	echo "UNMOUNTING"
	sudo umount \${2}proc
	sudo umount \${2}sys
	sudo umount \${2}dev/pts
	sudo umount \${2}dev
}

if [ "\$1" == "-m" ] && [ -n "\$2" ] ;
then
	mnt \$1 \$2
elif [ "\$1" == "-u" ] && [ -n "\$2" ];
then
	umnt \$1 \$2
else
	echo ""
	echo "Either 1'st, 2'nd or both parameters were missing"
	echo ""
	echo "1'st parameter can be one of these: -m(mount) OR -u(umount)"
	echo "2'nd parameter is the full path of rootfs directory(with trailing '/')"
	echo ""
	echo "For example: ch-mount -m /media/sdcard/"
	echo ""
	echo 1st parameter : \${1}
	echo 2nd parameter : \${2}
fi
EOF

sudo chmod +x mount.sh

touch ${SDK_DIR}/${TARGET_ROOTFS_DIR}/usr/local/bin/autoexpand.sh

cat << EOF > ${SDK_DIR}/${TARGET_ROOTFS_DIR}/usr/local/bin/autoexpand.sh
#!/bin/bash

ROOT_PARTITION=\$(lsblk | grep "/$" | awk '{print \$1}'| sed 's/^..//')
DEVICE=\${ROOT_PARTITION%p*}
ROOT_DIR=/dev/\${ROOT_PARTITION}
NUM="\${ROOT_PARTITION: -1}"

echo -e "\n" | parted /dev/\${DEVICE} resizepart \${NUM}
echo -e "\n" | resize2fs \${ROOT_DIR}

echo '扩容根目录已完成'
EOF

touch ${SDK_DIR}/${TARGET_ROOTFS_DIR}/etc/systemd/system/autoexpand.service

cat << EOF > ${SDK_DIR}/${TARGET_ROOTFS_DIR}/etc/systemd/system/autoexpand.service
[Unit]
Description=Run My Script Once at Boot

[Service]
Type=oneshot
ExecStart=/bin/bash -c 'if [ ! -f /tmp/auto_expand_done ]; then /usr/local/bin/autoexpand.sh; touch /tmp/auto_expand_done; fi'

[Install]
WantedBy=multi-user.target
EOF


./mount.sh -m ${TARGET_ROOTFS_DIR}/

cat << EOF | sudo chroot ${TARGET_ROOTFS_DIR}/
echo "Setting up environment..."

apt update
apt upgrade -y
mv /var/lib/dpkg/info/ /var/lib/dpkg/info_old/
mkdir /var/lib/dpkg/info
apt-get update
apt-get install
apt-get install vim bash-completion net-tools iputils-ping ifupdown ethtool ssh rsync udev htop rsyslog curl openssh-server apt-utils dialog nfs-common psmisc language-pack-en-base sudo kmod apt-transport-https gcc g++ make cmake  fdisk -y

echo "LANG=zh_CN.UTF-8" >> /etc/default/locale
locale-gen zh_CN.UTF-8
update-locale LANG=zh_CN.UTF-8
source /etc/default/locale
sudo DEBIAN_FRONTEND=noninteractive apt-get install network-manager -y -q
echo "Network Manager installation finished"

sudo echo "[keyfile]" > /usr/lib/NetworkManager/conf.d/10-globally-managed-devices.conf
sudo echo "unmanaged-devices=*,except:type:ethernet,except:type:wifi,except:type:gsm,except:type:cdma" >> /usr/lib/NetworkManager/conf.d/10-globally-managed-devices.conf

echo "RK3588" > /etc/hostname
echo "127.0.0.1 localhost" >> /etc/hosts
echo "127.0.0.1 RK3588" >> /etc/hosts
echo "127.0.0.1 localhost RK3588" >> /etc/hosts

systemctl mask sleep.target suspend.target hibernate.target hybrid-sleep.target

sed -i 's/TimeoutStartSec=5min/TimeoutStartSec=5sec/g' /lib/systemd/system/networking.service
cat /lib/systemd/system/networking.service

sudo chmod +x /usr/local/bin/autoexpand.sh

sudo systemctl enable autoexpand.service

sed -i 's/#   PasswordAuthentication yes/ PasswordAuthentication yes/g' /etc/ssh/ssh_config
sed -i 's/#PermitRootLogin prohibit-password/PermitRootLogin yes/g' /etc/ssh/sshd_config

mkdir /app

apt install picocom i2c-tools usbutils -y
sudo apt install libgpiod-dev -y
apt install gpiod -y

echo -e "$root_passwd\n$root_passwd" | sudo passwd root
echo -e "$usr_passwd\n$usr_passwd" | sudo adduser $usrname

echo "$usrname  ALL=(ALL:ALL) ALL" >> /etc/sudoers

EOF

./mount.sh -u ${TARGET_ROOTFS_DIR}/

touch mk-image.sh

cat << EOF > ${SDK_DIR}/mk-image.sh
#!/bin/bash -e

TARGET_ROOTFS_DIR=./ubuntu_rootfs # 定义目标根文件系统目录路径
ROOTFSIMAGE=ubuntu-rootfs.img # 定义根文件系统镜像文件名
EXTRA_SIZE_MB=300 # 定义额外的磁盘空间大小
IMAGE_SIZE_MB=\$(( \$(sudo du -sh -m \${TARGET_ROOTFS_DIR} | cut -f1) + \${EXTRA_SIZE_MB} )) # 计算根文件系统镜像文件大小

echo Making rootfs! # 输出提示信息

if [ -e \${ROOTFSIMAGE} ]; then # 如果根文件系统镜像文件已经存在，则删除
rm \${ROOTFSIMAGE}
fi

dd if=/dev/zero of=\${ROOTFSIMAGE} bs=1M count=0 seek=\${IMAGE_SIZE_MB} # 创建指定大小的空白镜像文件

sudo mkfs.ext4 -d \${TARGET_ROOTFS_DIR} \${ROOTFSIMAGE} # 在指定目录下创建ext4文件系统，并将其写入到镜像文件中

echo Rootfs Image: \${ROOTFSIMAGE} # 输出根文件系统镜像文件名

EOF

sudo chmod +x mk-image.sh

./mk-image.sh

