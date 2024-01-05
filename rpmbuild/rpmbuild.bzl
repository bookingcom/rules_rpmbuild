load("@aspect_bazel_lib//lib:copy_file.bzl", "COPY_FILE_TOOLCHAINS", "copy_file_action")

TAR_TOOLCHAIN = "@aspect_bazel_lib//lib:tar_toolchain_type"

_RPMBUILD_CMD = """
set -exo pipefail

mkdir -p /tmp/rpmbuild/rpmbuild

{fakeroot} {tar} -xf {rpm_build_archive} -C /tmp/rpmbuild

if [ ! -z "{rpms}" ]; then
    cp --parents {rpms} /tmp/rpmbuild

    {fakecontainer} /tmp/rpmbuild /bin/rpm --rebuilddb

    {fakecontainer} \
        /tmp/rpmbuild \
            /bin/rpm \
                --install --force {flags} {rpms}
fi

cp {spec} /tmp/rpmbuild/rpmbuild

{copy_sources}

{fakecontainer} \
    /tmp/rpmbuild \
        /usr/bin/bash -c 'cd /rpmbuild && /usr/bin/rpmbuild --verbose -bb {spec_basename}'

mkdir -p {output}
cp $(find /tmp/rpmbuild/rpmbuild/RPMS -type f) {output}
"""

def _rpmbuild_impl(ctx):
    bsdtar = ctx.toolchains[TAR_TOOLCHAIN]

    out = ctx.actions.declare_directory("{}-output".format(ctx.label.name))

    sources = []
    for k, v in ctx.attr.sources.items():
        files = k.files.to_list()
        if len(files) > 1:
            fail("Source {} contains multiple files, expected single file".format(k))
        dst = ctx.actions.declare_file(v)
        copy_file_action(ctx, src=files[0], dst=dst)
        sources.append(dst)

    copy_sources = [
        "mkdir -p /tmp/rpmbuild/rpmbuild/{short_path} && cp {path} /tmp/rpmbuild/rpmbuild/{short_path}".format(short_path = x.short_path.rsplit("/", 1)[0], path = x.path) for x in sources
    ]

    ctx.actions.run_shell(
        inputs = depset(
            direct = ctx.files.rpms + ctx.files.spec_file + sources,
            transitive = [
                bsdtar.default.files,
                depset(direct = ctx.files._fakeroot + ctx.files._fakecontainer + ctx.files.rpm_build_archive),
            ],
        ),
        outputs = [out],
        command = _RPMBUILD_CMD.format(
            copy_sources = "\n".join(copy_sources),
            fakecontainer = ctx.executable._fakecontainer.path,
            fakeroot = ctx.executable._fakeroot.path,
            flags = " ".join(ctx.attr.rpm_install_flags),
            output = out.path,
            rpm_build_archive = ctx.file.rpm_build_archive.path,
            rpms = " ".join([x.path for x in ctx.files.rpms]),
            spec = ctx.file.spec_file.path,
            spec_basename = ctx.file.spec_file.basename,
            tar = bsdtar.tarinfo.binary.path,
        ),
        mnemonic = "BuildRpm",
    )

    return DefaultInfo(
        files = depset([out]),
    )

rpmbuild = rule(
    implementation = _rpmbuild_impl,
    attrs = {
        "rpm_build_archive": attr.label(allow_single_file = True, doc = "label with a ready to use rpm-build chroot"),
        "rpms": attr.label_list(allow_files = True, doc = "extra rpms required to install for the package to be built"),
        "spec_file": attr.label(allow_single_file = True, doc = "spec file for the rpm to be built"),
        "sources": attr.label_keyed_string_dict(allow_files = True, doc = "map of extra files required to build the rpm and their target location in the rpmbuild structure"),
        "rpm_install_flags": attr.string_list(default = [], doc = "flags to pass to rpm install"),
        "_fakeroot": attr.label(default = "//cmd/fakeroot", executable = True, cfg = "exec"),
        "_fakecontainer": attr.label(default = "//cmd/fake-container", executable = True, cfg = "exec"),
    },
    toolchains = [ TAR_TOOLCHAIN ] + COPY_FILE_TOOLCHAINS,
)
