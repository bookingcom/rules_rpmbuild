%define patchleveltag .21
%define baseversion 5.2
%bcond_without tests

%if 0%{?rhel} < 8
%undefine _annotated_build
%endif

Version: %{baseversion}%{patchleveltag}
Name: bash
Summary: The GNU Bourne Again shell
Release: 1%{?dist}
Group: System Environment/Shells
License: GPLv3+
Url: http://www.gnu.org/software/bash
Source0: bash.tar.gz


BuildRequires: autoconf
BuildRequires: binutils
BuildRequires: bison
BuildRequires: coreutils
BuildRequires: diffutils
BuildRequires: findutils
BuildRequires: gcc
BuildRequires: gcc-c++
BuildRequires: gettext
BuildRequires: gzip
BuildRequires: make
BuildRequires: ncurses-devel
BuildRequires: tar
BuildRequires: texinfo

Conflicts: filesystem < 3

Provides: /bin/sh
Provides: /bin/bash

%description
The GNU Bourne Again shell (Bash) is a shell or command language
interpreter that is compatible with the Bourne shell (sh). Bash
incorporates useful features from the Korn shell (ksh) and the C shell
(csh). Most sh scripts can be run by bash without modification.

%package        devel
Summary:        Header and development files for bash
Requires:       %{name} = %{version}

%description    devel
It contains the libraries and header files to create applications

%prep
cd /rpmbuild/BUILD
rm -rf bash-*
tar --no-same-owner -xzf %{SOURCE0}
%setup -q -T -c -D -n %{name}-%{baseversion}%{patchleveltag}

echo %{version} > _distribution
echo %{release} > _patchlevel

%build
%configure --with-bash-malloc=no --with-afs

# Recycles pids is neccessary. When bash's last fork's pid was X
# and new fork's pid is also X, bash has to wait for this same pid.
# Without Recycles pids bash will not wait.
make "CPPFLAGS=-D_GNU_SOURCE -DRECYCLES_PIDS -DDEFAULT_PATH_VALUE='\"/usr/local/bin:/usr/bin\"' `getconf LFS_CFLAGS` -DSYSLOG_HISTORY"

%install
%make_install


%files
%defattr(-,root,root)
%license COPYING
/usr/bin/*
%{_libdir}/%{name}/*
%{_defaultdocdir}/%{name}/*
%{_mandir}/*/*
%{_datadir}/info/*
%exclude %{_datadir}/info/dir
%{_datadir}/locale/

%files devel
%{_includedir}/%{name}/*
%{_libdir}/pkgconfig/*

%changelog
* Tue Jan 16 2024 Manuel Naranjo <manuel.naranjo@booking.com> - 5.2.21-2
- Added missing dependencies
- Making the build reproducible
* Fri Jan 05 2024 Manuel Naranjo <manuel.naranjo@booking.com> - 5.2.21-1
- Mocking for rules_rpmbuild
