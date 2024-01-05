#!/usr/bin/env bash

set -exo pipefail

prepare_root () {
    mkdir -p $1 $1/usr/bin $1/usr/lib64 $1/var/spool/mail $1/tmp

    ( cd $1 && ln -s ./usr/bin bin && ln -s ./usr/lib64 lib64 )
    ( cd $1/var && ln -s spool/mail mail )
    ( cd $1/usr && ln -s ../tmp tmp )
    mkdir -p $1/dev $1/proc $1/sys
    chmod 777 $1/dev $1/proc $1/sys
}

if [ -d /tmp/rpm ]; then
    chmod -R +w /tmp/rpm
    rm -rf /tmp/rpm
fi

mkdir -p /tmp/rpm /tmp/rpm/bin /tmp/rpm/lib64 /tmp/rpm/sbin

{fakeroot} {tar} -xkmf {rpmtree} -C /tmp/rpm

mkdir -p /tmp/rpm/external

cp --parents {filesystem} {rpms} /tmp/rpm

prepare_root /tmp/rpm/chroot

{fakecontainer} \
    /tmp/rpm \
        rpm \
            --root /chroot \
            --dbpath /var/lib/rpm \
            --install --justdb --force --verbose {filesystem}

{fakecontainer} \
    /tmp/rpm \
        /bin/rpm \
            --root /chroot \
            --dbpath /var/lib/rpm \
            --install --force --verbose {flags} {rpms}

{fakeroot} rm -rf /tmp/rpm/chroot/dev /tmp/rpm/chroot/proc /tmp/rpm/chroot/sys

exec {fakeroot} {tar} -czf {output} -C /tmp/rpm/chroot .
