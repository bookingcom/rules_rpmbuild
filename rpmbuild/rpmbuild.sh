#!/usr/bin/env bash

set -exuo pipefail

if [ -d ${RPMPATH} ]; then
    chmod -R +w ${RPMPATH}
    rm -rf ${RPMPATH}
fi

# Jan 1, 2001 00:00:00 UTC as epoch
export SOURCE_DATE_EPOCH="978307200"

CWD=$(pwd)

export OUTPUT=${CWD}/${OUTPUT}
export FAKEROOT=${CWD}/${FAKEROOT}
export FAKECONTAINER=${CWD}/${FAKECONTAINER}
export BSDTAR_BIN=${CWD}/${BSDTAR_BIN}
export RPM_ARCHIVE=${CWD}/${RPM_ARCHIVE}

mkdir -p ${RPMPATH}/rpmbuild/rpmbuild

${FAKEROOT} mkdir -p ${RPMPATH}/bin ${RPMPATH}/lib64 ${RPMPATH}/sbin ${RPMPATH}/rpmbuild/usr/lib/rpm ${RPMPATH}/usr/lib/rpm

# base system + rpmbuild
${FAKEROOT} ${BSDTAR_BIN} -xkmf ${FILESYSTEM_RPMTREE} -C ${RPMPATH}
${FAKEROOT} ${BSDTAR_BIN} -xkmf ${RPMBUILD_RPMTREE} -C ${RPMPATH}

# portable rpm
${FAKEROOT} ${BSDTAR_BIN} -xkmf ${RPM_ARCHIVE} -C ${RPMPATH}

# build dependencies
if [ -n "${DEPS_RPMS:-}" ]; then
    ${FAKEROOT} ${BSDTAR_BIN} -xkmf ${DEPS_RPMTREE} -C ${RPMPATH}
fi

# fix some paths
for i in bin lib64 sbin ; do
    find ${RPMPATH}/${i}/ -mindepth 1 -maxdepth 1 -exec ${FAKEROOT} mv {} ${RPMPATH}/usr/${i} \;
    ${FAKEROOT} rmdir ${RPMPATH}/${i}
    ${FAKEROOT} bash -c "cd ${RPMPATH} && ln -s usr/${i} ."
done

if grep -q -F "__perl_provides" ${RPMPATH}/etc/rpm/macros.perl ; then
    ${FAKEROOT} sed -i '/__perl_provides/d' ${RPMPATH}/etc/rpm/macros.perl
    ${FAKEROOT} sed -i '/__perl_requires/d' ${RPMPATH}/etc/rpm/macros.perl
fi

${FAKEROOT} \
    ${RPMPATH}/${RPM_INTERPRETER} \
        ${RPMPATH}/${RPM_PREFIX}/usr/bin/rpmdb \
        --initdb \
        --root=${RPMPATH} \
        --dbpath=/var/lib/rpm \
        --verbose

${FAKEROOT} mkdir -p ${RPMPATH}/var/lib/rpm

RPMS="${CWD}/${FILESYSTEM_RPMS}/*.rpm ${CWD}/${RPMBUILD_RPMS}/*.rpm"

if [ -n "${DEPS_RPMS:-}" ]; then
    RPMS="${RPMS} ${CWD}/${DEPS_RPMS:-}/*.rpm"
fi

${FAKEROOT} \
    ${RPMPATH}/${RPM_INTERPRETER} ${RPMPATH}/${RPM_BIN} \
        --install \
        --rcfile=${RPMPATH}/${RPM_RC} \
        --root=${RPMPATH} \
        --dbpath=/var/lib/rpm \
        --justdb \
        --verbose \
        ${FLAGS} \
        ${RPMS}

cp ${SPEC} ${RPMPATH}/rpmbuild

${FAKEROOT} ${CWD}/${COPY_FILES}

if [ ! -f ${RPMPATH}/usr/bin/ld ] && [ -f ${RPMPATH}/usr/bin/ld.gold ]; then
    (cd ${RPMPATH}/usr/bin ; ${FAKEROOT} ln -s ld.gold ld)
fi

${FAKECONTAINER} ${RPMPATH} \
    ${RPM_INTERPRETER} ${RPMBUILD_BIN} \
        --verbose -bb \
        --dbpath=/var/lib/rpm \
        --define='source_date_epoch_from_changelog 1' \
        --define='use_source_date_epoch_as_buildtime 1' \
        --define='clamp_mtime_to_source_date_epoch 1' \
        --define='debug_package %{nil}' \
        --define='_build_id_links none' \
        /rpmbuild/${SPEC_BASENAME}

mkdir -p {output}
exec cp $(find ${RPMPATH}/rpmbuild/RPMS -type f) ${OUTPUT}
