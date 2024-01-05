TAR_TOOLCHAIN = "@aspect_bazel_lib//lib:tar_toolchain_type"

def _bootstrap_impl(ctx):
    bsdtar = ctx.toolchains[TAR_TOOLCHAIN]

    out = ctx.actions.declare_file("%s.tar.gz" % ctx.label.name)

    rpms = " ".join([x.path for x in ctx.files.rpms])
    filesystem = " ".join([x.path for x in ctx.files.filesystem])

    script = ctx.actions.declare_file("%s.sh" % ctx.label.name)

    ctx.actions.expand_template(
        template = ctx.file._bootstrap_template,
        output = script,
        substitutions = {
            "{tar}": bsdtar.tarinfo.binary.path,
            "{output}": out.path,
            "{rpmtree}": ctx.file.rpm_rpmtree.path,
            "{fakeroot}":  ctx.executable._fakeroot.path,
            "{fakecontainer}": ctx.executable._fakecontainer.path,
            "{rpms}": rpms,
            "{filesystem}": filesystem,
            "{flags}": " ".join(ctx.attr.rpm_install_flags),
        },
        is_executable = True,
    )

    ctx.actions.run_shell(
        inputs = depset(
            direct = [ script ] +
                ctx.files.rpm_rpmtree +
                ctx.files._fakeroot +
                ctx.files._fakecontainer +
                ctx.files.rpms +
                ctx.files.filesystem,
            transitive = [
                bsdtar.default.files,
            ],
        ),
        outputs = [out],
        command = script.path,
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
        "_fakeroot": attr.label(default = "//cmd/fakeroot", executable = True, cfg = "exec"),
        "_fakecontainer": attr.label(default = "//cmd/fake-container", executable = True, cfg = "exec"),
        "_bootstrap_template": attr.label(default = Label("//rpmbuild:bootstrap.sh"), allow_single_file = True),
    },
    toolchains = [
        TAR_TOOLCHAIN,
    ],
)
