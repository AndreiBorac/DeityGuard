ARCH=x64
MODEL=d16
DEBUG_MODEL=n
BOOT_STYLE=chip
BOOT_ROM_KEEP_SEABIOS=y
BOOT_ROM_PENGUIN=n
ETH_HWADDR=""

STAGE0_MODULES_PLATFORM_SPECIFIC=(_)
STAGE1_MODULES_PLATFORM_SPECIFIC=(_)
STAGE1_MODULES_WITHOUT_AUTO_LOAD=(_)
STAGE3_MODULES_PLATFORM_SPECIFIC=(_)
STAGE3_MODULES_MODPROBE_FAIL_LAX=(_)

STAGE0_MODULES_PLATFORM_SPECIFIC+=({ehci,ohci,uhci}-hcd {ehci,ohci}-{pci,platform} ahci e1000e)
STAGE0_USB_NET=n
STAGE1_MODULES_PLATFORM_SPECIFIC+=(nouveau) # display
STAGE1_MODULES_PLATFORM_SPECIFIC+=(i8042 atkbd) # keyboard
STAGE1_MODULES_WITHOUT_AUTO_LOAD+=()
STAGE3_MODULES_PLATFORM_SPECIFIC+=("${STAGE0_MODULES_PLATFORM_SPECIFIC[@]:1}")
STAGE3_MODULES_PLATFORM_SPECIFIC+=("${STAGE1_MODULES_PLATFORM_SPECIFIC[@]:1}")
STAGE3_MODULES_PLATFORM_SPECIFIC+=()
STAGE3_MODULES_MODPROBE_FAIL_LAX+=()
STAGE3_USB_NET=n

#include model-common

FLASHPAGAN_STRATEGY=wrrd
FLASHPAGAN_SPI_SPEED_HZ=20000000