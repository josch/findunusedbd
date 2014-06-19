#!/bin/sh -ex
# start this script without arguments and then start sbuild as:
#
#    sbuild --chroot-setup-commands='/home/prebuildcmd.sh chroot-setup' --pre-realbuild-commands='/home/prebuildcmd.sh pre-realbuild' --post-realbuild-commands='/home/prebuildcmd.sh post-realbuild'

if [ "$#" -eq 0 ]; then
	rm -rf /home/myfifo /home/myfifo2 /tmp/pkglists
	# fifo to receive data
	mkfifo /home/myfifo
	# fifo to acknowledge reception
	mkfifo /home/myfifo2
	# make sure the sbuild user can write to the fifos
	chmod a+w /home/myfifo
	chmod a+w /home/myfifo2
	mkdir -p /tmp/pkglists
	# strip the architecture qualifier
	cat /home/myfifo | sort > initialselection.list
	echo > /home/myfifo2
	cat /home/myfifo | sort > fullselection.list
	echo > /home/myfifo2
	# get all packages that were installed on top of the base packages
	comm -13 initialselection.list fullselection.list > bdselection.list
	while true; do
		pkgnamever=`cat /home/myfifo`
		echo > /home/myfifo2
		# end loop when packagename is empty
		[ -z "$pkgnamever" ] && break
		# check if the package was installed as its build dependencies
		if grep --line-regexp $pkgnamever bdselection.list; then
			cat /home/myfifo | sort > "/tmp/pkglists/$pkgnamever"
		else
			cat /home/myfifo > /dev/null
		fi
		echo > /home/myfifo2
	done
	cat /home/myfifo | sed 's/, \+/\n/'g \
		| sed 's/\([a-zA-Z0-9][a-zA-Z0-9+.-]*\).*/\1/' \
		> /tmp/sbuild-dummy-depends
	echo > /home/myfifo2
	SCHROOT_SESSION_ID=`cat /home/myfifo`;
	echo > /home/myfifo2

	# start fatrace in the mounted directory
	(
		cd /var/lib/schroot/mount/$SCHROOT_SESSION_ID;
		fatrace --current-mount > /home/fatrace.log &
		FATRACE_PID=$!;
		cat /home/myfifo > /dev/null;
		echo > /home/myfifo2
		kill $FATRACE_PID;
	)

	# clean up the fatrace log to only include unique paths
	sed 's/\/var\/lib\/schroot\/mount\/[^\/]\+//' /home/fatrace.log \
		| awk '{ print $3; }' \
		| grep -v ^/build \
		| sort \
		| uniq \
		> accessed.log
	# now get all packages in /tmp/pkglists that have files that never appear in the collected trace
	while read namever; do
		name=`echo $namever | cut -d '=' -f 1 | cut -d ':' -f 1`
		# FIXME: the following cannot handle dependencies on virtual packages
		if [ -z "`comm -12 accessed.log /tmp/pkglists/$namever`" ] \
			&& grep --line-regexp "$name" /tmp/sbuild-dummy-depends > /dev/null; then
			echo $namever
		fi
	done > unneededdepends.list < bdselection.list
else
	case "$1" in
		chroot-setup)
			env
			dpkg --list | awk '$1 == "ii" { print $2"="$3 }' > /home/myfifo
			cat /home/myfifo2 > /dev/null
			;;
		pre-realbuild)
			# get the current selection so that the parent script can find the additional packages that were installed
			dpkg --list | awk '$1 == "ii" { print $2"="$3 }' > /home/myfifo
			cat /home/myfifo2 > /dev/null
			# output the files belonging to all packages
			dpkg --list | awk '$1 == "ii" { print $2, $3 }' | while read namever; do
				set -- $namever
				name=$1
				ver=$2
				echo "${name}=${ver}" > /home/myfifo
				cat /home/myfifo2 > /dev/null
				dpkg -L $name > /home/myfifo
				cat /home/myfifo2 > /dev/null
			done
			# output an empty line to indicate the end
			echo > /home/myfifo
			cat /home/myfifo2 > /dev/null
			# output the dependencies of the sbuild dummy package
			dpkg --get-selections | awk '{ print $1; }' \
				| grep sbuild-build-depends \
				| grep -v sbuild-build-depends-core-dummy \
				| grep -v sbuild-build-depends-essential-dummy \
				| grep -v sbuild-build-depends-lintian-dummy \
				| xargs -I {} dpkg-query --showformat='${Depends}\n' --show {} \
				> /home/myfifo
			cat /home/myfifo2 > /dev/null
			# output the schroot id to start tracing
			echo $SCHROOT_SESSION_ID > /home/myfifo
			cat /home/myfifo2 > /dev/null
			;;
		post-realbuild)
			echo "done" > /home/myfifo
			cat /home/myfifo2 > /dev/null
			;;
		equivs)
			namever="$2"
			# create and install a package with same name and version but without dependencies
			# removing Source: field because of bug#751942
			apt-cache show --no-all-versions $namever
				| grep -v "^Pre-Depends:" \
				| grep -v "^Depends:" \
				| grep -v "^Recommends:" \
				| grep -v "^Suggests:" \
				| grep -v "^Conflicts:" \
				| grep -v "^Breaks:" \
				| grep -v "^Provides:" \
				| grep -v "^Replaces:" \
				| grep -v "^Source:" \
				| equivs-build -
			name=`echo $namever | cut -d '=' -f 1 | cut -d ':' -f 1`
			# we use a wildcard because there should only be a single file anyways
			dpkg -i ${name}_*.deb
			;;
		*)
			echo "invalid argument: $1" >&2
			;;
	esac
fi
