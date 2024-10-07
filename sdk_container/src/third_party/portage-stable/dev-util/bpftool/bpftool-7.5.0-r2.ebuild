# Copyright 2021-2024 Gentoo Authors
# Distributed under the terms of the GNU General Public License v2

EAPI=8

LLVM_COMPAT=( {15..19} )
LLVM_OPTIONAL=1
PYTHON_COMPAT=( python3_{10..13} )

inherit bash-completion-r1 estack linux-info llvm-r1 optfeature python-any-r1 toolchain-funcs

DESCRIPTION="Tool for inspection and simple manipulation of eBPF programs and maps"
HOMEPAGE="https://kernel.org/"

# Use LINUX_VERSION to specify the full kernel version triple (x.y.z)
LINUX_VERSION=6.11.2
LINUX_VER=$(ver_cut 1-2 ${LINUX_VERSION})
LINUX_V="${LINUX_VERSION:0:1}.x"

LINUX_SOURCES="linux-${LINUX_VER}.tar.xz"
SRC_URI="https://www.kernel.org/pub/linux/kernel/v${LINUX_V}/${LINUX_SOURCES}"

if [[ ${LINUX_VERSION} == *.*.* ]] ; then
	LINUX_PATCH="patch-${LINUX_VERSION}.xz"
	SRC_URI+=" https://www.kernel.org/pub/linux/kernel/v${LINUX_V}/${LINUX_PATCH}"
fi

S_K="${WORKDIR}/linux-${LINUX_VER}"
S="${S_K}/tools/bpf/bpftool"

LICENSE="GPL-2"
SLOT="0"
KEYWORDS="~amd64 ~arm ~arm64 ~loong ~ppc ~ppc64 ~riscv ~x86"
IUSE="caps llvm"

RDEPEND="
	sys-libs/zlib:=
	virtual/libelf:=
	caps? ( sys-libs/libcap:= )
	llvm? ( $(llvm_gen_dep 'sys-devel/llvm:${LLVM_SLOT}') )
	!llvm? ( sys-libs/binutils-libs:= )
"
DEPEND="
	${RDEPEND}
	>=sys-kernel/linux-headers-5.8
"
BDEPEND="
	${LINUX_PATCH+dev-util/patchutils}
	${PYTHON_DEPS}
	app-arch/tar
	dev-python/docutils
"

CONFIG_CHECK="~DEBUG_INFO_BTF"

pkg_setup() {
	python-any-r1_pkg_setup
	use llvm && llvm-r1_pkg_setup
}

# src_unpack and src_prepare are copied from dev-util/perf since
# it's building from the same tarball, please keep it in sync with perf
src_unpack() {
	local paths=(
		'arch/*/include/*' 'arch/*/lib/*' 'arch/*/tools/*' 'include/*'
		'kernel/bpf/*' 'lib/*' 'scripts/*' 'tools/arch/*' 'tools/bpf/*'
		'tools/build/*' 'tools/include/*' 'tools/lib/*' 'tools/perf/*'
		'tools/scripts/*'
	)

	# We expect the tar implementation to support the -j and --wildcards option
	echo ">>> Unpacking ${LINUX_SOURCES} (${paths[*]}) to ${PWD}"
	gtar --wildcards -xpf "${DISTDIR}"/${LINUX_SOURCES} \
		"${paths[@]/#/linux-${LINUX_VER}/}" || die

	if [[ -n ${LINUX_PATCH} ]] ; then
		eshopts_push -o noglob
		ebegin "Filtering partial source patch"
		xzcat "${DISTDIR}"/${LINUX_PATCH} | filterdiff -p1 ${paths[@]/#/-i} > ${P}.patch
		assert -n "Unpacking to ${P} from ${DISTDIR}/${LINUX_PATCH} failed"
		eend $? || die "filterdiff failed"
		test -s ${P}.patch || die "patch is empty?!"
		eshopts_pop
	fi

	local a
	for a in ${A}; do
		[[ ${a} == ${LINUX_SOURCES} ]] && continue
		[[ ${a} == ${LINUX_PATCH} ]] && continue
		unpack ${a}
	done
}

src_prepare() {
	default

	if [[ -n ${LINUX_PATCH} ]] ; then
		pushd "${S_K}" >/dev/null || die
		eapply "${WORKDIR}"/${P}.patch
		popd || die
	fi

	# Use rst2man or rst2man.py depending on which one exists (#930076)
	type -P rst2man >/dev/null || sed -i -e 's/rst2man/rst2man.py/g' Documentation/Makefile || die

	# remove -Werror (bug 887981)
	sed -i -e 's/\-Werror//g' ../../lib/bpf/Makefile || die

	# fix up python shebangs (bug 940781)
	python_fix_shebang "${S_K}"/scripts/bpf_doc.py
}

bpftool_make() {
	local arch=$(tc-arch-kernel)
	tc-export AR CC LD

	emake V=1 VF=1 \
		HOSTCC="$(tc-getBUILD_CC)" HOSTLD="$(tc-getBUILD_LD)" \
		EXTRA_CFLAGS="${CFLAGS}" ARCH="${arch}" \
		prefix="${EPREFIX}"/usr \
		bash_compdir="$(get_bashcompdir)" \
		feature-libcap="$(usex caps 1 0)" \
		feature-llvm="$(usex llvm 1 0)" \
		"$@"
}

src_compile() {
	bpftool_make
	bpftool_make -C Documentation
}

src_install() {
	bpftool_make DESTDIR="${D}" install
	bpftool_make mandir="${ED}"/usr/share/man -C Documentation install
}

pkg_postinst() {
	optfeature "clang-bpf-co-re support" sys-devel/clang[llvm_targets_BPF]
}
