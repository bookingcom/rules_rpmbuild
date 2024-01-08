#!/usr/bin/env bash

set -exo pipefail

if [ -d /tmp/rpmbuild ]; then
    chmod -R +w /tmp/rpmbuild
    rm -rf /tmp/rpmbuild
fi

mkdir -p /tmp/rpmbuild/rpmbuild

{fakeroot} {tar} -xf {rpm_build_archive} -C /tmp/rpmbuild

if [ ! -z "{rpms}" ]; then
    cp --parents {rpms} /tmp/rpmbuild

    {fakecontainer} /tmp/rpmbuild rpm --rebuilddb

    {fakecontainer} /tmp/rpmbuild rpm --install --force {flags} {rpms}
fi

cp {spec} /tmp/rpmbuild/rpmbuild

{copy_sources}

ls /tmp/rpmbuild/rpmbuild/SOURCES

{fakecontainer} \
    /tmp/rpmbuild \
        /usr/bin/bash -c 'cd /rpmbuild && /usr/bin/rpmbuild --verbose -bb {spec_basename}'

mkdir -p {output}
exec cp $(find /tmp/rpmbuild/rpmbuild/RPMS -type f) {output}
