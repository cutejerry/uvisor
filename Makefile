###########################################################################
#
#  Copyright (c) 2013-2015, ARM Limited, All Rights Reserved
#  SPDX-License-Identifier: Apache-2.0
#
#  Licensed under the Apache License, Version 2.0 (the "License"); you may
#  not use this file except in compliance with the License.
#  You may obtain a copy of the License at
#
#  http://www.apache.org/licenses/LICENSE-2.0
#
#  Unless required by applicable law or agreed to in writing, software
#  distributed under the License is distributed on an "AS IS" BASIS, WITHOUT
#  WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
#  See the License for the specific language governing permissions and
#  limitations under the License.
#
###########################################################################
PREFIX:=arm-none-eabi-
CC:=$(PREFIX)gcc
CXX:=$(PREFIX)g++
OBJCOPY:=$(PREFIX)objcopy
OBJDUMP:=$(PREFIX)objdump

SYSLIBS:=-lgcc -lc -lnosys

# Suffix for the exported binary blob
BINARY_NAME:=$(shell echo $(CONFIGURATION) | tr '[:upper:]' '[:lower:]')

# Root (relative to hardware-specific Makefile)
ROOT_DIR:=../..

# Top-level folder paths
CORE_DIR:=$(ROOT_DIR)/core
PLATFORM_DIR:=$(ROOT_DIR)/platform
RELEASE_DIR:=$(ROOT_DIR)/release
TOOLS_DIR:=$(ROOT_DIR)/tools

# Core paths
CMSIS_DIR:=$(CORE_DIR)/cmsis
SYSTEM_DIR:=$(CORE_DIR)/system
MBED_DIR:=$(CORE_DIR)/mbed
DEBUG_DIR:=$(CORE_DIR)/debug
LIB_DIR:=$(CORE_DIR)/lib

# mbed origin paths
MBED_SRC:=$(MBED_DIR)/source
MBED_SRC_HW:=$(MBED_SRC)/$(PROJECT)
MBED_INC:=$(MBED_DIR)/uvisor-lib
MBED_ASM_INPUT:=$(MBED_SRC)/uvisor-input.S
MBED_ASM_HEADER:=$(MBED_SRC)/uvisor-header.S
MBED_ASM:=$(MBED_SRC_HW)/uvisor_$(BINARY_NAME).s
MBED_BIN_NAME:=uvisor_$(BINARY_NAME).box
MBED_BIN:=$(MBED_SRC_HW)/$(MBED_BIN_NAME)
MBED_CONFIG:=$(PLATFORM_DIR)/$(PROJECT)/mbed/get_configuration.cmake

# mbed release paths
RELEASE_SRC:=$(RELEASE_DIR)/source
RELEASE_SRC_HW:=$(RELEASE_SRC)/$(PROJECT)
RELEASE_INC:=$(RELEASE_DIR)/uvisor-lib
RELEASE_OBJ:=$(RELEASE_SRC_HW)/uvisor_$(BINARY_NAME).o
RELEASE_VER:=$(RELEASE_SRC_HW)/version.txt

# make ARMv7-M MPU driver the default
ifeq ("$(ARCH_MPU)","")
ARCH_MPU:=ARMv7M
endif

# ARMv7-M MPU driver
ifeq ("$(ARCH_MPU)","ARMv7M")
MPU_SRC:=\
         $(SYSTEM_DIR)/src/mpu/vmpu_armv7m.c \
         $(SYSTEM_DIR)/src/mpu/vmpu_armv7m_debug.c
endif

# Freescale K64 MPU driver
ifeq ("$(ARCH_MPU)","KINETIS")
MPU_SRC:=\
         $(SYSTEM_DIR)/src/mpu/vmpu_freescale_k64.c \
         $(SYSTEM_DIR)/src/mpu/vmpu_freescale_k64_debug.c \
         $(SYSTEM_DIR)/src/mpu/vmpu_freescale_k64_aips.c \
         $(SYSTEM_DIR)/src/mpu/vmpu_freescale_k64_mem.c
endif

SOURCES:=\
         $(SYSTEM_DIR)/src/benchmark.c \
         $(SYSTEM_DIR)/src/halt.c \
         $(SYSTEM_DIR)/src/main.c \
         $(SYSTEM_DIR)/src/stdlib.c \
         $(SYSTEM_DIR)/src/svc.c \
         $(SYSTEM_DIR)/src/svc_cx.c \
         $(SYSTEM_DIR)/src/unvic.c \
         $(SYSTEM_DIR)/src/system.c \
         $(SYSTEM_DIR)/src/mpu/vmpu.c \
         $(DEBUG_DIR)/src/debug.c \
         $(DEBUG_DIR)/src/memory_map.c \
         $(LIB_DIR)/printf/tfp_printf.c \
         $(MPU_SRC) \
         $(APP_SRC)

OPT:=-Os -DNDEBUG
DEBUG:=-g3
WARNING:=-Wall -Werror

# determine repository version
PROGRAM_VERSION:=$(shell git describe --tags --abbrev=4 --dirty 2>/dev/null | sed s/^v//)
ifeq ("$(PROGRAM_VERSION)","")
         PROGRAM_VERSION:='unknown'
endif

# Read UVISOR_{FLASH, SRAM}_LENGTH from uvisor-config.h.
ifeq ("$(wildcard  $(CORE_DIR)/uvisor-config.h)","")
	UVISOR_MAGIC:=0
	UVISOR_FLASH_LENGTH:=0
	UVISOR_SRAM_LENGTH:=0
else
	UVISOR_MAGIC:=$(shell grep UVISOR_MAGIC $(CORE_DIR)/uvisor-config.h | sed -E 's/^.* (0x[0-9A-Fa-f]+).*$\/\1/')
	UVISOR_FLASH_LENGTH:=$(shell grep UVISOR_FLASH_LENGTH $(CORE_DIR)/uvisor-config.h | sed -E 's/^.* (0x[0-9A-Fa-f]+).*$\/\1/')
	UVISOR_SRAM_LENGTH:=$(shell grep UVISOR_SRAM_LENGTH $(CORE_DIR)/uvisor-config.h | sed -E 's/^.* (0x[0-9A-Fa-f]+).*$\/\1/')
endif

FLAGS_CM4:=-mcpu=cortex-m4 -march=armv7e-m -mthumb

LDFLAGS:=\
        $(FLAGS_CM4) \
        -T$(PROJECT).linker \
        -nostartfiles \
        -nostdlib \
        -Xlinker --gc-sections \
        -Xlinker -M \
        -Xlinker -Map=$(PROJECT).map

CFLAGS_PRE:=\
        $(OPT) \
        $(DEBUG) \
        $(WARNING) \
        -DARCH_MPU_$(ARCH_MPU) \
        -D$(CONFIGURATION) \
        -DPROGRAM_VERSION=\"$(PROGRAM_VERSION)\" \
        $(APP_CFLAGS) \
        -I$(CORE_DIR) \
        -I$(CMSIS_DIR)/inc \
        -I$(SYSTEM_DIR)/inc \
        -I$(SYSTEM_DIR)/inc/mpu \
        -I$(DEBUG_DIR)/inc \
        -I$(LIB_DIR)/printf \
        -ffunction-sections \
        -fdata-sections

CFLAGS:=$(FLAGS_CM4) $(CFLAGS_PRE)
CPPFLAGS:=-fno-exceptions

OBJS:=$(SOURCES:.cpp=.o)
OBJS:=$(OBJS:.c=.o)

LINKER_CONFIG:=\
    -D$(CONFIGURATION) \
    -DUVISOR_FLASH_LENGTH=$(UVISOR_FLASH_LENGTH) \
    -DUVISOR_SRAM_LENGTH=$(UVISOR_SRAM_LENGTH) \
    -include $(PLATFORM_DIR)/$(PROJECT)/inc/config.h

BINARY_CONFIG:=\
    -DUVISOR_FLASH_LENGTH=$(UVISOR_FLASH_LENGTH) \
    -DUVISOR_SRAM_LENGTH=$(UVISOR_SRAM_LENGTH) \
    -DUVISOR_MAGIC=$(UVISOR_MAGIC) \
    -DRELEASE_BIN=\"$(MBED_BIN)\"

.PHONY: debug gdb gdbtui flash erase reset ctags source.c.tags swo

include $(CORE_DIR)/Makefile.scripts

all: $(PROJECT).bin

CONFIGURATION_%:
	CONFIGURATION=$@ make -f ../../core/Makefile.rules mbed

release:
	make clean $(CONFIGURATIONS)

debug:
	make OPT= clean $(CONFIGURATIONS)

$(PROJECT).elf: $(OBJS) $(PROJECT).linker
	$(CC) $(LDFLAGS) -o $@ $(OBJS) $(SYSLIBS)
	$(OBJDUMP) -d $@ > $(PROJECT).asm

$(PROJECT).bin: $(PROJECT).elf
	$(OBJCOPY) $< -O binary $@

$(PROJECT).linker: $(CORE_DIR)/linker/default.h
	$(CPP) -w -P $(LINKER_CONFIG) $^ -o $@

mbed: $(MBED_ASM_INPUT) $(PROJECT).bin
	rm  -f $(RELEASE_INC)/*.h
	rm  -f $(RELEASE_SRC)/*.cpp
	rm -f $(RELEASE_OBJ) $(RELEASE_VER)
	mkdir -p $(MBED_SRC_HW)
	mkdir -p $(RELEASE_INC)
	mkdir -p $(RELEASE_SRC_HW)
	echo "$(PROGRAM_VERSION)" > $(RELEASE_VER)
	cp $(PROJECT).bin $(MBED_BIN)
	cp $(MBED_INC)/*.h   $(RELEASE_INC)/
	cp $(MBED_SRC)/*.cpp $(RELEASE_SRC)/
	find ../.. -name "*_exports.h" -not -path "$(RELEASE_DIR)/*"\
	     -exec cp {} $(RELEASE_INC)/ \;
	cp -f $(MBED_ASM_HEADER) $(MBED_ASM)
	cp $(MBED_CONFIG) $(RELEASE_SRC_HW)/
	$(CPP) -w -P $(BINARY_CONFIG) $< > $(MBED_ASM)
	$(CC) $(CFLAGS) $(CPPFLAGS) -c -o $(RELEASE_OBJ) $(MBED_ASM)

clean:
	rm -f $(PROJECT).map $(PROJECT).elf $(PROJECT).bin $(PROJECT).asm\
	      $(PROJECT).linker source.c.tags \
	      $(RELEASE_ASM) $(RELEASE_SRC_HW)/*
	      $(APP_CLEAN)
	find . $(CORE_DIR) -iname '*.o' -exec rm -f \{\} \;
