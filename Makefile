include Version.mk
include Env.mk

ARCH = $(shell $(CC) -dumpmachine | cut -f1 -d- | sed s,i[3456789]86,i386,)
TOPDIR=$(PWD)

.DEFAULT_GOAL := all
.PHONE: all clean install tag patch_openssl config build_basetools

all: patch_openssl config build_basetools build

patch_openssl:
	@echo "Checking openssl ..."; \
	cd $(TOPDIR)/edk2/CryptoPkg/Library/OpensslLib; \
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
	cd $(TOPDIR)/edk2; \
	$(MAKE) -C BaseTools/Source/C || { echo "Failed to build BaseTools"; exit 1; }

config:
	echo "Configuring edk2 ..."; \
	cd $(TOPDIR)/edk2; \
	bash -c "source ./edksetup.sh"; \
	sed -i -e 's/^\s*\(TARGET\)\s*=\s*DEBUG\(\s\)$$/\1 = RELEASE\2/' \
	    -e 's/^\s*\(TOOL_CHAIN_TAG\)\s*=\s*MYTOOLS\(\s\)$$/\1 = GCC5\2/' \
	    Conf/target.txt; \
	[ "$(ARCH)" = "x86_64" ] && \
	    sed -i 's/^\s*\(TARGET_ARCH\)\s*=\s*IA32\(\s\)$$/\1 = X64\2/' \
	        Conf/target.txt

build:
	echo "Building edk2 ..."; \
	cd $(TOPDIR)/edk2; \
	bash -c "source ./edksetup.sh; build -DSECURE_BOOT_ENABLE=TRUE -p \
		SecurityPkg/SecurityPkg.dsc" || { echo "Failed to build edk2"; exit 1; }

clean:

install:

tag:
	@$(GIT) tag -a $(LIBEDK2_VERSION) -m $(LIBEDK2_VERSION) refs/heads/master
