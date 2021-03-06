#!/bin/false

rm -f ./.config
make defconfig
mv ./.config ./.config.def
make allmodconfig
cp ./.config ./.config.mod
cat ./.config.mod | egrep '=m$' >./.config.mod.only
cat >./.config.ena <<'EOF'
CONFIG_AUDIT=n
CONFIG_NETFILTER_ADVANCED=y
EOF
cat ./.config.def ./.config.ena ./.config.mod.only >./.config
make olddefconfig
cat >>./.config <<'EOF'
CONFIG_KERNEL_XZ=y

CONFIG_IKCONFIG_PROC=y

CONFIG_RD_GZIP=n
CONFIG_RD_BZIP2=n
CONFIG_RD_LZMA=n
CONFIG_RD_XZ=n
CONFIG_RD_LZO=n
CONFIG_RD_LZ4=n

CONFIG_CC_OPTIMIZE_FOR_SIZE=y
CONFIG_CC_STACKPROTECTOR_STRONG=y

CONFIG_MODULE_FORCE_UNLOAD=n

CONFIG_SERIAL_8250=y
CONFIG_SERIAL_8250_DEPRECATED_OPTIONS=n
CONFIG_SERIAL_8250_CONSOLE=y
CONFIG_SERIAL_8250_EXTENDED=n

CONFIG_BINFMT_SCRIPT=y

CONFIG_SQUASHFS_FILE_DIRECT=y
CONFIG_SQUASHFS_4K_DEVBLK_SIZE=y
CONFIG_SQUASHFS_ZLIB=y
CONFIG_SQUASHFS_LZ4=y
CONFIG_SQUASHFS_LZO=y
CONFIG_SQUASHFS_XZ=y

CONFIG_PANIC_ON_OOPS=y

CONFIG_MAGIC_SYSRQ_DEFAULT_ENABLE=0
CONFIG_SND_DYNAMIC_MINORS=y
CONFIG_DEBUG_STACK_USAGE=n

CONFIG_LOGO=n
CONFIG_DEBUG_KERNEL=n
EOF

cat <<'EOF'
CONFIG_PROVIDE_OHCI1394_DMA_INIT=n
CONFIG_X86_VERBOSE_BOOTUP=n
CONFIG_EARLY_PRINTK_DBGP=n
CONFIG_FTRACE=n

CONFIG_USELIB=n
CONFIG_PROFILING=n
CONFIG_SLUB_CPU_PARTIAL=n
CONFIG_KPROBES=n
CONFIG_JUMP_LABEL=n

CONFIG_BSD_PROCESS_ACCT=n
CONFIG_TASK_XACCT=n

CONFIG_OSF_PARTITION=n
CONFIG_AMIGA_PARTITION=n
CONFIG_MAC_PARTITION=n
CONFIG_BSD_DISKLABEL=n
CONFIG_MINIX_SUBPARTITION=n
CONFIG_SOLARIS_X86_PARTITION=n
CONFIG_UNIXWARE_DISKLABEL=n
CONFIG_SGI_PARTITION=n
CONFIG_SUN_PARTITION=n
CONFIG_KARMA_PARTITION=n

CONFIG_X86_EXTENDED_PLATFORM=n
CONFIG_CALGARY_IOMMU=n
CONFIG_MICROCODE=n
CONFIG_BALLOON_COMPACTION=n
CONFIG_COMPACTION=n
CONFIG_EFI=n
CONFIG_CRASH_DUMP=n
CONFIG_RELOCATABLE=n

CONFIG_SUSPEND=n
CONFIG_HIBERNATION=n
CONFIG_PM=n

#CONFIG_CPU_FREQ=n

CONFIG_INTEL_IOMMU=n

CONFIG_STACKTRACE=n

CONFIG_SECURITY=n

CONFIG_CRYPTO_CBC=m
CONFIG_CRYPTO_HMAC=m
CONFIG_CRYPTO_SHA1=m
CONFIG_CRYPTO_SHA256=m

CONFIG_XZ_DEC=m
EOF
make olddefconfig
