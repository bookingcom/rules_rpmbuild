# rules_rpmbuild

Complete rules for rpmbuild packaging. This rules are insipired in the legacy mode
of `rules_pkg` rpmbuild tooling, but with the added advantage of being able to handle
a fake container where rpmbuild gets called, allowing users of the rule to install
extra packages required for each build file, isolating the build process from the
host where the build is happening.

## Usage

For usage look into the `examples` directory.

## Debugging

Sometimes a build fails and you want to debug, since bazel 7 by default `tmp` gets mapped
and isolated from the host, which is great for builds, but kind of a pain for anyone trying
to debug what's going on, if you enable `--noincompatible_sandbox_hermetic_tmp` flag on the
build then `/tmp` doesn't get mapped and you can debug inside `/tmp/rpmbuild`.

The best approach to debug is to try to build your RPM with `--noincompatible_sandbox_hermetic_tmp`,
wait for the build to fail, and then execute:

```bash
bazel run @rules_rpmbuild//cmd/fake-container -- /tmp/rpmbuild bash
cd /rpmbuild
rpmbuild --verbose -bb {spec-file}
```

{spec-file} is copied and not symlinked, so if you make changes in your host you need to
copy it into `/tmp/rpmbuild/rpmbuild` before running a new build.

## How to use

The way this rules work are rather simple (even though it looks complex), first we make use
of [bazeldnf](https://github.com/rmohr/bazeldnf) to manage the RPMs we put into the
fake container, the _bazel bzlmod_ support we need from bazeldnf hasn't been
merged yet, that's why your `MODULE.bazel` needs a block like:

```python
BAZELDNF_COMMIT = "8e110d32399ab1c3db08e18f015b3e7e092a27de"

bazel_dep(name = "bazeldnf", version = "0.6.0")
archive_override(
    module_name = "bazeldnf",
    integrity = "sha256-x1+AOKCknpmFjGfdPJ5cR6+lhjjKX0zh5vlVn2YYHuM=",
    strip_prefix = "bazeldnf-%s" % BAZELDNF_COMMIT,
    urls = [
        "https://github.com/bookingcom/bazeldnf/archive/%s.tar.gz" % BAZELDNF_COMMIT,
    ],
)
```

We're working with the bazeldnf team to get bazeldnf merged. Once that's merged we will
release to the bazel central registry as well.

_bazeldnf_ is used to create a fake container that contains rpmbuild for your distribution,
we provide an example one for CentOS7 in the `rpmtree` directory, together with a
public rpm mirror configuration under `rpm-repos`.

In order to generate your distribution `rpm-build` rpm tree you will start by creating your
own rpm repo yaml configuration file pointing to all the repositories you need.

Then you can generate the rpm tree by running:

```bash
bazel run @rules_rpmbuild//rpmbuild:bazeldnf -- fetch --repofile {config.yaml}

# on CentOS7 there's a special rpm called filesystem which creates
# a working file system, with some symlinks, this one is hard to
# run properly so we need to strip it out
bazel run @rules_rpmbuild//rpmbuild:bazeldnf -- rpmtree \
    --repofile {config.yaml} \
    --arch {your-target-arch} \
    --basesystem {your-base-system for centos-release} \
    --bzlmod \
    --lock-file {path-to-your-filesystem-lockfile} \
    --name {your filesystem rpmtree name} \
    filesystem

bazel run @rules_rpmbuild//rpmbuild:bazeldnf -- rpmtree \
    --repofile {config.yaml} \
    --arch {your-target-arch} \
    --basesystem {your-base-system for centos-release} \
    --bzlmod \
    --lock-file {path-to-your-rpm-build-lockfile} \
    --name{your rpm-build rpmtree name} \
    rpm-build
```

Then you need to create a `BUILD.bazel` with

```python
load("@{your filesystem rpmtree name}//:rpms.bzl", _filesystem = "RPMS")
load("@{your rpm-build rpmtree name}//:rpms.bzl", "RPMS")
load("@rules_rpmbuild//rpmbuild:bootstrap.bzl", "bootstrap")

bootstrap(
    name = "rpm-build",
    filesystem = _filesystem,
    rpm_install_flags = [
        # you may need a few flags to rpm --install, this are the ones we collected for CentOS7
        "--excludepath=/var/spool/mail",
        "--excludepath=/usr/libexec/utempter",
        "--excludepath=/usr/bin/write",
        "--excludepath=/usr/libexec/dbus-1/dbus-daemon-launch-helper",
    ],
    rpm_rpmtree = "@{your rpm-build rpm tree name}//:rpms",
    rpms = RPMS,
    visibility = ["//visibility:public"],
)
```

Once you have `rpm-build` available is time to build your spec file.

Most likely you require extra dependencies, for that we will create
another rpm tree, for example to generate the one for `bash` we did:

```bash
bazel run @rules_rpmbuild//rpmbuild:bazeldnf -- rpmtree \
    --repofile ../../rpm-repos/centos7.yaml \
    --arch x86_64 \
    --basesystem centos-release \
    --bzlmod \
    --lock-file bash-rpm-deps.json \
    --name bash-rpm-deps \
    make texinfo bison ncurses-devel autoconf gettext gcc gcc-c++ coreutils
```

### Fake containers

To create a fake container without requiring a container runtime like `docker` we use
a setup based on Linux namespaces with overrides. The concept is not so hard,
but it's too complex to describe as part of this document, a good reference paper
[is this one](https://www.toptal.com/linux/separation-anxiety-isolating-your-system-with-linux-namespaces#)
we recommend you read it and try to grasp it.

Basically we use namespaces to create a fake environment running with a regular user
where inside the environment the system thinks it's running as root (with root
mapped to the caller user), we isolate the network, and we chroot into the fake
container root. We also mount bind a few special files required for `rpm` and
`rpmbuild` to work like `/dev/urandom`, `/dev/random` and `/dev/null`.

The build is not yet 100% reproducible, you need rpm-build >= 4.13 which is not
available for all CentOS versions, once CentOS 7 is finally EOL we will do the
full change.
