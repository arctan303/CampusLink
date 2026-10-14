include $(TOPDIR)/rules.mk
PKG_NAME:=campuslink-mwan3
PKG_VERSION:=0.2.0
PKG_RELEASE:=1
PKG_LICENSE:=MIT
include $(INCLUDE_DIR)/package.mk

define Package/campuslink-mwan3
  SECTION:=net
  CATEGORY:=Network
  TITLE:=CampusLink integration for mwan3-nft
  DEPENDS:=+campuslink +mwan3-nft +rpcd +ucode-mod-fs +ucode-mod-ubus +ucode-mod-uci +ucode-mod-uloop
  PKGARCH:=all
endef

define Package/campuslink-mwan3/conffiles
/etc/campuslink-mwan3/config.json
endef

define Build/Compile
endef

define Package/campuslink-mwan3/install
	$(CP) ./files/* $(1)/
	chmod 755 $(1)/etc/init.d/campuslink-mwan3
	chmod 755 $(1)/etc/hotplug.d/iface/24-campuslink-mwan3
	chmod 755 $(1)/usr/share/campuslink-mwan3/apply.sh
	chmod 755 $(1)/usr/share/campuslink-mwan3/apply-mapping.sh
	chmod 755 $(1)/usr/share/campuslink-mwan3/events.sh
endef

define Package/campuslink-mwan3/prerm
#!/bin/sh
[ -n "$$$$IPKG_INSTROOT" ] || { /etc/init.d/campuslink-mwan3 stop; /etc/init.d/campuslink-mwan3 disable; }
exit 0
endef

$(eval $(call BuildPackage,campuslink-mwan3))
