#!/usr/bin/env bash

# Where is the pcbsd-build program installed
PROGDIR="`realpath | sed 's|/scripts||g'`" ; export PROGDIR

# Source the config file
. ${PROGDIR}/freenas.cfg

cd ${PROGDIR}/scripts

# Source our functions
. ${PROGDIR}/scripts/functions.sh
. ${PROGDIR}/scripts/functions-tests.sh

# Look through the output log and try to determine the failure
parse_checkout_error()
{
  ### TODO - Add error detection of checkout failures
  echo '' > ${LOUT}
}

# Look through the output log and try to determine the failure
parse_build_error()
{
  echo '' > ${LOUT}
  export TESTSTDERR=${LOUT}

  # Look for some of the common error messages

  # port failed to compile
  grep -q "ERROR: Packages installation failed" ${1}
  if [ $? -eq 0 ] ; then
    grep "====>> Failed" ${1} >> ${LOUT}
    grep "====>> Skipped" ${1} >> ${LOUT}
    grep "====>> Ignored" ${1} >> ${LOUT}
    return 0
  fi

  ### TODO - Add various error detection as they occur

  # Look for generic error
  grep -q "^ERROR: " ${1}
  if [ $? -eq 0 ] ; then
    # Use the search function to get some context
    ${PROGDIR}/../utils/search -s5 "ERROR: " ${1} >>${LOUT}
    return 0
  fi
}

# Set local location of FreeNAS build
if [ -n "$BUILDTAG" ] ; then
  FNASBDIR="/$BUILDTAG"
else
  FNASBDIR="/freenas"
fi
export FNASBDIR

# Kludge for now, this dir gets full and kills free space
if [ -d "/builds/FreeNAS" ] ; then
  rm -rf /builds/FreeNAS
fi

# Error output log
LOUT="/tmp/fnas-error-debug.txt"
touch ${LOUT}

if [ -z "$BUILDINCREMENTAL" ] ; then
  BUILDINCREMENTAL="false"
fi

get_bedir

# Rotate an old build
if [ -d "${FNASBDIR}" -a "${BUILDINCREMENTAL}" != "true" ] ; then
  echo "Doing fresh build!"
  cd ${FNASBDIR}
  chflags -R 0 ${BEDIR}
  rm -rf ${BEDIR}
fi

if [ "$BUILDINCREMENTAL" = "true" ] ; then
  echo "Doing incremental build!"
  cd ${FNASBDIR}
  rc_halt "git reset --hard"

  # Nuke old ISO's / builds
  echo "Removing old build ISOs"
  rm -rf ${BEDIR}/release 2>/dev/null
fi

# Figure out the flavor for this test
echo $BUILDTAG | grep -q "truenas"
if [ $? -eq 0 ] ; then
  FLAVOR="TRUENAS"
else
  FLAVOR="FREENAS"
fi

# Add JENKINSBUILDSENV to one specified by the build itself
if [ -n "$JENKINSBUILDSENV" ] ; then
  BUILDSENV="$BUILDSENV $JENKINSBUILDSENV"
fi

# Throw env command on the front
if [ -n "$BUILDSENV" ] ; then
  BUILDSENV="env $BUILDSENV"
fi

if [ -d "${FNASBDIR}" ] ; then
  rc_halt "cd ${FNASBDIR}"
  OBRANCH=$(git branch | grep '^*' | awk '{print $2}')
  if [ "${OBRANCH}" != "${GITFNASBRANCH}" ] ; then
     # Branch mismatch, re-clone
     echo "New freenas-build branch detected (${OBRANCH} != ${GITFNASBRANCH}) ... Re-cloning..."
     cd ${PROGDIR}
     rm -rf ${FNASBDIR}
     chflags -R noschg ${FNASBDIR}
     rm -rf ${FNASBDIR}
  fi
fi

# Make sure we have our freenas sources
if [ -d "${FNASBDIR}" ]; then
  rc_halt "ln -fs ${FNASBDIR} ${FNASSRC}"
  git_fnas_up "${FNASSRC}" "${FNASSRC}"
else
  rc_halt "git clone --depth=1 -b ${GITFNASBRANCH} ${GITFNASURL} ${FNASBDIR}"
  rc_halt "ln -fs ${FNASBDIR} ${FNASSRC}"
  git_fnas_up "${FNASSRC}" "${FNASSRC}"
fi

# Lets keep our distfiles around and use previous ones
if [ ! -d "/usr/ports/distfiles" ] ; then
  mkdir -p /usr/ports/distfiles
fi
if [ -e "${FNASSRC}/build/config/env.pyd" ] ; then
  # FreeNAS 9.10 / 10
  sed -i '' 's|${OBJDIR}/ports/distfiles|/usr/ports/distfiles|g' ${FNASSRC}/build/config/env.pyd
else
  # FreeNAS / TrueNAS 9
  export PORTS_DISTFILES_CACHE="/usr/ports/distfiles"
fi

# Now create the world / kernel / distribution
cd ${FNASSRC}

# Check if we have optional build options
if [ -n "$BUILDOPTS" ] ; then
  BUILDOPTS=`echo $BUILDOPTS | sed "s|%BUILDID%|${BUILD_ID}|g"`
  PROFILEARGS="$PROFILEARGS $BUILDOPTS"

  # Unset so we don't conflict with anything
  export OLDBUILDOPTS="$BUILDOPTS"
  unset BUILDOPTS
fi

echo $PROFILEARGS | grep -q "PRODUCTION=yes"
if [ $? -eq 0 ] ; then
  # PRODUCTION is enabled, make sure VERSION was specified
  if [ -z "$JENKINSVERSION" ] ; then
    echo "PRODUCTION=yes is SET, but no JENKINSVERSION= is set!"
    exit 1
  fi
  PROFILEARGS="${PROFILEARGS} VERSION=$JENKINSVERSION"

  # Cleanup before the build if doing PRODUCTION and INCREMENTAL is set
  if [ "$BUILDINCREMENTAL" != "true" ] ; then
    echo "Running cleandist"
    make cleandist
  fi
fi

# Are we building docs / API?
if [ "$1" = "docs" -o "$1" = "api-docs" ] ; then
  echo "Creating $1"
  cd ${FNASBDIR}
  rc_halt "make checkout $PROFILEARGS"
  rc_halt "make clean-docs $PROFILEARGS"
  rc_halt "make $1 $PROFILEARGS"
  exit 0
fi


# Start the XML reporting
clean_xml_results "Clean previous results"
start_xml_results "FreeNAS Build Process"
set_test_group_text "Build phase tests" "2"

OUTFILE="/tmp/fnas-build.out.$$"

# Display output to stdout
touch ${OUTFILE}
(tail -f ${OUTFILE} 2>/dev/null) &
TPID=$!

echo_test_title "${BUILDSENV} make checkout ${PROFILEARGS}" 2>/dev/null >/dev/null
echo "${BUILDSENV} make checkout ${PROFILEARGS}"
${BUILDSENV} make checkout ${PROFILEARGS} >${OUTFILE} 2>${OUTFILE}
if [ $? -ne 0 ] ; then
  kill -9 $TPID 2>/dev/null
  echo_fail "Failed running make checkout"
  finish_xml_results "make"
  exit 1
fi
kill -9 $TPID 2>/dev/null
echo_ok

# Ugly hack to get freenas 9.x to build on CURRENT
if [ "$FREENASLEGACY" = "YES" ] ; then

   # Add all the fixes to use a 9.10 version of mtree
   sed -i '' "s|mtree -deU|${PROGDIR}/scripts/kludges/mtree -deU|g" ${FNASSRC}/FreeBSD/src/Makefile.inc1
   sed -i '' "s|mtree -deU|${PROGDIR}/scripts/kludges/mtree -deU|g" ${FNASSRC}/FreeBSD/src/release/Makefile.sysinstall
   sed -i '' "s|mtree -deU|${PROGDIR}/scripts/kludges/mtree -deU|g" ${FNASSRC}/FreeBSD/src/release/picobsd/build/picobsd
   sed -i '' "s|mtree -deU|${PROGDIR}/scripts/kludges/mtree -deU|g" ${FNASSRC}/FreeBSD/src/tools/tools/tinybsd/tinybsd
   sed -i '' "s|mtree -deU|${PROGDIR}/scripts/kludges/mtree -deU|g" ${FNASSRC}/FreeBSD/src/share/examples/Makefile
   sed -i '' "s|mtree -deU|${PROGDIR}/scripts/kludges/mtree -deU|g" ${FNASSRC}/FreeBSD/src/include/Makefile
   sed -i '' "s|mtree -deU|${PROGDIR}/scripts/kludges/mtree -deU|g" ${FNASSRC}/FreeBSD/src/usr.sbin/sysinstall/install.c
   MTREE_CMD="${PROGDIR}/scripts/kludges/mtree"
   export MTREE_CMD

   if [ ! -e "/usr/bin/makeinfo" ] ; then
      cp ${PROGDIR}/scripts/kludges/makeinfo /usr/bin/makeinfo
      chmod 755 /usr/bin/makeinfo
   fi
   if [ ! -e "/usr/bin/mklocale" ] ; then
      cp ${PROGDIR}/scripts/kludges/mklocale /usr/bin/mklocale
      chmod 755 /usr/bin/mklocale
   fi
   if [ ! -e "/usr/bin/install-info" ] ; then
      cp ${PROGDIR}/scripts/kludges/install-info /usr/bin/install-info
      chmod 755 /usr/bin/install-info
   fi

   # Copy our kludged build_jail.sh
   cp ${PROGDIR}/scripts/kludges/build_jail.sh ${FNASSRC}/build/build_jail.sh

   # NANO_WORLDDIR expects this to exist
   if [ ! -d "/var/home" ] ; then
      mkdir /var/home
   fi

   # Fix a missing directory in NANO_WORLDDIR
   sed -i '' 's|geom_gate.ko|geom_gate.ko;mkdir -p ${NANO_WORLDDIR}/usr/src/sys|g' ${FNASSRC}/build/nanobsd-cfg/os-base-functions.sh

   # Check if grub2-efi is on the builder, remove it so
   pkg info -q grub2-efi
   if [ $? -eq 0 ] ; then
     pkg delete -y grub2-efi
   fi
fi

# Set to use TMPFS for everything
if [ -e "build/config/templates/poudriere.conf" ] ; then
  echo "Enabling USE_TMPFS=all"

  sed -i '' 's|USE_TMPFS=yes|USE_TMPFS=all|g' build/config/templates/poudriere.conf
  # Set the jail name to use for these builds
  export POUDRIERE_JAILNAME="`echo ${BUILDTAG} | sed 's|\.||g'`"

fi

# Some tuning for our big build boxes
CPUS=$(sysctl -n kern.smp.cpus)
if [ $CPUS -gt 10 ] ; then
  echo "Setting POUDRIERE_JOBS=10"
  export POUDRIERE_JOBS="10"
fi

# Display output to stdout
touch $OUTFILE
(sleep 5 ; tail -f $OUTFILE 2>/dev/null) &
TPID=$!

echo_test_title "${BUILDSENV} make release ${PROFILEARGS}" 2>/dev/null >/dev/null
echo "${BUILDSENV} make release ${PROFILEARGS}"
${BUILDSENV} make release ${PROFILEARGS} >${OUTFILE} 2>${OUTFILE}
if [ $? -ne 0 ] ; then
  kill -9 $TPID 2>/dev/null
  echo_fail "Failed running make release"
  parse_build_error "${OUTFILE}"
  clean_artifacts
  save_artifacts_on_fail
  finish_xml_results "make"
  exit 1
fi
kill -9 $TPID 2>/dev/null
echo_ok
clean_artifacts
save_artifacts_on_success
finish_xml_results "make"

rm ${OUTFILE}
exit 0
