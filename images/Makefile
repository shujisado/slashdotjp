# Makefile for slashdot.jp images

DESTDIR = /var/lib/slash/site/slashdot.jp/htdocs/images

sections = apple ask books developer games hardware it linux mobile politics yro
csses = core-tidied comments firehose search polls calendar admin admin-topic-popup print handheld slashcode_lite slashcode_low_bw
jses = all-minified

default: $(csses) $(sections) $(jses) images

install: default
	rsync -n -avHSC --exclude=/hc/ --exclude=Makefile --exclude=\*-stamp ./ $(DESTDIR)

images: images-stamp
images-stamp:
	perl -ne "print \"http:\$$1\n\" if /url\(['\"]?(\/\/images\.slashdot\.org\/[^)'\"]+)/;" $(patsubst %,css/%.css.orig, $(csses)) $(patsubst %,css/slashdot_%.css.orig, $(sections)) | \
		sed -e 's/\.pnh$$/.png/' | \
		sort -u | \
		wget --no-host-directories --mirror --no-verbose -i -
	touch images-stamp

$(csses): %: css/%.css
$(sections): %: css/slashdot_%.css
$(patsubst %,css/%.css, $(csses)) $(patsubst %,css/slashdot_%.css, $(sections)): %: %.orig
	cat $@.orig | sed -e 's/images\.slashdot\.org/images.slashdot.jp/' > $@

css/%.css.orig: FORCE
	wget --no-verbose http://images.slashdot.org/$(patsubst css/%.orig,%, $@) -O $@

$(jses): FORCE
	wget --no-verbose http://slashdot.org/$(patsubst %,%.js, $@) -O $(patsubst %,%.js, $@)

force: clean default

clean:
	rm -f css/*.css.orig image-stamp \
		$(patsubst %,css/%.css, $(csses)) \
		$(patsubst %,css/slashdot_%.css, $(sections)) \
		$(patsubst %,%.js, $(jses))

.PHONY: default images clean force install FORCE
