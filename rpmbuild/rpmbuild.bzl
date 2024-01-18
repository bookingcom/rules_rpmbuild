load("@aspect_bazel_lib//lib:copy_file.bzl", "COPY_FILE_TOOLCHAINS", "copy_file_action")
load("//rpmbuild/private:utils.bzl", "utils")
load(":utils.bzl", "deduplicate_rpms")

TAR_TOOLCHAIN = "@aspect_bazel_lib//lib:tar_toolchain_type"
RPM_TOOLCHAIN = "@rules_rpmbuild//rpmbuild:reproducible_rpmbuild_toolchain_type"


def _copy_rpms(ctx, path, files):
    basepath = ""
    out = []
    for f in files:
        dst = ctx.actions.declare_file("external/{}/{}".format(path, f.basename))
        basepath = dst.path.rsplit("/", 1)[0]
        copy_file_action(ctx, src=f, dst=dst)
        out.append(dst)
    return basepath, out

def _rpmbuild_impl(ctx):
    out = ctx.actions.declare_directory("{}-output".format(ctx.label.name))

    rpm_path = "/tmp/rpm-{}-{}".format(
        ctx.label.package.replace("/", "-"),
        ctx.label.name
    )

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
                "mkdir -p %s/rpmbuild/%s" % (rpm_path, v.rsplit("/", 1)[0])
            )
        copy_sources.append(
            "cp %s %s/rpmbuild/%s" % (dst.path, rpm_path, v)
        )

    copy_files_script = ctx.actions.declare_file("%s-copy-files.sh" % ctx.label.name)
    ctx.actions.write(
        output = copy_files_script,
        is_executable = True,
        content = """#!/usr/bin/env bash

set -exuo pipefail

{}
""".format("\n".join(copy_sources))
    )

    filesystem_rpms_basepath, filesystem_rpms = _copy_rpms(ctx, "filesystem", ctx.files.filesystem_rpms)
    rpmbuild_rpms_basepath, rpmbuild_rpms = _copy_rpms(ctx, "rpmbuild", ctx.files.rpmbuild_rpms)

    env = utils.compute_env(ctx, {
        "OUTPUT": out.path,
        "SPEC": ctx.file.spec_file.path,
        "SPEC_BASENAME": ctx.file.spec_file.basename,
        "FLAGS": " ".join(ctx.attr.rpm_install_flags),
        "FILESYSTEM_RPMS": filesystem_rpms_basepath,
        "RPMBUILD_RPMS": rpmbuild_rpms_basepath,
        "COPY_FILES": copy_files_script.path,
        "FILESYSTEM_RPMTREE": ctx.file.filesystem_rpmtree.path,
        "RPMBUILD_RPMTREE": ctx.file.rpmbuild_rpmtree.path,
        "RPMPATH": rpm_path,
    })

    depset_direct = [copy_files_script] + \
        ctx.files._build_template + \
        ctx.files.deps_rpmtree + \
        ctx.files.rpmbuild_rpmtree + \
        ctx.files.filesystem_rpmtree + \
        ctx.files.spec_file + \
        utils.tool_dependencies(ctx) + \
        sources + \
        filesystem_rpms + \
        rpmbuild_rpms

    if ctx.attr.deps_rpmtree != None:
        print(ctx.attr.deps_rpmtree)
        if len(ctx.files.deps_rpms) == 0:
            fail("deps_rpms should not be an empty list if deps_rpmtree is not Null")
        deps_rpms_basepath, deps_rpms = _copy_rpms(ctx, "deps", ctx.files.deps_rpms)
        env["DEPS_RPMTREE"] = ctx.file.deps_rpmtree.path
        env["DEPS_RPMS"] = deps_rpms_basepath
        depset_direct = depset_direct + deps_rpms

    ctx.actions.run_shell(
        inputs = depset(
            direct = depset_direct,
            transitive = utils.toolchain_dependencies(ctx),
        ),
        env = env,
        outputs = [out],
        command = ctx.file._build_template.path,
        mnemonic = "BuildRpm",
    )

    return DefaultInfo(
        files = depset([out]),
    )

_rpmbuild_attrs = {
    "deps_rpms": attr.label_list(allow_files = True, allow_empty = True, doc = "build dependencies for the package to be built"),
    "deps_rpmtree":attr.label(allow_single_file = True, doc = "label with an rpmtree providing your dependencies"),
    "filesystem_rpms": attr.label_list(allow_files = True, allow_empty = False, doc = "rpms for the filesystem rpmtree"),
    "filesystem_rpmtree":attr.label(allow_single_file = True, doc = "label with an rpmtree providing a file system"),
    "rpmbuild_rpms": attr.label_list(allow_files = True, allow_empty = False, doc = "rpms for the rpm-build rpmtree for your system"),
    "rpmbuild_rpmtree":attr.label(allow_single_file = True, doc = "label with an working rpm-build for your system"),
    "rpm_install_flags": attr.string_list(default = [], doc = "flags to pass to rpm install"),
    "sources": attr.label_keyed_string_dict(allow_files = True, doc = "map of extra files required to build the rpm and their target location in the rpmbuild structure"),
    "spec_file": attr.label(allow_single_file = True, doc = "spec file for the rpm to be built"),
    "_build_template": attr.label(default = Label("//rpmbuild:rpmbuild.sh"), allow_single_file = True),
}

_rpmbuild_attrs.update(utils.common_attrs)

_rpmbuild = rule(
    implementation = _rpmbuild_impl,
    attrs = _rpmbuild_attrs,
    toolchains = utils.toolchains + COPY_FILE_TOOLCHAINS,
)

def rpmbuild(deps_rpms = [], filesystem_rpms = [], rpmbuild_rpms = [], **kwargs):
    rpmbuild_rpms = deduplicate_rpms(rpmbuild_rpms, filesystem_rpms)
    deps_rpms = deduplicate_rpms(deps_rpms, rpmbuild_rpms + filesystem_rpms)
    _rpmbuild(
        deps_rpms = deps_rpms,
        filesystem_rpms = filesystem_rpms,
        rpmbuild_rpms = rpmbuild_rpms,
        **kwargs
    )
