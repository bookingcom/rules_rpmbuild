"Provide access to a NixOS patchelf https://github.com/NixOS/patchelf"

# inspired in https://github.com/aspect-build/bazel-lib/blob/1be6994ca62ba897cb7cebf5cb6e9a1d551aca01/lib/private/tar_toolchain.bzl

PATCHELF_PLATFORMS = {
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

LINUX_BINARIES = {
    "linux_x86_64": [
        "https://github.com/NixOS/patchelf/releases/download/0.18.0/patchelf-0.18.0-x86_64.tar.gz",
        "ce84f2447fb7a8679e58bc54a20dc2b01b37b5802e12c57eece772a6f14bf3f0"
    ],
    "linux_aarch64": [
        "https://github.com/NixOS/patchelf/releases/download/0.18.0/patchelf-0.18.0-aarch64.tar.gz",
        "ae13e2effe077e829be759182396b931d8f85cfb9cfe9d49385516ea367ef7b2"
    ]
}


_PATCHELF_TEMPLATE="""\
# @generated by @rules_rpmbuild//rpmbuild/private:patchelf.bzl

load("@rules_rpmbuild//rpmbuild/private:patchelf.bzl", "patchelf_toolchain")

patchelf_toolchain(
    name = "patchelf_toolchain",
    files = ["bin/patchelf"],
    binary = "bin/patchelf",
    visibility = ["//visibility:public"],
)
"""
def _patchelf_binary_repo(rctx):
    if not rctx.os.name.lower().startswith("linux"):
        fail("This toolchain is only compatible with linux right now")

    if rctx.attr.platform not in LINUX_BINARIES:
        fail("The requested architecture {} is not support yet".format(rctx.attr.platform))

    rctx.download_and_extract(
        url = LINUX_BINARIES[rctx.attr.platform][0],
        sha256 = LINUX_BINARIES[rctx.attr.platform][1],
    )

    rctx.file("BUILD.bazel", _PATCHELF_TEMPLATE)

patchelf_binary_repo = repository_rule(
    implementation = _patchelf_binary_repo,
    attrs = {
        "platform": attr.string(mandatory = True, values = PATCHELF_PLATFORMS.keys()),
    },
)

PatchELFInfo = provider(
    doc = "Provide info for executing NixOS patchelf",
    fields = {
        "binary": "patchelf executable",
    },
)

def _patchelf_toolchain_impl(ctx):
    binary = ctx.executable.binary

    # Make the $(PATCHELF_BIN) variable available in places like genrules.
    # See https://docs.bazel.build/versions/main/be/make-variables.html#custom_variables
    template_variables = platform_common.TemplateVariableInfo({
        "PATCHELF_BIN": binary.path,
    })

    default_info = DefaultInfo(
        files = depset(ctx.files.binary + ctx.files.files),
    )
    patchelfinfo = PatchELFInfo(
        binary = binary,
    )

    # Export all the providers inside our ToolchainInfo
    # so the resolved_toolchain rule can grab and re-export them.
    toolchain_info = platform_common.ToolchainInfo(
        patchelfinfo = patchelfinfo,
        template_variables = template_variables,
        default = default_info,
    )

    return [toolchain_info, template_variables, default_info]

patchelf_toolchain = rule(
    implementation = _patchelf_toolchain_impl,
    attrs = {
        "binary": attr.label(
            doc = "a command to find on the system path",
            allow_files = True,
            executable = True,
            cfg = "exec",
        ),
        "files": attr.label_list(allow_files = True),
    },
)

def _patchelf_toolchains_repo_impl(rctx):
    # Expose a concrete toolchain which is the result of Bazel resolving the toolchain
    # for the execution or target platform.
    # Workaround for https://github.com/bazelbuild/bazel/issues/14009
    starlark_content = """\
# @generated by @rules_rpmbuild//rpmbuild/private:patchelf.bzl

# Forward all the providers
def _resolved_toolchain_impl(ctx):
    toolchain_info = ctx.toolchains["@rules_rpmbuild//rpmbuild:patchelf_toolchain_type"]
    return [
        toolchain_info,
        toolchain_info.default,
        toolchain_info.patchelfinfo,
        toolchain_info.template_variables,
    ]

# Copied from java_toolchain_alias
# https://cs.opensource.google/bazel/bazel/+/master:tools/jdk/java_toolchain_alias.bzl
resolved_toolchain = rule(
    implementation = _resolved_toolchain_impl,
    toolchains = ["@rules_rpmbuild//rpmbuild:patchelf_toolchain_type"],
    incompatible_use_toolchain_transition = True,
)
"""
    rctx.file("defs.bzl", starlark_content)

    build_content = """# @generated by @rules_rpmbuild//rpmbuild/private:patchelf_toolchain.bzl
load(":defs.bzl", "resolved_toolchain")
load("@local_config_platform//:constraints.bzl", "HOST_CONSTRAINTS")

resolved_toolchain(name = "resolved_toolchain", visibility = ["//visibility:public"])"""

    for [platform, meta] in PATCHELF_PLATFORMS.items():
        build_content += """
toolchain(
    name = "{platform}_toolchain",
    exec_compatible_with = {compatible_with},
    toolchain = "@{user_repository_name}_{platform}//:patchelf_toolchain",
    toolchain_type = "@rules_rpmbuild//rpmbuild:patchelf_toolchain_type",
)
""".format(
            platform = platform,
            user_repository_name = rctx.attr.user_repository_name,
            compatible_with = meta.compatible_with,
        )

    rctx.file("BUILD.bazel", build_content)

patchelf_toolchains_repo = repository_rule(
    _patchelf_toolchains_repo_impl,
    doc = """Creates a repository that exposes a patchelf_toolchain_type target.""",
    attrs = {
        "user_repository_name": attr.string(doc = "Base name for toolchains repository"),
    },
)

DEFAULT_PATCHELF_REPOSITORY = "patchelf"

def register_patchelf_toolchains(name = DEFAULT_PATCHELF_REPOSITORY, register = True):
    """Registers patchelf toolchain and repositories

    Args:
        name: override the prefix for the generated toolchain repositories
        register: whether to call through to native.register_toolchains.
            Should be True for WORKSPACE users, but false when used under bzlmod extension
    """
    for [platform, meta] in PATCHELF_PLATFORMS.items():
        patchelf_binary_repo(
            name = "%s_%s" % (name, platform),
            platform = platform,
            compatible_with = meta.compatible_with
        )
        if register:
            native.register_toolchains("@%s_toolchains//:%s_toolchain" % (name, platform))

    patchelf_toolchains_repo(
        name = "%s_toolchains" % name,
        user_repository_name = name,
    )
