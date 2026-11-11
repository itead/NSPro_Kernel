# AIC8800 Bluetooth low-power module - in-tree Kbuild

obj-$(CONFIG_AIC8800_BTLPM_SUPPORT) += aic8800_btlpm.o

ccflags-y += -I$(srctree)/$(src)/../aic8800_bsp
ccflags-y += -DCONFIG_PLATFORM_ROCKCHIP -DANDROID_PLATFORM
ccflags-y += -DAIC_TRACE_INCLUDE_PATH=$(src)

aic8800_btlpm-y := \
	aic_bluetooth_main.o \
	rfkill.o \
	lpm.o
