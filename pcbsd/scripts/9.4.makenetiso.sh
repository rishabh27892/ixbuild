#!/bin/sh
#        Author: Kris Moore
#   Description: Creates the network install ISO file
#     Copyright: 2015 PC-BSD Software / iXsystems
############################################################################

# Where is the pcbsd-build program installed
PROGDIR="`realpath | sed 's|/scripts||g'`" ; export PROGDIR

# Source the config file
. ${PROGDIR}/pcbsd.cfg

cd ${PROGDIR}/scripts

# Source our functions
. ${PROGDIR}/scripts/functions.sh

echo "Building DVD images.."

ISODISTDIR="${PDESTDIR9}/dist"

# Remove archive files
if [ -d "${ISODISTDIR}" ] ; then
  echo "Removing ${ISODISTDIR}"
  rm -rf ${ISODISTDIR}
fi
mkdir ${ISODISTDIR}

# Set the file-date
fDate="-`date '+%m-%d-%Y'`"

# Base file name
if [ "$SYSBUILD" = "trueos" ] ; then
  bFile="TRUEOS${ISOVER}${fDate}-${FARCH}"
  bTitle="TrueOS"
  brand="trueos"
else
  bFile="PCBSD${ISOVER}${fDate}-${FARCH}"
  bTitle="PC-BSD"
  brand="pcbsd"
fi
export bFile

# Set the pcbsd-media-details file marker on this media
echo "TrueOS ${PCBSDVER} "$ARCH" INSTALL DVD/USB - `date`" > ${PDESTDIR9}/pcbsd-media-details
touch ${PDESTDIR9}/pcbsd-media-network

# Stolen from FreeBSD's build scripts
# This is highly x86-centric and will be used directly below.
bootable="-o bootimage=i386;$4/boot/cdboot -o no-emul-boot"

# Make EFI system partition (should be done with makefs in the future)
rc_halt "dd if=/dev/zero of=efiboot.img bs=4k count=500"
device=`mdconfig -a -t vnode -f efiboot.img`
rc_halt "newfs_msdos -F 12 -m 0xf8 /dev/$device"
rc_nohalt "mkdir efi"
rc_halt "mount -t msdosfs /dev/$device efi"
rc_halt "mkdir -p efi/efi/boot"
rc_halt "cp ${PDESTDIR9}/boot/loader.efi efi/efi/boot/bootx64.efi"
rc_halt "umount efi"
rc_halt "rmdir efi"
rc_halt "mdconfig -d -u $device"
bootable="-o bootimage=i386;efiboot.img -o no-emul-boot $bootable"

LABEL="PCBSD_INSTALL"
publisher="The PC-BSD Project.  http://www.pcbsd.org/"
echo "Running makefs..."
echo "/dev/iso9660/$LABEL / cd9660 ro 0 0" > ${PDESTDIR9}/etc/fstab
# Set some initial loader.conf values
cat >>${PDESTDIR9}/boot/loader.conf << EOF
vfs.root.mountfrom="cd9660:/dev/iso9660/$LABEL"
loader_menu_title="Welcome to $bTitle"
loader_brand="$brand"
EOF
makefs -t cd9660 $bootable -o rockridge -o label=$LABEL -o publisher="$publisher" ${PROGDIR}/iso/${bFile}-netinstall.iso ${PDESTDIR9}
rm ${PDESTDIR9}/etc/fstab
rm -f efiboot.img

# Run MD5 command
cd ${PROGDIR}/iso
md5 -q ${bFile}-netinstall.iso >${bFile}-netinstall.iso.md5
sha256 -q ${bFile}-netinstall.iso >${bFile}-netinstall.iso.sha256
if [ ! -e "latest.iso" ] ; then
  ln -s ${bFile}-netinstall.iso latest.iso
  ln -s ${bFile}-netinstall.iso.md5 latest.iso.md5
  ln -s ${bFile}-netinstall.iso.sha256 latest.iso.sha256
fi

exit 0
