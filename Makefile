include Version.mk
include Env.mk

ARCH := $(shell $(CC) -dumpmachine | cut -f1 -d- | sed s,i[3456789]86,i386,)

ifeq ($(ARCH),x86_64)
	EFI_ARCH := X64
else ifeq ($(ARCH),i386)
	EFI_ARCH := IA32
else
	$(error Unsupported ARCH $(ARCH))
endif

TOPDIR := $(shell pwd)
EDK2_TOPDIR ?= $(TOPDIR)/edk2

EDK2_PKG_LIBS_MdePkg := \
	BaseLib \
	BasePrintLib \
	BaseMemoryLib \
	UefiMemoryAllocationLib \
	UefiRuntimeServicesTableLib \
	UefiBootServicesTableLib \
	UefiLib

# These libraries cannot be built directly.
EDK2_EXTRA_PKG_LIBS_MdePkg := \
	UefiFileHandleLib

define BUILD_EDK2_PKG
	build -q -s -a $(EFI_ARCH) -b RELEASE -t GCC5 \
	    -DSECURE_BOOT_ENABLE=TRUE -p \"$(1)/$(1).dsc\"; \
	if [ \$$? -ne 0 ]; then \
	    echo \"Failed to build $(1)\"; \
	    exit 1; \
	fi
endef

define BUILD_EDK2_PKG_LIBS
	for lib in $(EDK2_PKG_LIBS_$(1)); do \
	    build -q -s -a $(EFI_ARCH) -b RELEASE -t GCC5 \
		-DSECURE_BOOT_ENABLE=TRUE -p \"$(1)/$(1).dsc\" \
		-m \"$(1)/Library/\$$lib/\$$lib.inf\"; \
	    if [ \$$? -ne 0 ]; then \
		echo \"Failed to build $(1):\$$lib\"; \
		exit 1; \
	    fi; \
	done
endef

define INSTALL_EDK2_LIBS
	$(shell \
	    for lib in $(EDK2_PKG_LIBS_$(1)) $(EDK2_EXTRA_PKG_LIBS_$(1)); do \
		if [ x\"$(1)\" = x\"MdePkg\" ]; then \
		    name=\"Mde"; \
		else \
		    name=\"$(1)\"; \
		fi; \
		echo \"$(EDK2_TOPDIR)/Build/\$$name/RELEASE_GCC5/$(EFI_ARCH)/$(1)/Library/\$$lib/\$$lib/OUTPUT/\$$lib.lib\"; \
	    done; \
	)
endef

.DEFAULT_GOAL := all
.PHONE: all clean install tag patch_openssl build_basetools

all: Makefile patch_openssl build_basetools build

clean:
	@echo "Cleaning edk2 ..."; \
	cd $(EDK2_TOPDIR); \
	bash -c "source ./edksetup.sh; \
		 build clean; \
		"

install: Makefile $(call INSTALL_EDK2_LIBS,MdePkg)
	@$(INSTALL) -d -m 755 "$(DESTDIR)$(libdir)/edk2"
	@$(foreach x, $(call INSTALL_EDK2_LIBS,MdePkg), $(INSTALL) -m 755 "$(x)" \
	    "$(DESTDIR)$(libdir)/edk2/lib`basename $(patsubst %.lib,%,$(x))`.a";)
	@$(INSTALL) -d -m 755 "$(DESTDIR)$(includedir)/edk2"
	@cp -a "$(EDK2_TOPDIR)"/MdePkg/Include/* "$(DESTDIR)$(includedir)/edk2"

tag:
	@$(GIT) tag -a "$(LIBEDK2_VERSION)" -m "$(LIBEDK2_VERSION)" refs/heads/master

patch_openssl:
	@echo "Checking openssl ..."; \
	cd "$(EDK2_TOPDIR)/CryptoPkg/Library/OpensslLib"; \
	pattern='openssl-[[:digit:]]\.[[:digit:]]\{1,2\}\.[[:digit:]]\{1,2\}[a-z]\?'; \
	link=`grep -m 1 "^\s*http://www\.openssl\.org/source/$$pattern\.tar\.gz\s$$" \
	    Patch-HOWTO.txt | grep -o "http.*\.tar\.gz"`; \
	basename=`echo $$link | grep -o "$$pattern"`; \
	[ x"$$basename" = x"" ] && { echo "Failed to find out openssl pattern"; exit 1; }; \
	echo "$$basename used"; \
	[ ! -d "$$basename" ] && { \
	    [ ! -s "$$basename.tar.gz" ] && { \
	        echo "Downloading $$basename ..."; \
	        wget "$$link" || { echo "Failed to download $$basename"; exit 1; }; \
	    }; \
	    echo "Extracting $$basename ..."; \
	    tar xzf "$$basename.tar.gz" || { echo "Failed to extract $$basename"; exit 1; }; \
	    echo "Patching $$basename ..."; \
	    cd "$$basename"; \
	    patch -p1 -i "../EDKII_$$basename.patch" || { \
	        echo "Failed to patch $$basename"; exit 1; \
	    }; \
	    cd ..; \
	    echo "Installing $$basename ..."; \
	    bash -c ./Install.sh || { echo "Failed to install $$basename"; exit 1; }; \
	}; \
        echo "$$basename applied"

build_basetools:
	@echo "Building BaseTools ..."; \
	cd "$(EDK2_TOPDIR)"; \
	$(MAKE) -C BaseTools/Source/C || { echo "Failed to build BaseTools"; exit 1; }

build:
	@echo "Building edk2 ..."; \
	cd $(EDK2_TOPDIR); \
	bash -c "source ./edksetup.sh; \
		 $(call BUILD_EDK2_PKG_LIBS,MdePkg); \
		 $(call BUILD_EDK2_PKG,ShellPkg); \
		 $(call BUILD_EDK2_PKG,SecurityPkg); \
		"
