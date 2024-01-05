# About

A sample use of rules_rpmbuild to build a valid rpm for bash (maybe it doesn't work)

## Setup

To initialize the yum mirrors you need to run:

```bash
bazel run @rules_rpmbuild//rpmbuild:bazeldnf -- fetch -r ../../rpm-repos/centos7.yaml
```

Updating the dependencies:

```bash
bazel run @rules_rpmbuild//rpmbuild:bazeldnf -- fetch -r ../../rpm-repos/centos7.yaml
```
