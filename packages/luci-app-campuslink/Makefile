include $(TOPDIR)/rules.mk
LUCI_TITLE:=CampusLink campus authentication
LUCI_DEPENDS:=+campuslink +luci-base +rpcd +busybox
LUCI_PKGARCH:=all
PKG_VERSION:=0.4.2
PKG_RELEASE:=1
PKG_LICENSE:=MIT
define Build/Prepare/luci-app-campuslink
	chmod 755 $(PKG_BUILD_DIR)/root/usr/libexec/rpcd/campuslink.diagnostics
endef
define Package/luci-app-campuslink/postinst
#!/bin/sh
[ -n "$${IPKG_INSTROOT}" ] || { rm -f /tmp/luci-indexcache; /etc/init.d/rpcd reload; ubus list campuslink.diagnostics | grep -qx campuslink.diagnostics || /etc/init.d/rpcd restart; }
exit 0
endef
define Package/luci-app-campuslink/postrm
#!/bin/sh
[ -n "$${IPKG_INSTROOT}" ] || { rm -f /tmp/luci-indexcache; /etc/init.d/rpcd restart; }
exit 0
endef
include $(TOPDIR)/feeds/luci/luci.mk
