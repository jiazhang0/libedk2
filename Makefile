include Version.mk
include Env.mk

ARCH := $(shell $(CC) -dumpmachine | cut -f1 -d- | sed s,i[3456789]86,i386,)

ifeq ($(ARCH),x86_64)
	EFI_ARCH = X64
else ifeq ($(ARCH),i386)
	EFI_ARCH = IA32
else
    $(error Unsupported ARCH $(ARCH) specified)
endif

TOPDIR := $(shell pwd)
EDK2_TOPDIR := $(TOPDIR)/edk2
EDK2_TARGET_PKG := SecurityPkg

define EDK2_LIB
	$(EDK2_TOPDIR)/Build/$(EDK2_TARGET_PKG)/RELEASE_GCC5/$(EFI_ARCH)/$(1)/Library/$(2)/$(2)/OUTPUT/$(2).lib
endef

SUBLIBS := \
	$(call EDK2_LIB,MdePkg,BaseLib) \
	$(call EDK2_LIB,MdePkg,BasePrintLib) \
	$(call EDK2_LIB,MdePkg,BaseMemoryLib) \
	$(call EDK2_LIB,MdePkg,UefiDevicePathLib) \
	$(call EDK2_LIB,MdePkg,UefiMemoryAllocationLib) \
	$(call EDK2_LIB,MdePkg,UefiRuntimeServicesTableLib) \
	$(call EDK2_LIB,MdePkg,UefiBootServicesTableLib) \
	$(call EDK2_LIB,MdePkg,UefiLib) \
	$(call EDK2_LIB,MdeModulePkg,FileExplorerLib)

.DEFAULT_GOAL := all
.PHONE: all clean install tag patch_openssl config build_basetools

all: Makefile patch_openssl config build_basetools build

patch_openssl:
	@echo "Checking openssl ..."; \
	cd $(EDK2_TOPDIR)/CryptoPkg/Library/OpensslLib; \
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
	    patch -p1 -i ../EDKII_$$basename.patch || { \
	        echo "Failed to patch $$basename"; exit 1; \
	    }; \
	    cd ..; \
	    echo "Installing $$basename ..."; \
	    bash -c ./Install.sh || { echo "Failed to install $$basename"; exit 1; }; \
	}; \
        echo "$$basename applied"

build_basetools:
	echo "Building BaseTools ..."; \
	cd $(EDK2_TOPDIR); \
	$(MAKE) -C BaseTools/Source/C || { echo "Failed to build BaseTools"; exit 1; }

config:
	echo "Configuring edk2 ..."; \
	cd $(EDK2_TOPDIR); \
	bash -c "source ./edksetup.sh"; \
	sed -i -e 's/^\s*\(TARGET\)\s*=\s*DEBUG\(\s\)$$/\1 = RELEASE\2/' \
	    -e 's/^\s*\(TOOL_CHAIN_TAG\)\s*=\s*MYTOOLS\(\s\)$$/\1 = GCC5\2/' \
	    Conf/target.txt; \
	[ "$(ARCH)" = "x86_64" ] && \
	    sed -i 's/^\s*\(TARGET_ARCH\)\s*=\s*IA32\(\s\)$$/\1 = $(EFI_ARCH)\2/' \
	        Conf/target.txt

build:
	echo "Building edk2 ..."; \
	cd $(EDK2_TOPDIR); \
	bash -c "source ./edksetup.sh; build -DSECURE_BOOT_ENABLE=TRUE -p \
		 $(EDK2_TARGET_PKG)/$(EDK2_TARGET_PKG).dsc" || { \
		     echo "Failed to build edk2"; exit 1; \
		 }

clean:

install: Makefile $(SUBLIBS)
	@$(INSTALL) -d -m 755 $(DESTDIR)$(libdir)/edk2
	@$(foreach x, $(SUBLIBS), $(INSTALL) -m 755 $(x) \
		$(DESTDIR)$(libdir)/edk2/`basename $(patsubst %.lib,%,$(x))`.a;)
	@$(INSTALL) -d -m 755 $(DESTDIR)$(includedir)/edk2
	@cp -a $(EDK2_TOPDIR)/MdePkg/Include/* $(DESTDIR)$(includedir)/edk2

tag:
	@$(GIT) tag -a $(LIBEDK2_VERSION) -m $(LIBEDK2_VERSION) refs/heads/master
