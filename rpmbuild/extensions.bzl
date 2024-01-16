"Module extensions for use with bzlmod"

load("@aspect_bazel_lib//lib/private:extension_utils.bzl", "extension_utils")
load("//rpmbuild/private:patchelf.bzl", "DEFAULT_PATCHELF_REPOSITORY", "register_patchelf_toolchains")
load("//rpmbuild/private:reproducible_rpmbuild.bzl", "DEFAULT_REPRODUCIBLE_RPMBUILD_REPOSITORY", "register_reproducible_rpmbuild_toolchains")

def _toolchains_extension_impl(mctx):
    extension_utils.toolchain_repos_bfs(
        mctx = mctx,
        get_tag_fn = lambda tags: tags.patchelf,
        #default_repository = "patchelf_toolchains",
        toolchain_name = "patchelf",
        toolchain_repos_fn = lambda name, version: register_patchelf_toolchains(name = name, register = False),
        get_version_fn = lambda attr: None,
    )
    extension_utils.toolchain_repos_bfs(
        mctx = mctx,
        get_tag_fn = lambda tags: tags.reproducible_rpmbuild,
        #default_repository = "reproducible_rpmbuild_toolchains",
        toolchain_name = "reproducible_rpmbuild",
        toolchain_repos_fn = lambda name, version: register_reproducible_rpmbuild_toolchains(name = name, register = False),
        get_version_fn = lambda attr: None,
    )

toolchains = module_extension(
    implementation = _toolchains_extension_impl,
    tag_classes = {
        "patchelf": tag_class(attrs = {"name": attr.string(default = DEFAULT_PATCHELF_REPOSITORY)}),
        "reproducible_rpmbuild": tag_class(attrs = {"name": attr.string(default = DEFAULT_REPRODUCIBLE_RPMBUILD_REPOSITORY)}),
    },
)
