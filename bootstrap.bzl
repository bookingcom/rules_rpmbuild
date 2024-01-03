TAR_TOOLCHAIN = "@aspect_bazel_lib//lib:tar_toolchain_type"

_BOOTSTRAP_CMD = """
set -exo pipefail

mkdir -p rpm/chroot rpm/chroot/usr/bin rpm/chroot/usr/lib64 rpm/chroot/var/spool/mail rpm/chroot/tmp

( cd rpm/chroot && ln -s ./usr/bin bin && ln -s ./usr/lib64 lib64 )
( cd rpm/chroot/var && ln -s spool/mail mail )
( cd rpm/chroot/usr && ln -s ../tmp tmp )

{fakeroot} {tar} -xf {rpmtree} -C rpm

{fakeroot} \
    rpm/lib64/ld-linux-x86-64.so.2 \
    --library-path rpm/lib64:rpm/usr/lib:rpm/usr/lib64 \
    rpm/bin/rpm \
    --root $(pwd)/rpm/chroot \
    --dbpath /var/lib/rpm \
    --install --justdb --force --reinstall --verbose {filesystem}


{fakeroot} \
    rpm/lib64/ld-linux-x86-64.so.2 \
    --library-path rpm/lib64:rpm/usr/lib:rpm/usr/lib64 \
    rpm/bin/rpm \
    --root $(pwd)/rpm/chroot \
    --dbpath /var/lib/rpm \
    --install --force --verbose {rpms}

exec {fakeroot} {tar} -czf {output} -C rpm/chroot .
"""

def _bootstrap_impl(ctx):
    bsdtar = ctx.toolchains[TAR_TOOLCHAIN]

    out = ctx.actions.declare_file("bootstrap-target.tar.gz")

    rpms = " ".join([x.path for x in ctx.files.rpms])
    filesystem = " ".join([x.path for x in ctx.files.filesystem])

    ctx.actions.run_shell(
        inputs = depset(
            direct = ctx.files.rpm_rpmtree,
            transitive = [
                bsdtar.default.files,
                depset(direct = ctx.files._fakeroot + ctx.files.rpms + ctx.files.filesystem),
            ],
        ),
        outputs = [out],
        command = _BOOTSTRAP_CMD.format(
            tar = bsdtar.tarinfo.binary.path,
            output = out.path,
            rpmtree = ctx.file.rpm_rpmtree.path,
            fakeroot = ctx.executable._fakeroot.path,
            rpms = rpms,
            filesystem = filesystem,
        ),
        mnemonic = "CreateBootstrap",
    )

    return DefaultInfo(
        files = depset([out]),
    )

bootstrap = rule(
    implementation = _bootstrap_impl,
    attrs = {
        "rpms": attr.label_list(allow_files = True, doc = "list of RPMs to bootstrap the rpm binary"),
        "rpm_rpmtree": attr.label(doc = "bazeldnf rpmtree that provides an rpm binary", allow_single_file = True),
        "filesystem": attr.label_list(allow_files = True, doc = "list of labels pointing to the filesystem rpm and depedencies"),
        "_fakeroot": attr.label(default = "@fakeroot//cmd/nsfakeroot", executable = True, cfg = "exec"),
    },
    toolchains = [
        TAR_TOOLCHAIN,
    ],
)
