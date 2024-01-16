"A collection of helpers for our rules"

TAR_TOOLCHAIN = "@aspect_bazel_lib//lib:tar_toolchain_type"
RPM_TOOLCHAIN = "@rules_rpmbuild//rpmbuild:reproducible_rpmbuild_toolchain_type"

COMMON_ATTRS = {
    "_fakeroot": attr.label(default = "//cmd/fakeroot", executable = True, cfg = "exec"),
    "_fakecontainer": attr.label(default = "//cmd/fake-container", executable = True, cfg = "exec"),
}

def compute_env(ctx, env = {}):
    """Computes the enviroment to pass into an actions

    Args:
        ctx: The rule context
        env: The environment dictionary to populate

    Returns:
        The populated environment dictionary
    """
    for name in [TAR_TOOLCHAIN, RPM_TOOLCHAIN]:
        if name not in ctx.toolchains:
            continue
        toolchain = ctx.toolchains[name]
        for k, v in toolchain.template_variables.variables.items():
            env[k] = v
        if name == RPM_TOOLCHAIN:
            env["RPM_ARCHIVE"] = toolchain.default.files.to_list()[0].path

    if getattr(ctx.executable, "_fakeroot", None):
        env["FAKEROOT"] = ctx.executable._fakeroot.path

    if getattr(ctx.executable, "_fakecontainer", None):
        env["FAKECONTAINER"] = ctx.executable._fakecontainer.path

    return env

def toolchain_dependencies(ctx):
    """Computes the list of files required from the available toolchains

    Args:
        ctx: rule context

    Returns:
        files required by all the registered toolchains
    """
    out = []
    for toolchain in [TAR_TOOLCHAIN, RPM_TOOLCHAIN]:
        if toolchain not in ctx.toolchains:
            continue
        out.append(ctx.toolchains[toolchain].default.files)
    return out

def tool_dependencies(ctx):
    return ctx.files._fakeroot + ctx.files._fakecontainer

utils = struct(
    tar_toolchain = TAR_TOOLCHAIN,
    rpm_toolchain = RPM_TOOLCHAIN,
    toolchains = [TAR_TOOLCHAIN, RPM_TOOLCHAIN],
    common_attrs = COMMON_ATTRS,
    compute_env = compute_env,
    toolchain_dependencies = toolchain_dependencies,
    tool_dependencies = tool_dependencies
)
