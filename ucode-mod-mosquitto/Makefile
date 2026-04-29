#
# Copyright (C) 2026 Janusz Dziedzic
#
# This is free software, licensed under the GNU General Public License v2.
#

include $(TOPDIR)/rules.mk

PKG_NAME:=ucode-mod-mosquitto
PKG_VERSION:=1
PKG_RELEASE:=1

PKG_MAINTAINER:=Janusz Dziedzic <janusz.dziedzic@gmail.com>
PKG_LICENSE:=ISC

PKG_BUILD_DIR:=$(BUILD_DIR)/$(PKG_NAME)-$(PKG_VERSION)

include $(INCLUDE_DIR)/package.mk

define Package/ucode-mod-mosquitto
  SUBMENU:=ucode
  SECTION:=lang
  CATEGORY:=Languages
  TITLE:=ucode MQTT client module (libmosquitto)
  DEPENDS:=+libucode +libmosquitto-ssl +libubox +ucode
endef

define Package/ucode-mod-mosquitto/description
  Native ucode C module wrapping libmosquitto with uloop integration.
  Provides full MQTT v3.1.1 client support including TLS (via libmosquitto-ssl),
  QoS 0/1/2, will messages, authentication and automatic reconnect.
endef

define Build/Prepare
	mkdir -p $(PKG_BUILD_DIR)
	$(CP) ./src/mosquitto.c $(PKG_BUILD_DIR)/
endef

define Build/Compile
	$(TARGET_CC) $(TARGET_CFLAGS) $(TARGET_LDFLAGS) \
		-fPIC -shared \
		-I$(STAGING_DIR)/usr/include/ucode \
		-I$(STAGING_DIR)/usr/include \
		-o $(PKG_BUILD_DIR)/mosquitto.so \
		$(PKG_BUILD_DIR)/mosquitto.c \
		-lmosquitto -lubox
endef

define Package/ucode-mod-mosquitto/install
	$(INSTALL_DIR) $(1)/usr/lib/ucode
	$(INSTALL_BIN) $(PKG_BUILD_DIR)/mosquitto.so $(1)/usr/lib/ucode/
endef

$(eval $(call BuildPackage,ucode-mod-mosquitto))
