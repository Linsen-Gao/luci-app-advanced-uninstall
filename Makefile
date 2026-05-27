include $(TOPDIR)/rules.mk

PKG_NAME:=luci-app-advanced-uninstall
PKG_VERSION:=2.0.0
PKG_RELEASE:=1

PKG_MAINTAINER:=Your Name <your-email@example.com>
PKG_LICENSE:=Apache-2.0

include $(INCLUDE_DIR)/package.mk

define Package/$(PKG_NAME)
  SECTION:=luci
  CATEGORY:=LuCI
  TITLE:=LuCI Advanced Uninstall Manager
  DEPENDS:=+luci-base +rpcd
  PKGARCH:=all
  EXTRA_DEPENDS:=@(PACKAGE_opkg||PACKAGE_apk)
endef

define Package/$(PKG_NAME)/description
  LuCI interface for advanced package uninstall management with
  Docker container cleanup, dependency tracking, and more.
  
  Compatible with OpenWrt 23.05+ (opkg) and 25.xx+ (apk)
endef

define Build/Prepare
	mkdir -p $(PKG_BUILD_DIR)
	$(CP) ./src/* $(PKG_BUILD_DIR)/
endef

define Build/Compile
endef

define Package/$(PKG_NAME)/install
	$(INSTALL_DIR) $(1)/usr/lib/lua/luci/controller
	$(INSTALL_DATA) $(PKG_BUILD_DIR)/controller/uninstall.lua $(1)/usr/lib/lua/luci/controller/uninstall.lua
	
	$(INSTALL_DIR) $(1)/usr/lib/lua/luci/view/uninstall
	$(INSTALL_DATA) $(PKG_BUILD_DIR)/view/uninstall/main.htm $(1)/usr/lib/lua/luci/view/uninstall/main.htm
	
	$(INSTALL_DIR) $(1)/usr/share/rpcd/acl.d
	$(INSTALL_DATA) $(PKG_BUILD_DIR)/acl.d/luci-app-advanced-uninstall.json $(1)/usr/share/rpcd/acl.d/luci-app-advanced-uninstall.json
	
	$(INSTALL_DIR) $(1)/www/luci-static/resources/app-icons
	$(INSTALL_DATA) $(PKG_BUILD_DIR)/icons/*.png $(1)/www/luci-static/resources/app-icons/ 2>/dev/null || true
	$(INSTALL_DATA) $(PKG_BUILD_DIR)/icons/*.svg $(1)/www/luci-static/resources/app-icons/ 2>/dev/null || true
endef

define Package/$(PKG_NAME)/postinst
#!/bin/sh
[ -z "$${IPKG_INSTROOT}" ] && {
	/etc/init.d/rpcd restart
}
exit 0
endef

define Package/$(PKG_NAME)/prerm
#!/bin/sh
rm -rf /etc/luci-app-advanced-uninstall
exit 0
endef

$(eval $(call BuildPackage,$(PKG_NAME)))
