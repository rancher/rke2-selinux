#!/bin/sh -e

DIRNAME=`dirname $0`
cd $DIRNAME

echo "Building and Loading Policy"
set -x
make -f /usr/share/selinux/devel/Makefile rke2.pp || exit
/usr/sbin/semodule -i rke2.pp

/sbin/restorecon -F -R -v /usr/local/bin
/sbin/restorecon -F -R -v /var/run
/sbin/restorecon -F -R -v /var/lib

pwd=$(pwd)
rpmbuild --define "_sourcedir ${pwd}" --define "_specdir ${pwd}" --define "_builddir ${pwd}" --define "_srcrpmdir ${pwd}" --define "_rpmdir ${pwd}" --define "_buildrootdir ${pwd}/.build"  -ba rke2-selinux.spec
