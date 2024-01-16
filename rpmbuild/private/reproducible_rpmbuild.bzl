"A toolchain that contains rpm and rpmbuild with SOURCE_DATE_EPOCH support"

# inspired in https://github.com/aspect-build/bazel-lib/blob/1be6994ca62ba897cb7cebf5cb6e9a1d551aca01/lib/private/tar_toolchain.bzl

REPRODUCIBLE_RPMBUILD_PLATFORMS = {
    "linux_x86_64": struct(
        compatible_with = [
            "@platforms//os:linux",
            "@platforms//cpu:x86_64",
        ],
    ),
    "linux_aarch64": struct(
        compatible_with = [
            "@platforms//os:linux",
            "@platforms//cpu:aarch64",
        ],
    ),
}

LINUX_RPMTREE = {
    "linux_x86_64": "@rpm-build-centos9//:rpms",
}

_BINARY_TEMPLATE = """\
# @generated by @rules_rpmbuild//rpmbuild/private:reproducible_rpmbuild.bzl
load("@rules_rpmbuild//rpmbuild/private:reproducible_rpmbuild.bzl", "rpmbuild_toolchain")

rpmbuild_toolchain(
    name = "rpmbuild_toolchain",
    rpmtree = "{rpmtree}",
    visibility = ["//visibility:public"],
)
"""

def _rpmbuild_binary_repo(rctx):
    if not rctx.os.name.lower().startswith("linux"):
        fail("This toolchain is only compatible with linux right now")

    if rctx.attr.platform not in LINUX_RPMTREE:
        fail("The requested architecture {} is not support yet".format(rctx.attr.platform))

    rctx.file(
        "BUILD.bazel",
        _BINARY_TEMPLATE.format(
            rpmtree = LINUX_RPMTREE[rctx.attr.platform],
        ),
    )

rpmbuild_binary_repo = repository_rule(
    implementation = _rpmbuild_binary_repo,
    attrs = {
        "platform": attr.string(mandatory = True, values = REPRODUCIBLE_RPMBUILD_PLATFORMS.keys()),
    },
)

ReproducibleRPMBuildToolchainInfo = provider(
    doc = "Provide info for executing a reproducible build rpm/rpmbuild",
    fields = {
        "archive": "archive containing the tools",
    },
)

TAR_TOOLCHAIN = "@aspect_bazel_lib//lib:tar_toolchain_type"
PATCHELF_TOOLCHAIN = "@rules_rpmbuild//rpmbuild:patchelf_toolchain_type"

def _rpmbuild_toolchain_impl(ctx):
    tar = ctx.toolchains[TAR_TOOLCHAIN]
    patchelf = ctx.toolchains[PATCHELF_TOOLCHAIN]

    out = ctx.actions.declare_file("%s.tar" % ctx.label.name)

    env = {
        "OUTPUT": out.path,
        "RPMTREE": ctx.file.rpmtree.path,
        "FAKEROOT": ctx.file._fakeroot.path
    }

    for t in [tar, patchelf]:
        for k, v in t.template_variables.variables.items():
            env[k] = v

    ctx.actions.run_shell(
        inputs = depset(
            direct = [ ctx.file._prepare, ctx.file.rpmtree, ctx.file._fakeroot ],
            transitive = [
                tar.default.files,
                patchelf.default.files,
            ],
        ),
        outputs = [ out ],
        env = env,
        command = ctx.file._prepare.path,
        mnemonic = "ReproducibleRPMBuildSetup",

    )

    # Make the $(RPM_BIN) and $(RPMBUILD_BIN) variable available in places like genrules.
    # See https://docs.bazel.build/versions/main/be/make-variables.html#custom_variables
    template_variables = platform_common.TemplateVariableInfo({
        "RPM_BIN": "opt/portable-rpm/usr/bin/rpm",
        "RPMBUILD_BIN": "opt/portable-rpm/usr/bin/rpmbuild",
        "RPM_INTERPRETER": "opt/portable-rpm/usr/lib64/ld-linux-x86-64.so.2",
        "RPM_PREFIX": "opt/portable-rpm",
        "RPM_RC": "opt/portable-rpm/usr/lib/rpm/rpmrc"
    })

    default_info = DefaultInfo(
        files = depset( [ out ] ),
    )

    reproducible_rpmbuild_info = ReproducibleRPMBuildToolchainInfo(
        archive = "out",
    )

    # Export all the providers inside our ToolchainInfo
    # so the resolved_toolchain rule can grab and re-export them.
    toolchain_info = platform_common.ToolchainInfo(
        rpmbuildinfo = reproducible_rpmbuild_info,
        template_variables = template_variables,
        package = depset([out]).to_list()[0],
        default = default_info,
    )

    return [toolchain_info, template_variables, default_info]

rpmbuild_toolchain = rule(
    implementation = _rpmbuild_toolchain_impl,
    attrs = {
        "files": attr.label_list(allow_files = True),
        "rpmtree": attr.label(allow_single_file = True, mandatory = True),
        "_prepare": attr.label(allow_single_file = True, default = "//rpmbuild/private:setup_reproducible_rpmbuild.sh"),
        "_fakeroot": attr.label(allow_single_file = True, default = "//cmd/fakeroot"),
    },
    toolchains = [
        TAR_TOOLCHAIN,
        PATCHELF_TOOLCHAIN
    ],
)

def _rpmbuild_toolchains_repo_impl(rctx):
    # Expose a concrete toolchain which is the result of Bazel resolving the toolchain
    # for the execution or target platform.
    # Workaround for https://github.com/bazelbuild/bazel/issues/14009
    starlark_content = """\
# @generated by @rules_rpmbuild//rpmbuild/private:reproducible_rpmbuild.bzl

# Forward all the providers
def _resolved_toolchain_impl(ctx):
    toolchain_info = ctx.toolchains["@rules_rpmbuild//rpmbuild:reproducible_rpmbuild_toolchain_type"]
    return [
        toolchain_info,
        toolchain_info.default,
        toolchain_info.rpmbuildinfo,
        toolchain_info.template_variables,
    ]

# Copied from java_toolchain_alias
# https://cs.opensource.google/bazel/bazel/+/master:tools/jdk/java_toolchain_alias.bzl
resolved_toolchain = rule(
    implementation = _resolved_toolchain_impl,
    toolchains = ["@rules_rpmbuild//rpmbuild:reproducible_rpmbuild_toolchain_type"],
    incompatible_use_toolchain_transition = True,
)
"""
    rctx.file("defs.bzl", starlark_content)

    build_content = """# @generated by @rules_rpmbuild//rpmbuild/private:rpmbuild_toolchain.bzl
load(":defs.bzl", "resolved_toolchain")
load("@local_config_platform//:constraints.bzl", "HOST_CONSTRAINTS")

resolved_toolchain(name = "resolved_toolchain", visibility = ["//visibility:public"])"""

    for [platform, meta] in REPRODUCIBLE_RPMBUILD_PLATFORMS.items():
        build_content += """
toolchain(
    name = "{platform}_toolchain",
    exec_compatible_with = {compatible_with},
    toolchain = "@{user_repository_name}_{platform}//:rpmbuild_toolchain",
    toolchain_type = "@rules_rpmbuild//rpmbuild:reproducible_rpmbuild_toolchain_type",
)
""".format(
            platform = platform,
            user_repository_name = rctx.attr.user_repository_name,
            compatible_with = meta.compatible_with,
        )

    rctx.file("BUILD.bazel", build_content)

rpmbuild_toolchains_repo = repository_rule(
    _rpmbuild_toolchains_repo_impl,
    doc = """Creates a repository that exposes a reproducible_rpmbuild_toolchain_type target.""",
    attrs = {
        "user_repository_name": attr.string(doc = "Base name for toolchains repository"),
    },
)

DEFAULT_REPRODUCIBLE_RPMBUILD_REPOSITORY = "reproducible_rpmbuild"

def register_reproducible_rpmbuild_toolchains(name = DEFAULT_REPRODUCIBLE_RPMBUILD_REPOSITORY, register = True):
    """Registers reproducible rpmbuild toolchain and repositories

    Args:
        name: override the prefix for the generated toolchain repositories
        register: whether to call through to native.register_toolchains.
            Should be True for WORKSPACE users, but false when used under bzlmod extension
    """
    for [platform, meta] in REPRODUCIBLE_RPMBUILD_PLATFORMS.items():
        rpmbuild_binary_repo(
            name = "%s_%s" % (name, platform),
            platform = platform,
            compatible_with = meta.compatible_with,
        )
        if register:
            native.register_toolchains("@%s_toolchains//:%s_toolchain" % (name, platform))

    rpmbuild_toolchains_repo(
        name = "%s_toolchains" % name,
        user_repository_name = name,
    )
