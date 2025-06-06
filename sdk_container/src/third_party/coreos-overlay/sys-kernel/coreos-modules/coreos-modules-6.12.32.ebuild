# Copyright 2014-2016 CoreOS, Inc.
# Distributed under the terms of the GNU General Public License v2

EAPI=7
COREOS_SOURCE_REVISION=""
inherit coreos-kernel savedconfig

DESCRIPTION="CoreOS Linux kernel modules"
KEYWORDS="amd64 arm64"
RDEPEND="!<sys-kernel/coreos-kernel-4.6.3-r1"

src_prepare() {
	default
	restore_config build/.config
	if [[ ! -f build/.config ]]; then
		local archconfig="$(find_archconfig)"
		local commonconfig="$(find_commonconfig)"
		elog "Building using config ${archconfig} and ${commonconfig}"
		cat "${archconfig}" "${commonconfig}" | envsubst '$MODULE_SIGNING_KEY_DIR' >> build/.config || die
	fi
	cpio -ov </dev/null >build/bootengine.cpio

	# Check that an old pre-ebuild-split config didn't leak in.
	grep -q "^CONFIG_INITRAMFS_SOURCE=" build/.config && \
		die "CONFIG_INITRAMFS_SOURCE must be removed from kernel config"
	config_update 'CONFIG_INITRAMFS_SOURCE="bootengine.cpio"'
}

src_compile() {
	# Generate module signing key
	setup_keys

	# Build both vmlinux and modules (moddep checks symbols in vmlinux)
	kmake vmlinux modules
}

src_install() {
	# Install modules to /usr.
	# Install firmware to a temporary (bogus) location.
	# The linux-firmware package will be used instead.
	# Stripping must be done here, not portage, to preserve sigs.
	kmake INSTALL_MOD_PATH="${D}/usr" \
		  INSTALL_MOD_STRIP="--strip-debug" \
		  INSTALL_FW_PATH="${T}/fw" \
		  modules_install

	# Install to /usr/lib/debug with debug symbols intact
	kmake INSTALL_MOD_PATH="${D}/usr/lib/debug/usr" \
		  INSTALL_FW_PATH="${T}/fw" \
		  modules_install
	rm "${D}/usr/lib/debug/usr/lib/modules/${KV_FULL}/"modules.* || die
	rm "${D}/usr/lib/debug/usr/lib/modules/${KV_FULL}/build" || die

	# Clean up the build tree
	kmake clean

	# TODO: ensure that fixdep and kbuild tools shipped inside the image
	# are native (we previously shipped amd64 binaries on arm64).
	# Upstream has a new script from v6.12 that we might be able to use:
	# scripts/package/install-extmod-build
	kmake HOSTLD=$(tc-getLD) HOSTCC=$(tc-getCC) cmd_and_fixdep='$(cmd)' modules_prepare
	kmake clean

	find "build/" -type d -empty -delete || die
	rm "build/.config.old" || die

	# Install /lib/modules/${KV_FULL}/{build,source}
	install_build_source

	# Not strictly required but this is where we used to install the config.
	dodir "/usr/boot"
	local build="lib/modules/${KV_FULL}/build"
	dosym "../${build}/.config" "/usr/boot/config-${KV_FULL}"
	dosym "../${build}/.config" "/usr/boot/config"
}
