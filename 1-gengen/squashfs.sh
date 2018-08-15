#!/bin/false

. /builds/elvopt

# purge some history files that sometimes turn up
rm -f /root/.bash_history /root/.wget-hsts

mkdir /tmp/root
mount --bind / /tmp/root
echo "tmp" >>/tmp/ef
echo "var/tmp" >>/tmp/ef
if [ "$FLAG_SOURCES" != "y" ]
then
  echo "sources" >>/tmp/ef
fi
echo "builds" >>/tmp/ef
echo "tmp d 1777 0 0" >>/tmp/pf
echo "var/tmp d 1777 0 0" >>/tmp/pf
pushd /tmp/root
mkdir -p /builds
rm -f /builds/gentoo.sqs
mksquashfs . /builds/gentoo.sqs -no-exports -no-xattrs -always-use-fragments -ef /tmp/ef -pf /tmp/pf -no-recovery
popd
umount /tmp/root

# make gentoo.sqs a multiple of the nbd-hyperbolic sector size
# (128KiB). incidentally, this is also the default squashfs block size
# (but the image is not padded to this size by mksquashfs).

SIZE="$(stat -c %s /builds/gentoo.sqs)"
BLKZ="$(( (128*1024) ))"
SIZE="$(( (((SIZE+(BLKZ-1))/BLKZ)*BLKZ) ))"
truncate -s "$SIZE" /builds/gentoo.sqs
