# MeshMusic — Spotify-artiger Musik-Player für iPod touch 4 (iOS 6.1, ARMv7), Theos.
TARGET = iphone:clang:7.1:6.0
ARCHS  = armv7

include $(THEOS)/makefiles/common.mk

APPLICATION_NAME = MeshMusic

MeshMusic_FILES  = $(wildcard music/App/*.m) $(wildcard music/UI/*.m) $(wildcard music/Spot/*.m) $(wildcard music/Spot/*.c)
MeshMusic_FRAMEWORKS = UIKit CoreGraphics Foundation QuartzCore AVFoundation AudioToolbox Security MediaPlayer SystemConfiguration
MeshMusic_CFLAGS  = -fobjc-arc -O2 -Wall
MeshMusic_CFLAGS += -Imusic/App -Imusic/UI -Imusic/Spot -Ivendor/mbedtls/include -Ivendor/stb
MeshMusic_LDFLAGS  = -Lvendor/mbedtls/lib -ObjC
MeshMusic_LIBRARIES = mbedtls mbedx509 mbedcrypto
MeshMusic_CODESIGN_FLAGS = -S$(THEOS_PROJECT_DIR)/ent.plist   # darf andere Apps starten (Reboot öffnen)

include $(THEOS_MAKE_PATH)/application.mk
