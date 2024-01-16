#!/usr/bin/env bash

set -exuo pipefail

if [ -d /tmp/rpm ]; then
    chmod -R +w /tmp/rpm
    rm -rf /tmp/rpm
fi

# Jan 1, 2001 00:00:00 UTC as epoch
export SOURCE_DATE_EPOCH="978307200"

CWD=$(pwd)

export OUTPUT=${CWD}/${OUTPUT}
export FAKEROOT=${CWD}/${FAKEROOT}
export FAKECONTAINER=${CWD}/${FAKECONTAINER}
export BSDTAR_BIN=${CWD}/${BSDTAR_BIN}
export RPM_ARCHIVE=${CWD}/${RPM_ARCHIVE}

mkdir -p /tmp/rpm/rpmbuild/rpmbuild

${FAKEROOT} mkdir -p /tmp/rpm/bin /tmp/rpm/lib64 /tmp/rpm/sbin /tmp/rpm/rpmbuild/usr/lib/rpm /tmp/rpm/usr/lib/rpm

# base system + rpmbuild
${FAKEROOT} ${BSDTAR_BIN} -xkmf ${FILESYSTEM_RPMTREE} -C /tmp/rpm
${FAKEROOT} ${BSDTAR_BIN} -xkmf ${RPMBUILD_RPMTREE} -C /tmp/rpm

# portable rpm
${FAKEROOT} ${BSDTAR_BIN} -xkmf ${RPM_ARCHIVE} -C /tmp/rpm

# build dependencies
${FAKEROOT} ${BSDTAR_BIN} -xkmf ${DEPS_RPMTREE} -C /tmp/rpm

# fix some paths
for i in bin lib64 sbin ; do
    ${FAKEROOT} bash -c "cd /tmp/rpm && mv ${i}/* usr/${i} && rmdir ${i} && ln -s usr/${i} ."
done

if grep -q -F "__perl_provides" /tmp/rpm/etc/rpm/macros.perl ; then
    ${FAKEROOT} sed -i '/__perl_provides/d' /tmp/rpm/etc/rpm/macros.perl
    ${FAKEROOT} sed -i '/__perl_requires/d' /tmp/rpm/etc/rpm/macros.perl
fi

${FAKEROOT} \
    /tmp/rpm/${RPM_INTERPRETER} \
        /tmp/rpm/${RPM_PREFIX}/usr/bin/rpmdb \
        --initdb \
        --root=/tmp/rpm \
        --dbpath=/var/lib/rpm \
        --verbose

${FAKEROOT} mkdir -p /tmp/rpm/var/lib/rpm

${FAKEROOT} \
    /tmp/rpm/${RPM_INTERPRETER} /tmp/rpm/${RPM_BIN} \
        --install \
        --rcfile=/tmp/rpm/${RPM_RC} \
        --root=/tmp/rpm \
        --dbpath=/var/lib/rpm \
        --justdb \
        --verbose \
        ${FLAGS} \
        ${CWD}/${FILESYSTEM_RPMS}/*.rpm \
        ${CWD}/${RPMBUILD_RPMS}/*.rpm \
        ${CWD}/${DEPS_RPMS}/*.rpm

cp ${SPEC} /tmp/rpm/rpmbuild

${FAKEROOT} ${CWD}/${COPY_FILES}

if [ ! -f /tmp/rpm/usr/bin/ld ] && [ -f /tmp/rpm/usr/bin/ld.gold ]; then
    (cd /tmp/rpm/usr/bin ; ${FAKEROOT} ln -s ld.gold ld)
fi

${FAKECONTAINER} /tmp/rpm \
    ${RPM_INTERPRETER} ${RPMBUILD_BIN} \
        --verbose --verbose -bb \
        --dbpath=/var/lib/rpm \
        --define='source_date_epoch_from_changelog 1' \
        --define='use_source_date_epoch_as_buildtime 1' \
        --define='clamp_mtime_to_source_date_epoch 1' \
        --define='debug_package %{nil}' \
        --define='_build_id_links none' \
        /rpmbuild/${SPEC_BASENAME}

mkdir -p {output}
exec cp $(find /tmp/rpm/rpmbuild/RPMS -type f) ${OUTPUT}
