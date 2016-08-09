#!/bin/sh

# Change directory
mypath=`realpath $0`
cd `dirname $mypath`

if [ -z "$JENKINS_DO_UPDATE" ] ; then
  # Before we begin any build, make sure we are updated from git
  git pull
  export JENKINS_DO_UPDATE="YES"
  ./jenkins.sh "$1" "$2" "$3"
  exit $?
fi

# Set the variables
TYPE="${1}"
BUILD="${2}"
BRANCH="${3}"

# Set JENKINS var
export USING_JENKINS="YES"

display_usage() {

	 cat << EOF
Available Commands:

-- FreeNAS Commands --
      freenas - Builds FreeNAS release
freenas-tests - Runs FreeNAS VM API tests against built release
freenas-combo - Build release and run VM API tests against it automatically
freenas-ltest - Runs the FreeNAS "live" tests against a target system
freenas-lupgrade - Runs the FreeNAS "live" upgrade against a target system
freenas-docs      - Create FreeNAS Handbook
freenas-api       - Create FreeNAS API
freenas-push-docs - Push FreeNAS Docs
freenas-push-api  - Push FreeNAS API
freenas-push-nightly - Run 'release-push' for FreeNAS Nightly

-- TrueOS Commands --
trueos-world    - Builds the world
trueos-pkg      - Builds the entire pkg repo
trueos-iso-pkg  - Builds just the pkgs needed for ISO creation
trueos-iso      - Builds the ISO files
trueos-vm       - Builds the VM images
publish-iso     - Upload ISO files to ScaleEngine
publish-pkg     - Upload PKG files to ScaleEngine
trueos-docs     - Create TrueOS handbook
push-trueos-docs- Upload TrueOS handbook
lumina-docs	- Create lumina handbook
push-lumina-docs- Upload lumina handbook

-- PC-BSD Commands --
  world - Build FreeBSD world
   jail - Prep the jail for package build
    pkg - Build packages
iso-pkg - Build packages for ISO only
    iso - Assemble PC-BSD ISO files
     vm - Assemble PC-BSD VM images
EOF

}

if [ -z "$1" ] ; then
  display_usage
  exit 1
fi
 
# Source our functions
. build.conf
. functions.sh
######################################################

case $TYPE in
    world|trueos-world) jenkins_world ;;
        pkg|trueos-pkg) jenkins_pkg "release" ;;
iso-pkg|trueos-iso-pkg) jenkins_pkg "iso" ;;
           trueos-docs) jenkins_trueos_docs ;;
      push-trueos-docs) jenkins_trueos_push_docs ;;
           lumina-docs) jenkins_trueos_lumina_docs ;;
      push-lumina-docs) jenkins_trueos_push_lumina_docs ;;
        iso|trueos-iso) jenkins_iso ;;
           publish-iso) jenkins_publish_iso ;;
           publish-pkg) jenkins_publish_pkg ;;
          vm|trueos-vm) jenkins_vm ;;
                  jail) jenkins_jail ;;
               freenas) jenkins_freenas ;;
         freenas-tests) jenkins_freenas_tests ;;
         freenas-ltest) jenkins_freenas_live_tests ;;
      freenas-lupgrade) jenkins_freenas_live_upgrade ;;
          freenas-docs) jenkins_freenas_docs ;;
     freenas-push-docs) jenkins_freenas_push_docs ;;
           freenas-api) jenkins_freenas_api ;;
      freenas-push-api) jenkins_freenas_push_api ;;
  freenas-push-nightly) jenkins_freenas_push_nightly ;;
         freenas-combo) jenkins_freenas
   		        jenkins_freenas_tests ;;
           ports-tests) jenkins_ports_tests ;;
                     *) echo "Invalid command: $1" 
         		display_usage
         exit 1
         ;;
esac
