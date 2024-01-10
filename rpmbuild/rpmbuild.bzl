load("@aspect_bazel_lib//lib:copy_file.bzl", "COPY_FILE_TOOLCHAINS", "copy_file_action")
load(":utils.bzl", "deduplicate_rpms")

TAR_TOOLCHAIN = "@aspect_bazel_lib//lib:tar_toolchain_type"

def _rpmbuild_impl(ctx):
    bsdtar = ctx.toolchains[TAR_TOOLCHAIN]

    out = ctx.actions.declare_directory("{}-output".format(ctx.label.name))

    sources = []
    copy_sources = []
    for k, v in ctx.attr.sources.items():
        files = k.files.to_list()
        if len(files) > 1:
            fail("Source {} contains multiple files, expected single file".format(k))
        dst = ctx.actions.declare_file(v)
        copy_file_action(ctx, src=files[0], dst=dst)
        sources.append(dst)
        if "/" in v:
            copy_sources.append(
                "mkdir -p /tmp/rpmbuild/rpmbuild/%s" % (v.rsplit("/", 1)[0])
            )
        copy_sources.append(
            "cp %s /tmp/rpmbuild/rpmbuild/%s" % (dst.path, v)
        )

    script = ctx.actions.declare_file("%s.sh" % ctx.label.name)

    ctx.actions.expand_template(
        template = ctx.file._build_template,
        output = script,
        substitutions = {
            "{copy_sources}": "\n".join(copy_sources),
            "{fakecontainer}": ctx.executable._fakecontainer.path,
            "{fakeroot}": ctx.executable._fakeroot.path,
            "{flags}": " ".join(ctx.attr.rpm_install_flags),
            "{output}": out.path,
            "{rpm_build_archive}": ctx.file.rpm_build_archive.path,
            "{rpms}": " ".join([x.path for x in ctx.files.rpms]),
            "{spec}": ctx.file.spec_file.path,
            "{spec_basename}": ctx.file.spec_file.basename,
            "{tar}": bsdtar.tarinfo.binary.path,
        },
        is_executable = True,
    )

    ctx.actions.run_shell(
        inputs = depset(
            direct = [script] +
                ctx.files.rpms +
                ctx.files.spec_file +
                sources +
                ctx.files._fakeroot +
                ctx.files._fakecontainer +
                ctx.files.rpm_build_archive,
            transitive = [
                bsdtar.default.files,
            ],
        ),
        outputs = [out],
        command = script.path,
        mnemonic = "BuildRpm",
    )

    return DefaultInfo(
        files = depset([out]),
    )

_rpmbuild = rule(
    implementation = _rpmbuild_impl,
    attrs = {
        "rpm_build_archive": attr.label(allow_single_file = True, doc = "label with a ready to use rpm-build chroot"),
        "rpms": attr.label_list(allow_files = True, doc = "extra rpms required to install for the package to be built"),
        "spec_file": attr.label(allow_single_file = True, doc = "spec file for the rpm to be built"),
        "sources": attr.label_keyed_string_dict(allow_files = True, doc = "map of extra files required to build the rpm and their target location in the rpmbuild structure"),
        "rpm_install_flags": attr.string_list(default = [], doc = "flags to pass to rpm install"),
        "_fakeroot": attr.label(default = "//cmd/fakeroot", executable = True, cfg = "exec"),
        "_fakecontainer": attr.label(default = "//cmd/fake-container", executable = True, cfg = "exec"),
        "_build_template": attr.label(default = Label("//rpmbuild:rpmbuild.sh"), allow_single_file = True),
    },
    toolchains = [ TAR_TOOLCHAIN ] + COPY_FILE_TOOLCHAINS,
)

def rpmbuild(rpms = [], rpm_build_rpms = [], **kwargs):
    rpms = deduplicate_rpms(rpms, rpm_build_rpms)
    _rpmbuild(rpms = rpms, **kwargs)
