# Makefile for slashdot.jp images

CORE_TIDIED = css/core-tidied.css
CORE_TIDIED_ORIG = $(CORE_TIDIED).orig

default: $(CORE_TIDIED) images

images: images-stamp
images-stamp:
	perl -ne 'print "http:$$1\n" if /url\((\/\/images\.slashdot\.org\/[^)]+)/;' $(CORE_TIDIED_ORIG) | \
		sort -u | \
		wget --no-host-directories --mirror --verbose -i -
	touch images-stamp

$(CORE_TIDIED): $(CORE_TIDIED_ORIG)
	cat $(CORE_TIDIED_ORIG) | sed -e 's/images\.slashdot\.org/images\.slashdot\.jp/' > $(CORE_TIDIED)

$(CORE_TIDIED_ORIG): get
get:
	wget -q http://images.slashdot.org/core-tidied.css -O $(CORE_TIDIED_ORIG)

force: clean default

clean:
	rm -f $(CORE_TIDIED) $(CORE_TIDIED_ORIG) images-stamp

.PHONY: default get clean force
