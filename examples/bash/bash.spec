%define patchleveltag .21
%define baseversion 5.2
%bcond_without tests

Version: %{baseversion}%{patchleveltag}
Name: bash
Summary: The GNU Bourne Again shell
Release: 1%{?dist}
Group: System Environment/Shells
License: GPLv3+
Url: http://www.gnu.org/software/bash
Source0: bash.tar.gz


BuildRequires: texinfo bison
BuildRequires: ncurses-devel
BuildRequires: autoconf
BuildRequires: gettext
BuildRequires: gcc
BuildRequires: gcc-c++
BuildRequires: make

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
#cd %{name}-%{baseversion}%{patchleveltag}
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
%{_datadir}/info/
%{_datadir}/locale/

%files devel
%{_includedir}/%{name}/*
%{_libdir}/pkgconfig/*

%changelog
* Fri Jan 05 2024 Manuel Naranjo <manuel.naranjo@booking.com> - 5.2.21-1
- Mocking for rules_rpmbuild
