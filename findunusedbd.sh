#!/bin/sh -ex
# start this script without arguments and then start sbuild as:
#
#    sbuild --chroot-setup-commands='/home/josch/prebuildcmd.sh chroot-setup' --pre-realbuild-commands='/home/josch/prebuildcmd.sh pre-realbuild' --post-realbuild-commands='/home/josch/prebuildcmd.sh post-realbuild'

if [ "$#" -ne 1 ]; then
	rm -rf /home/josch/myfifo /home/josch/myfifo2 /tmp/pkglists
	mkfifo /home/josch/myfifo
	mkfifo /home/josch/myfifo2
	mkdir -p /tmp/pkglists
	# strip the architecture qualifier
	cat /home/josch/myfifo | cut -d ':' -f 1 | sort > initialselection.list
	echo > /home/josch/myfifo2
	cat /home/josch/myfifo | cut -d ':' -f 1 | sort > fullselection.list
	echo > /home/josch/myfifo2
	# get all packages that were installed on top of the base packages
	comm -13 initialselection.list fullselection.list > bdselection.list
	while true; do
		pkgname=`cat /home/josch/myfifo | cut -d ':' -f 1`
		echo > /home/josch/myfifo2
		# end loop when packagename is empty
		[ -z "$pkgname" ] && break
		# check if the package was installed as its build dependencies
		if grep --line-regexp $pkgname bdselection.list; then
			cat /home/josch/myfifo | sort > "/tmp/pkglists/$pkgname"
		else
			cat /home/josch/myfifo > /dev/null
		fi
		echo > /home/josch/myfifo2
	done
	cat /home/josch/myfifo | sed 's/, \+/\n/'g \
		| sed 's/\([a-zA-Z0-9][a-zA-Z0-9+.-]*\).*/\1/' \
		> /tmp/sbuild-dummy-depends
	echo > /home/josch/myfifo2
	SCHROOT_SESSION_ID=`cat /home/josch/myfifo`;
	echo > /home/josch/myfifo2

	# start fatrace in the mounted directory
	(
		cd /var/lib/schroot/mount/$SCHROOT_SESSION_ID;
		sudo fatrace --current-mount > /home/josch/fatrace.log &
		FATRACE_PID=$!;
		cat /home/josch/myfifo > /dev/null;
		echo > /home/josch/myfifo2
		sudo kill $FATRACE_PID;
	)

	# clean up the fatrace log to only include unique paths
	sed 's/\/var\/lib\/schroot\/mount\/[^\/]\+//' /home/josch/fatrace.log \
		| awk '{ print $3; }' \
		| grep -v ^/build \
		| sort \
		| uniq \
		> accessed.log
	# now get all packages in /tmp/pkglists that have files that never appear in the collected trace
	while read pkg; do
		# FIXME: the following cannot handle dependencies on virtual packages
		[ -z "`comm -12 accessed.log /tmp/pkglists/$pkg`" ] \
			&& grep --line-regexp "$pkg" /tmp/sbuild-dummy-depends || true
	done > unneededdepends.list < bdselection.list
else
	case "$1" in
		chroot-setup)
			env
			dpkg --get-selections | awk '{ print $1; }' > /home/josch/myfifo
			cat /home/josch/myfifo2 > /dev/null
			;;
		pre-realbuild)
			# get the current selection so that the parent script can find the additional packages that were installed
			dpkg --get-selections | awk '{ print $1; }' > /home/josch/myfifo
			cat /home/josch/myfifo2 > /dev/null
			# output the files belonging to all packages
			for pkg in `dpkg --get-selections | awk '{ print $1; }'`; do
				echo $pkg > /home/josch/myfifo
				cat /home/josch/myfifo2 > /dev/null
				dpkg -L $pkg > /home/josch/myfifo
				cat /home/josch/myfifo2 > /dev/null
			done
			# output an empty line to indicate the end
			echo > /home/josch/myfifo
			cat /home/josch/myfifo2 > /dev/null
			# output the dependencies of the sbuild dummy package
			dpkg --get-selections | awk '{ print $1; }' \
				| grep sbuild-build-depends \
				| grep -v sbuild-build-depends-core-dummy \
				| grep -v sbuild-build-depends-essential-dummy \
				| grep -v sbuild-build-depends-lintian-dummy \
				| xargs -I {} dpkg-query --showformat='${Depends}\n' --show {} \
				> /home/josch/myfifo
			cat /home/josch/myfifo2 > /dev/null
			# output the schroot id to start tracing
			echo $SCHROOT_SESSION_ID > /home/josch/myfifo
			cat /home/josch/myfifo2 > /dev/null
			;;
		post-realbuild)
			echo "done" > /home/josch/myfifo
			cat /home/josch/myfifo2 > /dev/null
			;;
		*)
			echo "invalid argument: $1" >&2
			;;
	esac
fi
