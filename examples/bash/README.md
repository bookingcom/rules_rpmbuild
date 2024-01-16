# About

A sample use of rules_rpmbuild to build a valid rpm for bash (maybe it doesn't work)

## Setup

To initialize the yum mirrors you need to run:

```bash
bazel run @rules_rpmbuild//rpmbuild:bazeldnf -- fetch -r ../../rpm-repos/centos7.yaml
```

Updating the dependencies:

```bash
bazel run @rules_rpmbuild//rpmbuild:bazeldnf -- rpmtree \
    --repofile ../../rpm-repos/centos7.yaml \
    --arch x86_64 \
    --basesystem centos-release \
    --bzlmod \
    --lock-file bash-rpm-deps.json \
    --name bash-rpm-deps \
    autoconf binutils bison coreutils \
    diffutils findutils gcc gcc-c++ gettext \
    gzip make ncurses-devel tar texinfo
```
