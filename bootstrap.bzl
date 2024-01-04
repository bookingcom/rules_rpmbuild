TAR_TOOLCHAIN = "@aspect_bazel_lib//lib:tar_toolchain_type"

_BOOTSTRAP_CMD = """
set -exo pipefail

mkdir -p /tmp/rpm/chroot /tmp/rpm/chroot/usr/bin /tmp/rpm/chroot/usr/lib64 /tmp/rpm/chroot/var/spool/mail /tmp/rpm/chroot/tmp

( cd /tmp/rpm/chroot && ln -s ./usr/bin bin && ln -s ./usr/lib64 lib64 )
( cd /tmp/rpm/chroot/var && ln -s spool/mail mail )
( cd /tmp/rpm/chroot/usr && ln -s ../tmp tmp )

{fakeroot} {tar} -xf {rpmtree} -C /tmp/rpm

cp --parents {filesystem} {rpms} /tmp/rpm

{fakecontainer} \
    /tmp/rpm \
        /bin/rpm \
            --root /chroot \
            --dbpath /var/lib/rpm \
            --install --justdb --force --reinstall --verbose {filesystem}

cp --parents -f {rpms} /tmp/rpm

{fakecontainer} \
    /tmp/rpm \
        /bin/rpm \
            --root /chroot \
            --dbpath /var/lib/rpm \
            --install --force --verbose {flags} {rpms}

exec {fakeroot} {tar} -czf {output} -C /tmp/rpm/chroot .
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
                depset(direct = ctx.files._fakeroot + ctx.files._fakecontainer + ctx.files.rpms + ctx.files.filesystem),
            ],
        ),
        outputs = [out],
        command = _BOOTSTRAP_CMD.format(
            tar = bsdtar.tarinfo.binary.path,
            output = out.path,
            rpmtree = ctx.file.rpm_rpmtree.path,
            fakeroot = ctx.executable._fakeroot.path,
            fakecontainer = ctx.executable._fakecontainer.path,
            rpms = rpms,
            filesystem = filesystem,
            flags = " ".join(ctx.attr.rpm_install_flags),
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
        "rpm_install_flags": attr.string_list(default = [], doc = "flags to pass to rpm install"),
        "_fakeroot": attr.label(default = "@fakeroot//cmd/nsfakeroot", executable = True, cfg = "exec"),
        "_fakecontainer": attr.label(default = "//cmd/fake-container", executable = True, cfg = "exec"),
    },
    toolchains = [
        TAR_TOOLCHAIN,
    ],
)
