#!/bin/sh -x

if [ $# -eq 0 ]; then
	echo "usage: $0 foo.dsc [bar.dsc ...]"
	exit 1
fi

# 1. create temporary directory
# 2. create fifo
# 3. run findunusedbd to start fatrace from outside
# 4. run sbuild with the correct hooks
# 5. if sbuild was successful, collect unused dependencies
# 6. remove temporary directory
build () {
	dsc="$1"
	archall="$2"
	tmpdir=`mktemp -d --tmpdir=/home`
	mkfifo "${tmpdir}/myfifo"
	chmod a+w "${tmpdir}/myfifo"
	/home/findunusedbd.sh "$tmpdir" &
	sbuild --$archall --quiet \
		--chroot-setup-commands="/home/findunusedbd.sh chroot-setup $tmpdir" \
		--pre-realbuild-commands="/home/findunusedbd.sh pre-realbuild $tmpdir" \
		--post-realbuild-commands="/home/findunusedbd.sh post-realbuild $tmpdir" \
		"$dsc"
	ret=$?
	rm -f *.deb *.udeb *.changes
	if [ $ret -eq 0 ] && [ -s "${tmpdir}/unneededdepends.list" ]; then
		mv "${tmpdir}/unneededdepends.list" `basename $dsc .dsc`.${archall}.unusedbd
		echo $dsc >> buildsuccess.${archall}.list
	fi
	rm -rf "$tmpdir"
}

for a in "arch-all" "no-arch-all"; do
	echo > buildsuccess.${a}.list
	for dsc in $@; do
		echo $dsc
		build "$dsc" "$a"
	done
done

# now process the possibly droppable build dependencies found by no-arch-all
# and remove from them all that were also found by arch-all
for noarchall in *.no-arch-all.unusedbd; do
	archall=`basename $noarchall .no-arch-all.unusedbd`.arch-all.unusedbd
	if [ -s $archall ]; then
		# only keep the values unique to no-arch-all
		comm -23 $noarchall $archall > tmp
		if [ -s tmp ]; then
			mv tmp $noarchall
		else
			# no unique values in noarchall
			rm $noarchall
		fi
	fi
done

# 1. for all possibly unused dependencise, run sbuild with a hook creating a
#    fake equivs package
# 2. if sbuild was successful, collect result
check () {
	dscname="$1"
	archall="$2"
	unusedbdname=`basename $dscname .dsc`.${archall}.unusedbd
	while read bd; do
		# now run sbuild with "findunusedbd.sh equivs" creating a fake equivs package
		sbuild --$archall --quiet \
			--chroot-setup-commands="/home/findunusedbd.sh equivs $bd" \
			"$dscname"
		if [ $? -eq 0 ]; then
			echo $bd >> "${unusedbdname}".real
		fi
		rm -f *.deb *.udeb *.changes
	done < $unusedbdname
}

for a in "arch-all" "no-arch-all"; do
	while read dscname; do
		echo $dscname
		check $dscname "$a"
	done < buildsuccess.${a}.list
done
