# Makefile for slashdot.jp images

DESTDIR = /var/lib/slash/site/slashdot.jp/htdocs/images

sections = apple ask books developer games hardware it linux mobile politics yro
csses = core-tidied comments firehose search polls calendar admin admin-topic-popup print handheld slashcode_lite slashcode_low_bw iestyles ie6 ie7 ie8 idlecore-tidied lick comments-idle
jses = all-minified comments sectionprefs jquery-opt-1
aimages = friend.png foe.png freak.png fof.png neutral.png fan.png eof.png

default: update
update: $(csses) $(sections) $(jses) images

install: default
	rsync -avHSC --exclude=/hc/ --exclude=Makefile --exclude=\*-stamp --exclude=\*.jp ./ $(DESTDIR)

images: images-stamp
images-stamp: $(patsubst %,css/%.css.orig, $(csses)) $(patsubst %,css/slashdot_%.css.orig, $(sections)) $(aimages)
	perl -ne "s|(url\(['\"]?/)([^/])|\$$1/images.slashdot.org/\$$2|g; print \"http:\$$1\n\" if /url\(['\"]?(\/\/images\.slashdot\.org\/[^)'\"]+)/;" $(patsubst %,css/%.css.orig, $(csses)) $(patsubst %,css/slashdot_%.css.orig, $(sections)) | \
		sed -e 's/\.pnh$$/.png/' | \
		sort -u | \
		wget --no-proxy --no-host-directories --mirror --no-verbose -i -
	touch images-stamp

css/slashcode_lite.css css/slashcode_low_bw.css css/iestyles.css css/admin.css css/slashdot_linux.css css/comments.css: %: %.orig %.jp
$(csses): %: css/%.css
$(sections): %: css/slashdot_%.css
$(patsubst %, css/%.css, $(csses)) $(patsubst %,css/slashdot_%.css, $(sections)): %: %.orig
	cat $@.orig | \
		sed -e 's/images\.slashdot\.org/images.slashdot.jp/' | \
		sed -e 's/text-align: right padding: 3px;/text-align: right; padding: 3px;/' | \
		sed -e 's/#articles div.storylinks ul {height: 2.3em; padding: 0 0 0 1em !important; z-index: 100;/#articles div.storylinks ul {height: 2.3em; padding: 0 0 0 1em !important; z-index: 100; }/' | \
		sed -e 's/#articles div.storylinks, div.storylinks div, div.storylinks ul {position: relative !important; margin: 0 !important; padding: 0 !important; height: 3em;}/#articles div.storylinks, div.storylinks div, div.storylinks ul {_position: relative !important; _margin: 0 !important; _padding: 0 !important; _height: 3em;}/' | \
		sed -e 's/#commentwrap {clear: both;}/* html #commentwrap {clear: both;}/' | \
		sed -e 's/div#users-blocks {margin: 0 18.5em 0 0; overflow: hidden;}/div#users-blocks {margin: 0 18.5em 0 0; _overflow: hidden;}/' | \
		perl -npe 's/\bfont-family:[^;]+;//' | \
		perl -npe "s/^\/\/.*$$//" | \
		perl -npe 's/\bsans-serif\b//' > $@
	echo >> $@
	if [ -f $@.jp ]; then cat $@.jp >> $@; fi

css/%.css.orig:
	wget --no-proxy --no-verbose http://images.slashdot.org/$(patsubst css/%.orig,%, $@) -O $@

all-minified.js: %: %.orig %.jp
$(jses): %: %.js
$(patsubst %, %.js, $(jses)): %: %.orig
	cat $@.orig | \
		sed -e 's/ Firehose / アレたま /' | \
		sed -e 's/innerHTML="Paused"/innerHTML="停止中"/' | \
		sed -e 's/innerHTML="Updated"/innerHTML="更新中"/' | \
		sed -e 's/sitename="Slashdot";/sitename="スラッシュドット ジャパン";/' > $@
	echo >> $@
	if [ -f $@.jp ]; then cat $@.jp >> $@; fi

%.js.orig:
	wget --no-proxy --no-verbose http://images.slashdot.org/$(patsubst %.js.orig,%.js, $@) -O $@

$(aimages):
	wget --no-proxy --no-verbose http://images.slashdot.org/$@ -O $@

force: clean default

clean:
	rm -f css/*.css.orig *.js.orig images-stamp \
		$(patsubst %,css/%.css, $(csses)) \
		$(patsubst %,css/slashdot_%.css, $(sections)) \
		$(patsubst %,%.js, $(jses))

.PHONY: default update images clean force install FORCE
