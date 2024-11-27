#!/bin/bash -e

TARGET_ROOTFS_DIR=./ubuntu_rootfs # 定义目标根文件系统目录路径
ROOTFSIMAGE=ubuntu-rootfs.img # 定义根文件系统镜像文件名
EXTRA_SIZE_MB=300 # 定义额外的磁盘空间大小
IMAGE_SIZE_MB=$(( $(sudo du -sh -m ${TARGET_ROOTFS_DIR} | cut -f1) + ${EXTRA_SIZE_MB} )) # 计算根文件系统镜像文件大小

echo Making rootfs! # 输出提示信息

if [ -e ${ROOTFSIMAGE} ]; then # 如果根文件系统镜像文件已经存在，则删除
rm ${ROOTFSIMAGE}
fi

dd if=/dev/zero of=${ROOTFSIMAGE} bs=1M count=0 seek=${IMAGE_SIZE_MB} # 创建指定大小的空白镜像文件

sudo mkfs.ext4 -d ${TARGET_ROOTFS_DIR} ${ROOTFSIMAGE} # 在指定目录下创建ext4文件系统，并将其写入到镜像文件中

echo Rootfs Image: ${ROOTFSIMAGE} # 输出根文件系统镜像文件名

