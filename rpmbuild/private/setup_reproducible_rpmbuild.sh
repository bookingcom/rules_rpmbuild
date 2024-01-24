#!/usr/bin/env bash

# extracts the rpmtree containing both rpm and rpmbuild changes the
# elf file to make it a bit more portable
env >/dev/stderr

set -eo pipefail

CWD=$(pwd)

mkdir -p rpmtree/opt/portable-rpm/bin rpmtree/opt/portable-rpm/lib64 rpmtree/opt/portable-rpm/lib rpmtree/opt/portable-rpm/sbin

${FAKEROOT} ${BSDTAR_BIN} -xkmf ${RPMTREE} -C rpmtree/opt/portable-rpm

pushd rpmtree/opt/portable-rpm

${CWD}/${FAKEROOT} rm -rf usr/share/man usr/local/share/man usr/share/zoneinfo usr/lib/.build-id run var
${CWD}/${FAKEROOT} rmdir mnt opt boot dev home media root srv tmp afs
${CWD}/${FAKEROOT} rm usr/tmp

${CWD}/${FAKEROOT} find -L ./bin ./lib64 ./lib ./sbin -maxdepth 1 -not -type d -exec mv {} usr/{} \;
${CWD}/${FAKEROOT} rmdir bin lib64 lib sbin
${CWD}/${FAKEROOT} rm etc/shadow etc/gshadow

# make all absolute symlinks relative as in https://unix.stackexchange.com/a/100955
${CWD}/${FAKEROOT} find . -lname '/*' -exec bash -c '
  for link; do
    target=$(readlink "$link")
    link=${link#./}
    root=${link//+([!\/])/..}; root=${root#/}; root=${root%..}
    rm "$link"
    ln -s "$root${target#/}" "$link"
  done
' _ {} +

patch_binary() {
    ${CWD}/${FAKEROOT} ${CWD}/${PATCHELF_BIN} --set-rpath \$ORIGIN/../lib64 $1
    ${CWD}/${FAKEROOT} ${CWD}/${PATCHELF_BIN} --add-rpath \$ORIGIN/../lib $1
}

patch_binary usr/bin/rpm
patch_binary usr/bin/rpmdb
patch_binary usr/bin/rpmbuild

for file in $(find usr/lib64); do
    if file "${file}" | grep -i elf | grep -v ld-linux- | grep -i -q 'dynamically linked' ; then
        ${CWD}/${FAKEROOT} ${CWD}/${PATCHELF_BIN} --set-rpath \$ORIGIN "${file}"
        ${CWD}/${FAKEROOT} ${CWD}/${PATCHELF_BIN} --add-rpath \$ORIGIN/../lib "${file}"
    fi
done

popd

# make sure all files have a consistent timestamp
${CWD}/${FAKEROOT} find rpmtree -exec touch -h -a -m -t 200101010000.00 {} \;

${CWD}/${FAKEROOT} touch -h -a -m -t 200101010000.00 rpmtree


${CWD}/${FAKEROOT} ${BSDTAR_BIN} -czf rpmtree.tar -C rpmtree .

mkdir -p $(dirname ${OUTPUT})
mv rpmtree.tar ${OUTPUT}
