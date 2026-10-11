PREFIX ?= $(HOME)/.local
BINDIR ?= $(PREFIX)/bin
DATADIR ?= $(PREFIX)/share/dwm.tmux
DESTDIR ?=
INSTALL_CLI ?= yes

.DEFAULT_GOAL := install
.PHONY: all install uninstall test lint

all: install

install:
	install -d -m 755 "$(DESTDIR)$(DATADIR)/bin" "$(DESTDIR)$(DATADIR)/lib"
	install -m 755 dwm.tmux "$(DESTDIR)$(DATADIR)/dwm.tmux"
	install -m 755 bin/dwm.tmux "$(DESTDIR)$(DATADIR)/bin/dwm.tmux"
	install -m 644 lib/dwm.tmux "$(DESTDIR)$(DATADIR)/lib/dwm.tmux"
ifeq ($(INSTALL_CLI),yes)
	install -d -m 755 "$(DESTDIR)$(BINDIR)"
	ln -sf "$(DATADIR)/bin/dwm.tmux" "$(DESTDIR)$(BINDIR)/dwm.tmux"
endif

uninstall:
	rm -f "$(DESTDIR)$(DATADIR)/dwm.tmux" "$(DESTDIR)$(DATADIR)/bin/dwm.tmux" "$(DESTDIR)$(DATADIR)/lib/dwm.tmux"
ifeq ($(INSTALL_CLI),yes)
	rm -f "$(DESTDIR)$(BINDIR)/dwm.tmux"
endif
	rmdir "$(DESTDIR)$(DATADIR)/bin" "$(DESTDIR)$(DATADIR)/lib" "$(DESTDIR)$(DATADIR)" 2>/dev/null || :

test:
	sh tests/integration.sh

lint:
	shellcheck dwm.tmux bin/dwm.tmux tests/*.sh

