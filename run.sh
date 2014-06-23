#!/bin/sh -x

if [ $# -eq 0 ]; then
	echo "usage: $0 foo.dsc [bar.dsc ...]"
	exit 1
fi

build () {
	dsc="$1"
	archall="$2"
	tmpdir=`mktemp -d --tmpdir=/home`
	mkfifo "${tmpdir}/myfifo"
	chmod a+w "${tmpdir}/myfifo"
	/home/findunusedbd.sh "$tmpdir" &
	sbuild --$archall \
		--chroot-setup-commands="/home/findunusedbd.sh chroot-setup $tmpdir" \
		--pre-realbuild-commands="/home/findunusedbd.sh pre-realbuild $tmpdir" \
		--post-realbuild-commands="/home/findunusedbd.sh post-realbuild $tmpdir" \
		"$dsc"
	ret=$?
	rm -f *.deb *.udeb *.changes
	if [ $ret -eq 0 ] && [ -s unneededdepends.list ]; then
		mv "${tmpdir}/unneededdepends.list" `basename $dsc .dsc`.${archall}.unusedbd
		echo $dsc >> buildsuccess.${archall}.list
	fi
	rm -rf "$tmpdir"
}

check () {
	dscname="$1"
	archall="$2"
	unusedbdname=`basename $dscname .dsc`.${archall}.unusedbd
	while read bd; do
		# now run sbuild with "findunusedbd.sh equivs" creating a fake equivs package
		sbuild --no-arch-all \
			--chroot-setup-commands="/home/findunusedbd.sh equivs $bd" \
			"$dscname"
		if [ $? -eq 0 ]; then
			echo $bd >> "${unusedbdname}".real
		fi
		rm -f *.deb *.udeb *.changes
	done < $unusedbdname
}

for a in "arch-all" "no-arch-all"; do
	echo > buildsuccess.${a}.list
	for dsc in $@; do
		echo $dsc
		build "$dsc" "$a"
	done

	while read dscname; do
		echo $dscname
		check $dscname "$a"
	done < buildsuccess.${a}.list
done
