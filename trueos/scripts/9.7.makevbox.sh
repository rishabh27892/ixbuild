#!/bin/sh
#        Author: Kris Moore
#   Description: Creates a vbox disk image
#     Copyright: 2011 PC-BSD Software / iXsystems
############################################################################

# Check if we have sourced the variables yet
# Where is the build program installed
PROGDIR="`realpath | sed 's|/scripts||g'`" ; export PROGDIR

# Source our functions
. ${PROGDIR}/scripts/functions.sh

# Source the config file
. ${PROGDIR}/trueos.cfg

cd ${PROGDIR}/scripts


if [ -z ${PDESTDIR} ]
then
  echo "ERROR: PDESTDIR is still unset!"
  exit 1
fi

# VFS FILE
MFSFILE="${PROGDIR}/iso/TrueOS${TRUEOSVER}-${FARCH}.img"
ISODIR="${PDESTDIR9}-vm"


VPKGLIST="trueos-desktop archivers/unzip archivers/unrar trueos-meta-virtualboxguest trueos-meta-vwmareguest"

# Cleanup any failed build
umount ${ISODIR} 2>/dev/null
umount ${ISODIR}-tmp 2>/dev/null
rmdir ${ISODIR}-tmp 2>/dev/null
sleep 1

# Create the tmp dir we will be using
mk_tmpfs_wrkdir ${ISODIR}
mkdir ${ISODIR}-tmp


# Extract the ISO file
DVDFILE=`ls ${PROGDIR}/iso/TrueOS*DVD-USB.iso`
if [ ! -e "$DVDFILE" ] ; then
  echo "No such ISO file: $DVDFILE"
  exit 1
fi

# We now run virtualbox headless
# This is because grub-bhyve can't boot FreeBSD on root/zfs
# Once bhyve matures we can switch this back over
kldunload vmm 2>/dev/null >/dev/null
# Remove bridge0/tap0 so vbox bridge mode works
ifconfig bridge0 destroy >/dev/null 2>/dev/null
ifconfig tap0 destroy >/dev/null 2>/dev/null

# Get the default interface
iface=`netstat -f inet -nrW | grep '^default' | awk '{ print $6 }'`

# Load up VBOX
kldload vboxdrv >/dev/null 2>/dev/null
service vboxnet onestart >/dev/null 2>/dev/null

echo "Copying file-system contents to memory..."
MD=`mdconfig -a -t vnode -f ${DVDFILE}`
rc_halt "mount_cd9660 /dev/$MD ${ISODIR}-tmp"
tar cvf - -C ${ISODIR}-tmp . 2>/dev/null | tar xvf - -C ${ISODIR} 2>/dev/null
if [ $? -ne 0 ] ; then
  exit_err "tar cvf"
fi
rc_halt "umount /dev/$MD"
rc_halt "mdconfig -d -u $MD"
rc_halt "rmdir ${ISODIR}-tmp"

echo "Extracting /root and /etc"
rc_halt "tar xvf ${ISODIR}/uzip/root-dist.txz -C ${ISODIR}/root" >/dev/null 2>/dev/null
rc_halt "tar xvf ${ISODIR}/uzip/etc-dist.txz -C ${ISODIR}/etc" >/dev/null 2>/dev/null

# Copy the bhyve ttys / gettytab
rc_halt "cp ${PROGDIR}/scripts/pre-installs/ttys ${ISODIR}/etc/"
rc_halt "cp ${PROGDIR}/scripts/pre-installs/gettytab ${ISODIR}/etc/"

# Re-compression of /root and /etc
echo "Re-compressing /root and /etc"
rc_halt "tar cvJf ${ISODIR}/uzip/root-dist.txz -C ${ISODIR}/root ." >/dev/null 2>/dev/null
rc_halt "tar cvJf ${ISODIR}/uzip/etc-dist.txz -C ${ISODIR}/etc ." >/dev/null 2>/dev/null
rc_halt "rm -rf ${ISODIR}/root"
rc_halt "mkdir ${ISODIR}/root"

# Now loop through and generate VM disk images based upon supplied configs
for cfg in `ls ${PROGDIR}/scripts/pre-installs/*.cfg`
do
  pName="`basename $cfg | sed 's|.cfg||g'`"

  # Remove any crashed / old VM
  VBoxManage unregistervm $VM --delete >/dev/null 2>/dev/null
  rm -rf "/root/VirtualBox VMs/vminstall" >/dev/null 2>/dev/null

  # Create the filesystem backend file
  echo "Creating $MFSFILE"
  rm ${MFSFILE}.vdi >/dev/null 2>/dev/null

  rc_halt "VBoxManage createhd --filename ${MFSFILE}.vdi --size 50000"

  VM="vminstall"

  # Remove from the vbox registry
  VBoxManage closemedium dvd ${PROGDIR}/ISO/VMAUTO.iso >/dev/null 2>/dev/null
  # Copy the pc-sysinstall config
  rc_halt "cp $cfg ${ISODIR}/pc-sysinstall.cfg"
   
  # Setup the auto-install stuff
  echo "pc_config: /pc-sysinstall.cfg
shutdown_cmd: shutdown -p now
confirm_install: NO" > ${ISODIR}/pc-autoinstall.conf

  # Use makefs to create the image
  echo "Creating ISO..."
  sed -i '' 's|/kernel/kernel|/kernel/kernel -D -h|g' ${ISODIR}/boot/grub/grub.cfg
  echo "kern.geom.label.disk_ident.enable=0" >> ${ISODIR}/boot/loader.conf
  echo "kern.geom.label.gptid.enable=0" >> ${ISODIR}/boot/loader.conf
  echo "kern.geom.label.ufsid.enable=0" >> ${ISODIR}/boot/loader.conf
  grub-mkrescue -o ${PROGDIR}/iso/VMAUTO.iso ${ISODIR} -- -volid "TRUEOS_INSTALL"
  if [ $? -ne 0 ] ; then
   exit_err "Failed running grub-mkrescue"
  fi

  # Create the VM in virtualbox
  rc_halt "VBoxManage createvm --name $VM --ostype FreeBSD_64 --register"
  rc_halt "VBoxManage storagectl $VM --name SATA --add sata --controller IntelAhci"
  rc_halt "VBoxManage storageattach $VM --storagectl SATA --port 0 --device 0 --type hdd --medium ${MFSFILE}.vdi"
  rc_halt "VBoxManage storageattach $VM --storagectl SATA --port 1 --device 0 --type dvddrive --medium ${PROGDIR}/iso/VMAUTO.iso"
  rc_halt "VBoxManage modifyvm $VM --cpus 2 --ioapic on --boot1 disk --memory 2048 --vram 12"
  rc_halt "VBoxManage modifyvm $VM --nic1 bridged"
  rc_halt "VBoxManage modifyvm $VM --bridgeadapter1 ${iface}"
  rc_halt "VBoxManage modifyvm $VM --macaddress1 auto"
  rc_halt "VBoxManage modifyvm $VM --nictype1 82540EM"
  rc_halt "VBoxManage modifyvm $VM --pae off"
  rc_halt "VBoxManage modifyvm $VM --usb on"

  # Setup serial output
  rc_halt "VBoxManage modifyvm $VM --uart1 0x3F8 4"
  rc_halt "VBoxManage modifyvm $VM --uartmode1 file /tmp/vboxpipe"


  # Run VM now
  sync
  sleep 3

  # Just in case the install hung, we don't need to be waiting for over an hour
  echo "Running VM for installation to $MFSFILE.vdi..."
  count=0
  daemon -f -p /tmp/vminstall.pid vboxheadless -startvm "$VM" --vrde off
  while :
  do
    if [ ! -e "/tmp/vminstall.pid" ] ; then break; fi

    pgrep -qF /tmp/vminstall.pid
    if [ $? -ne 0 ] ; then
          break;
    fi

    count=`expr $count + 1`
    if [ $count -gt 360 ] ; then break; fi
    echo -e ".\c"

    sleep 10
  done

  echo "Output from VM install:"
  echo "------------------------------------"
  cat /tmp/vboxpipe

  # Make sure VM is shutdown
  VBoxManage controlvm ${VM} poweroff >/dev/null 2>/dev/null

  # Remove from the vbox registry
  VBoxManage closemedium dvd ${PROGDIR}/iso/VMAUTO.iso >/dev/null 2>/dev/null

  # Check that this device seemed to install properly
  dSize=`du -m ${MFSFILE}.vdi | awk '{print $1}'`
  if [ $dSize -lt 10 ] ; then
     # if the disk image is too small, something didn't work, bail out!
     echo "VM install failed!"

     # Cleanup tempfs
     umount ${ISODIR} 2>/dev/null
     rmdir ${ISODIR}
     exit 1
  fi

  OVAFILE="${PROGDIR}/iso/TrueOS${ISOVER}-${FARCH}-${pName}.ova"
  VDIFILE="${PROGDIR}/iso/TrueOS${ISOVER}-${FARCH}-${pName}.vdi"
  VMDKFILE="${PROGDIR}/iso/TrueOS${ISOVER}-${FARCH}-${pName}.vmdk"
  RAWFILE="${PROGDIR}/iso/TrueOS${ISOVER}-${FARCH}-${pName}.raw"

  # Create the VDI
  rm ${VDIFILE} 2>/dev/null
  rm ${VDIFILE}.xz 2>/dev/null
  rc_halt "VBoxManage clonehd ${MFSFILE}.vdi ${VDIFILE}"

  # Create the OVA file now
  rm ${OVAFILE} 2>/dev/null
  rm ${OVAFILE}.xz 2>/dev/null
  VM="$pName"

  # Remove any crashed / old VM
  VBoxManage unregistervm $VM --delete >/dev/null 2>/dev/null

  rc_halt "VBoxManage createvm --name $VM --ostype FreeBSD_64 --register"
  rc_halt "VBoxManage storagectl $VM --name IDE --add ide --controller PIIX4"
  rc_halt "VBoxManage storageattach $VM --storagectl IDE --port 0 --device 0 --type hdd --medium ${VDIFILE}"
  rc_halt "VBoxManage modifyvm $VM --ioapic on --boot1 disk --memory 1024 --vram 12"
  rc_halt "VBoxManage modifyvm $VM --nic1 nat"
  rc_halt "VBoxManage modifyvm $VM --macaddress1 auto"
  rc_halt "VBoxManage modifyvm $VM --nictype1 82540EM"
  rc_halt "VBoxManage modifyvm $VM --pae off"
  rc_halt "VBoxManage modifyvm $VM --usb on"
  rc_halt "VBoxManage modifyvm $VM --audio oss"
  rc_halt "VBoxManage modifyvm $VM --audiocontroller ac97"
  rc_halt "VBoxManage export $VM -o $OVAFILE"
  rc_halt "VBoxManage unregistervm $VM --delete"
  rc_halt "chmod 644 $OVAFILE"

  # Create the VDI
  rm ${VDIFILE} 2>/dev/null
  rm ${VDIFILE}.xz 2>/dev/null
  rc_halt "VBoxManage clonehd --format VDI ${MFSFILE}.vdi ${VDIFILE}"
  rc_halt "pixz ${VDIFILE}"
  rc_halt "chmod 644 ${VDIFILE}.xz"

  # Create the VMDK
  rm ${VMDKFILE} 2>/dev/null
  rm ${VMDKFILE}.xz 2>/dev/null
  rc_halt "VBoxManage clonehd --format VMDK ${MFSFILE}.vdi ${VMDKFILE}"
  rc_halt "pixz ${VMDKFILE}"
  rc_halt "chmod 644 ${VMDKFILE}.xz"

  # Do RAW now
  rm ${RAWFILE} 2>/dev/null
  rm ${RAWFILE}.xz 2>/dev/null
  rc_halt "VBoxManage clonehd --format RAW ${MFSFILE}.vdi ${RAWFILE}"
  rc_halt "pixz ${RAWFILE}"
  rc_halt "chmod 644 ${RAWFILE}.xz"

  # Run MD5 command
  cd ${PROGDIR}/iso
  md5 -q ${OVAFILE} >${OVAFILE}.md5
  sha256 -q ${OVAFILE} >${OVAFILE}.sha256
  md5 -q ${VDIFILE}.xz >${VDIFILE}.xz.md5
  sha256 -q ${VDIFILE}.xz >${VDIFILE}.xz.sha256
  md5 -q ${VMDKFILE}.xz >${VMDKFILE}.xz.md5
  sha256 -q ${VMDKFILE}.xz >${VMDKFILE}.xz.sha256
  md5 -q ${RAWFILE}.xz >${RAWFILE}.xz.md5
  sha256 -q ${RAWFILE}.xz >${RAWFILE}.xz.sha256

  # Cleanup
  rm ${PROGDIR}/iso/VMAUTO.iso
done

# Cleanup tempfs
umount ${ISODIR} 2>/dev/null
rmdir ${ISODIR}
exit 0
