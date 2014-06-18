#!/bin/sh -x

if [ $# -eq 0 ]; then
	echo "usage: $0 foo.dsc [bar.dsc ...]"
	exit 1
fi

echo > buildsuccess.list
for dsc in $1; do
	echo $dsc
	/home/findunusedbd.sh &
	sbuild --no-arch-all \
		--chroot-setup-commands='/home/findunusedbd.sh chroot-setup' \
		--pre-realbuild-commands='/home/findunusedbd.sh pre-realbuild' \
		--post-realbuild-commands='/home/findunusedbd.sh post-realbuild' \
		"$dsc"
	ret=$?
	rm -f *.deb *.udeb *.changes
	if [ $ret -eq 0 ] && [ -s unneededdepends.list ]; then
		mv unneededdepends.list `basename $dsc .dsc`.unusedbd
		echo $dsc >> buildsuccess.list
	fi
done

while read dscname; do
	echo $dscname
	unusedbdname=`basename $dscname .dsc`.unusedbd
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
done < buildsuccess.list
