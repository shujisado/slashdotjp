# Makefile for slashdot.jp images

DESTDIR = /var/lib/slash/site/slashdot.jp/htdocs/images

sections = apple ask books developer games hardware it linux mobile politics yro
csses = core-tidied comments firehose search polls calendar admin admin-topic-popup print handheld slashcode_lite slashcode_low_bw iestyles
jses = all-minified

default: update
update: $(csses) $(sections) $(jses) images

install:
	rsync -avHSC --exclude=/hc/ --exclude=Makefile --exclude=\*-stamp ./ $(DESTDIR)

images: images-stamp
images-stamp:
	perl -ne "print \"http:\$$1\n\" if /url\(['\"]?(\/\/images\.slashdot\.org\/[^)'\"]+)/;" $(patsubst %,css/%.css.orig, $(csses)) $(patsubst %,css/slashdot_%.css.orig, $(sections)) | \
		sed -e 's/\.pnh$$/.png/' | \
		sort -u | \
		wget --no-proxy --no-host-directories --mirror --no-verbose -i -
	touch images-stamp

$(csses): %: css/%.css
$(sections): %: css/slashdot_%.css
$(patsubst %, css/%.css, $(csses)) $(patsubst %,css/slashdot_%.css, $(sections)): %: %.orig
	cat $@.orig | \
		sed -e 's/images\.slashdot\.org/images.slashdot.jp/' | \
		sed -e 's/text-align: right padding: 3px;/text-align: right; padding: 3px;/' | \
		perl -npe 's/\bfont-family:[^;]+;//' | \
		perl -npe 's/\bsans-serif\b//' > $@

css/%.css.orig: FORCE
	wget --no-proxy --no-verbose http://images.slashdot.org/$(patsubst css/%.orig,%, $@) -O $@

$(jses): %: %.js
$(patsubst %, %.js, $(jses)): %: %.orig
	cat $@.orig | \
		sed -e 's/ Firehose / アレたま /' | \
		sed -e 's/sitename="Slashdot";/sitename="スラッシュドット ジャパン";/' > $@

%.js.orig: FORCE
	wget --no-proxy --no-verbose http://slashdot.org/$(patsubst %.js.orig,%.js, $@) -O $@

force: clean default

clean:
	rm -f css/*.css.orig *.js.orig image-stamp \
		$(patsubst %,css/%.css, $(csses)) \
		$(patsubst %,css/slashdot_%.css, $(sections)) \
		$(patsubst %,%.js, $(jses))

.PHONY: default update images clean force install FORCE
