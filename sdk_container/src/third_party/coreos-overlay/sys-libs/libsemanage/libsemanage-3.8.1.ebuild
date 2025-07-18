# Copyright 1999-2025 Gentoo Authors
# Distributed under the terms of the GNU General Public License v2

EAPI="8"
PYTHON_COMPAT=( python3_{10..13} )

inherit python-r1 toolchain-funcs multilib-minimal

MY_PV="${PV//_/-}"
MY_P="${PN}-${MY_PV}"

DESCRIPTION="SELinux kernel and policy management library"
HOMEPAGE="https://github.com/SELinuxProject/selinux/wiki"

if [[ ${PV} == 9999 ]]; then
	inherit git-r3
	EGIT_REPO_URI="https://github.com/SELinuxProject/selinux.git"
	S="${WORKDIR}/${P}/${PN}"
else
	SRC_URI="https://github.com/SELinuxProject/selinux/releases/download/${MY_PV}/${MY_P}.tar.gz"
	KEYWORDS="amd64 arm arm64 ~mips ~riscv x86"
	S="${WORKDIR}/${MY_P}"
fi

LICENSE="GPL-2"
SLOT="0/2"
IUSE="+python"
REQUIRED_USE="python? ( ${PYTHON_REQUIRED_USE} )"

RDEPEND="
	app-arch/bzip2[${MULTILIB_USEDEP}]
	>=sys-libs/libsepol-${PV}:=[${MULTILIB_USEDEP}]
	>=sys-libs/libselinux-${PV}:=[${MULTILIB_USEDEP}]
	>=sys-process/audit-2.2.2[${MULTILIB_USEDEP}]
	python? ( ${PYTHON_DEPS} )
"
DEPEND="${RDEPEND}"
BDEPEND="
	app-alternatives/yacc
	app-alternatives/lex
	python? (
		>=dev-lang/swig-2.0.4-r1
		virtual/pkgconfig
	)
"

# tests are not meant to be run outside of the
# full SELinux userland repo
RESTRICT="test"

PATCHES=(
    "${FILESDIR}/libsemanage-extra-config.patch"
)

src_prepare() {
	default
	multilib_copy_sources
}

multilib_src_compile() {
	local -x CFLAGS="${CFLAGS} -fno-semantic-interposition"

	emake \
		AR="$(tc-getAR)" \
		CC="$(tc-getCC)" \
		LIBDIR="${EPREFIX}/usr/$(get_libdir)" \
		all

	if use python && multilib_is_native_abi; then
		building_py() {
			emake \
				AR="$(tc-getAR)" \
				CC="$(tc-getCC)" \
				PKG_CONFIG="$(tc-getPKG_CONFIG)" \
				LIBDIR="${EPREFIX}/usr/$(get_libdir)" \
				"$@"
		}
		python_foreach_impl building_py swigify
		python_foreach_impl building_py pywrap
	fi
}

multilib_src_install() {
	emake \
		LIBDIR="${EPREFIX}/usr/$(get_libdir)" \
		DESTDIR="${ED}" install

	if use python && multilib_is_native_abi; then
		installation_py() {
			emake DESTDIR="${ED}" \
				LIBDIR="${EPREFIX}/usr/$(get_libdir)" \
				PKG_CONFIG="$(tc-getPKG_CONFIG)" \
				install-pywrap
			python_optimize # bug 531638
		}
		python_foreach_impl installation_py
	fi
}

multiib_src_install_all() {
	if use python; then
		python_setup
		python_fix_shebang "${ED}"/usr/libexec/selinux/semanage_migrate_store
	fi
}
