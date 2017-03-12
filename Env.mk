CROSS_COMPILE ?=
CC := $(CROSS_COMPILE)gcc
LD := $(CROSS_COMPILE)ld
AR := $(CROSS_COMPILE)ar
OBJCOPY := $(CROSS_COMPILE)objcopy
NM := $(CROSS_COMPILE)nm
INSTALL ?= install
OPENSSL ?= openssl
GIT ?= git
SBSIGN ?= sbsign

DESTDIR ?=

prefix ?= /usr
libdir ?= $(prefix)/lib
includedir ?= $(prefix)/include