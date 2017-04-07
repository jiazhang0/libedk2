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
EDKS_BUILD_OPTS := \
	-q -s -a $(EFI_ARCH) -b RELEASE -t GCC5 \
	-DSECURE_BOOT_ENABLE=TRUE

EDK2_PKG_LIBS_Mde := \
	BaseMemoryLib \
	BaseLib \
	BasePcdLibNull \
	UefiDebugLibStdErr \
	UefiRuntimeServicesTableLib \
	UefiBootServicesTableLib

EDK2_PKG_LIBS_Shell := \
	UefiHandleParsingLib

EDK2_PKG_LIBS_MdeModule := \
	FileExplorerLib

# These libraries cannot be built directly.
EDK2_EXTRA_PKG_LIBS_Shell_Mde := \
	UefiFileHandleLib

define BUILD_EDK2_PKG
	build $(EDKS_BUILD_OPTS) -p \"$(1)Pkg/$(1)Pkg.dsc\"; \
	if [ \$$? -ne 0 ]; then \
	    echo \"Failed to build $(1)Pkg\"; \
	    exit 1; \
	fi
endef

define BUILD_EDK2_PKG_LIBS
	for lib in $(EDK2_PKG_LIBS_$(1)); do \
	    build $(EDKS_BUILD_OPTS) -p \"$(1)Pkg/$(1)Pkg.dsc\" \
		-m \"$(1)Pkg/Library/\$$lib/\$$lib.inf\"; \
	    if [ \$$? -ne 0 ]; then \
		echo \"Failed to build $(1)Pkg:\$$lib\"; \
		exit 1; \
	    fi; \
	done
endef

define INSTALL_EDK2_LIBS
	$(shell \
	    for lib in $(EDK2_PKG_LIBS_$(1)); do \
		echo "$(EDK2_TOPDIR)/Build/$(1)/RELEASE_GCC5/$(EFI_ARCH)/$(1)Pkg/Library/$$lib/$$lib/OUTPUT/$$lib.lib"; \
	    done; \
	)
endef

define INSTALL_EDK2_EXTRA_LIBS
	$(shell \
	    for lib in $(EDK2_EXTRA_PKG_LIBS_$(1)_$(2)); do \
		echo "$(EDK2_TOPDIR)/Build/$(1)/RELEASE_GCC5/$(EFI_ARCH)/$(2)Pkg/Library/$$lib/$$lib/OUTPUT/$$lib.lib"; \
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
		 build $(EDKS_BUILD_OPTS) clean; \
		"

install: $(call INSTALL_EDK2_LIBS,Mde) \
	 $(call INSTALL_EDK2_LIBS,MdeModule) \
	 $(call INSTALL_EDK2_LIBS,Shell) \
	 $(call INSTALL_EDK2_EXTRA_LIBS,Shell,Mde)
	@$(INSTALL) -d -m 755 "$(DESTDIR)$(libdir)/edk2"
	@$(foreach x, $^, \
	    $(INSTALL) -m 755 "$(x)" \
	        "$(DESTDIR)$(libdir)/edk2/lib`basename $(patsubst %.lib,%,$(x))`.a";)
	@$(INSTALL) -d -m 755 "$(DESTDIR)$(includedir)/edk2"
	@cp -a "$(EDK2_TOPDIR)"/MdePkg/Include/* "$(DESTDIR)$(includedir)/edk2"

tag:
	@$(GIT) tag -a "$(LIBEDK2_VERSION)" -m "$(LIBEDK2_VERSION)" refs/heads/master

patch_openssl:
	@echo "Checking openssl ..."; \
	cd "$(EDK2_TOPDIR)/CryptoPkg/Library/OpensslLib"; \
	if [ -f Patch-HOWTO.txt ]; then \
	    pattern='openssl-[[:digit:]]\.[[:digit:]]\{1,2\}\.[[:digit:]]\{1,2\}[a-z]\?'; \
	    link=`grep -m 1 "^\s*http://www\.openssl\.org/source/$$pattern\.tar\.gz\s$$" \
	        Patch-HOWTO.txt | grep -o "http.*\.tar\.gz"`; \
	    dirname=`echo $$link | grep -o "$$pattern"`; \
	    pkgname=dirname; \
	    new_scheme=0; \
	elif [ -f OpenSSL-HOWTO.txt ]; then \
	    pattern='[[:digit:]]\.[[:digit:]]\{1,2\}\.[[:digit:]]\{1,2\}[a-z]\?'; \
	    pkgname=openssl-`grep -m 1 "^\s*The latest official release is OpenSSL-$$pattern " \
	        OpenSSL-HOWTO.txt | grep -o "$$pattern"`; \
	    link="https://www.openssl.org/source/$$pkgname.tar.gz"; \
	    dirname=openssl; \
	    new_scheme=1; \
	fi; \
	[ x"$$dirname" = x"" ] && { echo "Failed to find out openssl pattern"; exit 1; }; \
	echo "$$pkgname used"; \
	[ ! -d "$$dirname" ] && { \
	    [ ! -s "$$pkgname.tar.gz" ] && { \
	        echo "Downloading $$pkgname ..."; \
	        wget "$$link" || { echo "Failed to download $$pkgname"; exit 1; }; \
	    }; \
	    echo "Extracting $$pkgname ..."; \
	    tar xzf "$$pkgname.tar.gz" || { echo "Failed to extract $$pkgname"; exit 1; }; \
	    if [ $$new_scheme -eq 0 ]; then \
	        echo "Patching $$pkgname ..."; \
	        cd "$$pkgname"; \
	        patch -p1 -i "../EDKII_$$pkgname.patch" || { \
	            echo "Failed to patch $$pkgname"; exit 1; \
	        }; \
	        cd ..; \
	        echo "Installing $$pkgname ..."; \
	        bash -c ./Install.sh || { echo "Failed to install $$pkgname"; exit 1; }; \
	    else \
	        mv "$$pkgname" "$$dirname"; \
	        chmod +x ./process_files.pl; \
	        ./process_files.pl; \
	    fi; \
	}; \
	echo "$$pkgname applied"

build_basetools:
	@echo "Building BaseTools ..."; \
	cd "$(EDK2_TOPDIR)"; \
	$(MAKE) -C BaseTools/Source/C || { echo "Failed to build BaseTools"; exit 1; }

build:
	@echo "Building edk2 ..."; \
	cd $(EDK2_TOPDIR); \
	bash -c "source ./edksetup.sh; \
		 $(call BUILD_EDK2_PKG_LIBS,Mde); \
		"
