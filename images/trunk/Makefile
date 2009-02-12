# Makefile for slashdot.jp images

DESTDIR = /var/lib/slash/site/slashdot.jp/htdocs/images

sections = apple ask books developer games hardware it linux mobile politics yro
csses = core-tidied comments firehose search polls calendar admin admin-topic-popup print handheld slashcode_lite slashcode_low_bw iestyles ie6 ie7 ie8 idlecore-tidied lick comments-idle ie6-idle ie7-idle ie8-idle
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

css/slashcode_lite.css css/slashcode_low_bw.css css/iestyles.css css/admin.css css/comments.css css/firehose.css css/ie6.css css/ie7.css: %: %.orig %.jp
$(patsubst %, css/slashdot_%.css, $(sections)): %: %.orig %.jp
$(csses): %: css/%.css
$(sections): %: css/slashdot_%.css
$(patsubst %, css/%.css, $(csses)) $(patsubst %,css/slashdot_%.css, $(sections)): %: %.orig
	cat $@.orig | \
		sed -e 's/images\.slashdot\.org/images.slashdot.jp/' | \
		sed -e 's/text-align: right padding: 3px;/text-align: right; padding: 3px;/' | \
		sed -e 's/ul li {list-style-type: none}//' | \
		sed -e 's/\(#articles div.storylinks {margin-top: 1em !important}\)/\/* \1/' | \
		sed -e 's/\(div.storylinks ul {padding: .75em 8em .75em .6em; }\)/\1 *\//' | \
		sed -e 's/#articles div.storylinks ul {height: 2.3em; padding: 0 0 0 1em !important; z-index: 100;/#articles div.storylinks ul {height: 2.3em; padding: 0 0 0 1em !important; z-index: 100; }/' | \
		sed -e 's/#articles div.storylinks, div.storylinks div, div.storylinks ul {position: relative !important; margin: 0 !important; padding: 0 !important; height: 3em;}/#articles div.storylinks, div.storylinks div, div.storylinks ul {_position: relative !important; _margin: 0 !important; _padding: 0 !important; _height: 3em;}/' | \
		sed -e 's/#commentwrap {clear: both;}/* html #commentwrap {clear: both;}/' | \
		sed -e 's/div#users-blocks {margin: 0 18.5em 0 0; overflow: hidden;}/div#users-blocks {margin: 0 18.5em 0 0; _overflow: hidden;}/' | \
		perl -npe 's/\.briefarticle h3 a {#555}/.briefarticle h3 a { color: #555; }/' | \
		perl -npe 's/\bfont-family:[^;]+;//' | \
		perl -npe "s/^\/\/.*$$//" | \
		perl -npe 's/\bsans-serif\b//' > $@
	echo >> $@
	if [ -f $@.jp ]; then cat $@.jp >> $@; fi

css/%.css.orig:
	wget --no-proxy --no-verbose http://images.slashdot.org/$(patsubst css/%.orig,%, $@) -O $@

all-minified.js: %: %.orig %.jp %.prefix
$(jses): %: %.js
$(patsubst %, %.js, $(jses)): %: %.orig
	if [ -f $@.prefix ]; then cat $@.prefix > $@; else echo -n > $@; fi
	cat $@.orig | \
		sed -e 's/if(name=="usermode"){/if(name=="firehose_usermode"){/' | \
		sed -e 's/ Firehose / アレたま /' | \
		sed -e 's/"Sunday","Monday","Tuesday","Wednesday","Thursday","Friday","Saturday"/"日曜日","月曜日","火曜日","水曜日","木曜日","金曜日","土曜日"/' | \
		sed -e 's/"Sun","Mon","Tue","Wed","Thu","Fri","Sat"/"日","月","火","水","木","金","土"/' | \
		sed -e 's/"S","M","T","W","T","F","S"/"日","月","火","水","木","金","土"/' | \
		sed -e 's/"January","February","March","April","May","June","July","August","September","October","November","December"/"1月","2月","3月","4月","5月","6月","7月","8月","9月","10月","11月","12月"/' | \
		sed -e 's/"Jan","Feb","Mar","Apr","May","Jun","Jul","Aug","Sep","Oct","Nov","Dec"/"1月","2月","3月","4月","5月","6月","7月","8月","9月","10月","11月","12月"/' | \
		sed -e 's/title="History "/title="履歴 "/' | \
		sed -e "s/html('Paused')/html('停止中')/" | \
		sed -e "s/html('Updated')/html('更新中')/" | \
		sed -e 's/sitename="Slashdot";/sitename="スラッシュドット ジャパン";/' | \
		sed -e 's/Update failed or timed out\./更新に失敗したか、タイムアウトしました。/' | \
		sed -e 's/Firehose updates failed/アレたまの更新に失敗しました/' | \
		sed -e 's/Firehose Paused due to inactivity/アクティブでないので、アレたまの更新を一時停止しました/' | \
		sed -e 's/Click to retry/もう一度やってみる/' | \
		sed -e 's/Click to unpause/一時停止を解除する/' | \
		sed -e 's/>Cancel Reply</>返信をキャンセル</' | \
		sed -e 's/>Loading\.\.\./>読み込み中.../' | \
		sed -e "s/' comments are beneath your threshhold'/'個のコメントが現在のしきい値以下です'/" | \
		sed -e 's/Get More Comments/さらにコメントを取得/' | \
		sed -e 's/Get 1 More Comment/もう一つコメントを取得/' | \
		sed -e "s/'Get ' + num + ' More Comments'/'さらにコメントを' + num + '個取得'/" | \
		sed -e "s/'No More Comments At This Threshold'/'このしきい値ではもうコメントはありません'/" | \
		sed -e 's/>There are no more comments available at Score:--SCORE--, but there might be more at Score:--SCORE1--.</>スコア: --SCORE-- ではもう表示できるコメントはありませんが、スコア: --SCORE1-- ならありそうです。</' | \
		sed -e 's/>Would you like to lower your threshold for/>しきい値を下げますか？/' | \
		sed -e 's/value="this"/value="この議論だけ"/' | \
		sed -e 's/value="all"/value="すべての議論で"/' | \
		sed -e 's/value="No Thanks"/value="やりません"/' | \
		sed -e 's/>(Remember that you can always adjust these controls with the slider widget/>（コメントの--LEFTORTOP--に見えるスライダーで制御できますよ）/' | \
		sed -e 's/visible to the --LEFTORTOP-- of the discussion.)</</' | \
		sed -e "s/'top' : 'left';/'上の' : '左の';/" | \
		sed -e 's/hidden comment</個の隠れコメント</' | \
		sed -e 's/hidden comments</個の隠れコメント</' >> $@
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
