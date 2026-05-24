APP              := mxcore
$(APP)_BUILD_DIR := $(SN_ROOT)/sw/kernels/$(APP)/build
SRCS             := $(SN_ROOT)/sw/kernels/$(APP)/src/$(APP).c
$(APP)_INCDIRS   := $(SN_ROOT)/sw/kernels/$(APP)/data

include $(SN_ROOT)/sw/kernels/common.mk