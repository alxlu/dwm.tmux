PREFIX=~/.local
BINDIR=${PREFIX}/bin
LIBDIR=${PREFIX}/lib
ARCH=$(shell uname -m)
OS=$(shell uname -s | tr '[:upper:]' '[:lower:]')


.PHONY: install bin lib

install: dirs bin lib

dirs:
	install -d ${BINDIR} ${LIBDIR}

lib:
	cp lib/* ${LIBDIR}/

bin:
	cp bin/* ${BINDIR}/
	cp dwmtmux-${OS}-${ARCH} ${BINDIR}/dwmtmux

uninstall:
	rm ${BINDIR}/dwm.tmux
	rm ${BINDIR}/dwmtmux
	rm ${LIBDIR}/dwm.tmux

