include $(TOPDIR)/rules.mk
PKG_NAME:=campuslink
PKG_VERSION:=0.4.0
PKG_RELEASE:=1
PKG_LICENSE:=MIT
include $(INCLUDE_DIR)/package.mk

define Package/campuslink
  SECTION:=net
  CATEGORY:=Network
  TITLE:=CampusLink campus authentication service
  DEPENDS:=+ucode +ucode-mod-fs +ucode-mod-ubus +ucode-mod-uloop +curl +ca-bundle
  PKGARCH:=all
endef

define Build/Compile
endef

define Package/campuslink/install
	$(CP) ./files/* $(1)/
	chmod 755 $(1)/etc/init.d/campuslink
endef

define Package/campuslink/postinst
#!/bin/sh
[ -n "$$$$IPKG_INSTROOT" ] || { /etc/init.d/campuslink enable; /etc/init.d/campuslink start; }
exit 0
endef

define Package/campuslink/prerm
#!/bin/sh
[ -n "$$$$IPKG_INSTROOT" ] || { /etc/init.d/campuslink stop; /etc/init.d/campuslink disable; }
exit 0
endef

$(eval $(call BuildPackage,campuslink))
