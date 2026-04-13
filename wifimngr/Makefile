include $(TOPDIR)/rules.mk

PKG_NAME:=wifimngr
PKG_VERSION:=1.0
PKG_RELEASE:=1
PKG_LICENSE:=GPL-2.0

PKG_MAINTAINER:=Janusz Dziedzic <janusz.dziedzic@gmail.com>

include $(INCLUDE_DIR)/package.mk

define Package/wifimngr
  SECTION:=net
  CATEGORY:=Network
  TITLE:=WiFi Manager daemon
  DEPENDS:=+ucode +ucode-mod-nl80211 +ucode-mod-ubus +ucode-mod-uci +ucode-mod-uloop +ucode-mod-fs +hostapd-utils +wpa-cli
  PKGARCH:=all
endef

define Package/wifimngr/description
  A ucode-based WiFi manager daemon providing ubus APIs for radio and
  interface management, including capabilities reporting, channel survey,
  scan, and operating class preferences.
endef

define Build/Prepare
endef

define Build/Configure
endef

define Build/Compile
endef

define Package/wifimngr/install
	$(INSTALL_DIR) $(1)/usr/share/wifimngr
	$(INSTALL_DATA) ./wifimngr.uc $(1)/usr/share/wifimngr/
	$(INSTALL_DATA) ./wifi_device.uc $(1)/usr/share/wifimngr/
	$(INSTALL_DATA) ./wifi_iface.uc $(1)/usr/share/wifimngr/
	$(INSTALL_DATA) ./wifi_opclass.uc $(1)/usr/share/wifimngr/
	$(INSTALL_DATA) ./hostapd_cli.uc $(1)/usr/share/wifimngr/
	$(INSTALL_DIR) $(1)/etc/init.d
	$(INSTALL_BIN) ./files/wifimngr.init $(1)/etc/init.d/wifimngr
endef

$(eval $(call BuildPackage,wifimngr))
