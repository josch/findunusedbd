#!/bin/sh -ex
# start this script without arguments and then start sbuild as:
#
#    sbuild --chroot-setup-commands='/home/prebuildcmd.sh chroot-setup' --pre-realbuild-commands='/home/prebuildcmd.sh pre-realbuild' --post-realbuild-commands='/home/prebuildcmd.sh post-realbuild'

if [ "$#" -eq 1 ]; then
	tmpdir="$1"
	# once something is written to the fifo, it indicates that fatrace should start
	SCHROOT_SESSION_ID=`cat "${tmpdir}/myfifo"`;
	# change to the schroot mount
	cd /var/lib/schroot/mount/$SCHROOT_SESSION_ID
	# start fatrace in the mounted directory
	fatrace --current-mount > "${tmpdir}/fatrace.log" &
	FATRACE_PID=$!
	# give fatrace some time to set up (value is arbitrary)
	sleep 5
	# signal that fatrace was started
	echo > "${tmpdir}/myfifo"
	# wait for build to finish
	cat "${tmpdir}/myfifo" > /dev/null
	kill $FATRACE_PID
	# clean up the fatrace log to only include unique paths
	sed 's/\/var\/lib\/schroot\/mount\/[^\/]\+//' "${tmpdir}/fatrace.log" \
		| awk '{ print $3; }' \
		| grep -v ^/build \
		| sort \
		| uniq \
		> "${tmpdir}/accessed.log"
	# now get all packages in /tmp/pkglists that have files that never appear in the collected trace
	while read namever; do
		name=`echo $namever | cut -d '=' -f 1 | cut -d ':' -f 1`
		# FIXME: the following cannot handle dependencies on virtual packages
		if [ -z "`comm -12 "${tmpdir}/accessed.log" "${tmpdir}/$namever"`" ] \
			&& grep --line-regexp "$name" "${tmpdir}/sbuild-dummy-depends" > /dev/null; then
			echo $namever
		fi
	done > "${tmpdir}/unneededdepends.list" < "${tmpdir}/bdselection.list"
	# signal that the script is about to exit
	echo > "${tmpdir}/myfifo"
elif [ "$#" -eq 2 ]; then
	case "$1" in
		chroot-setup)
			tmpdir="$2"
			dpkg --list | awk '$1 == "ii" { print $2"="$3 }' | sort > "${tmpdir}/initialselection.list"
			;;
		pre-realbuild)
			tmpdir="$2"
			# get the current selection so that the parent script can find the additional packages that were installed
			dpkg --list | awk '$1 == "ii" { print $2"="$3 }' | sort > "${tmpdir}/fullselection.list"
			# get all packages that were installed on top of the base packages
			comm -13 "${tmpdir}/initialselection.list" "${tmpdir}/fullselection.list" > "${tmpdir}/bdselection.list"
			# output the files belonging to all packages
			dpkg --list | awk '$1 == "ii" { print $2, $3 }' | while read namever; do
				set -- $namever
				name=$1
				ver=$2
				if grep --line-regexp "${name}=${ver}" "${tmpdir}/bdselection.list"; then
					dpkg -L $name | sort > "${tmpdir}/${name}=${ver}"
				fi
			done
			# output the dependencies of the sbuild dummy package
			dpkg --get-selections | awk '{ print $1; }' \
				| grep sbuild-build-depends \
				| grep -v sbuild-build-depends-core-dummy \
				| grep -v sbuild-build-depends-essential-dummy \
				| grep -v sbuild-build-depends-lintian-dummy \
				| xargs -I {} dpkg-query --showformat='${Depends}\n' --show {} \
				| sed 's/, \+/\n/'g \
				| sed 's/\([a-zA-Z0-9][a-zA-Z0-9+.-]*\).*/\1/' \
				| sort \
				| uniq \
				> "${tmpdir}/sbuild-dummy-depends"
			# output the schroot id to start tracing
			echo $SCHROOT_SESSION_ID > "${tmpdir}/myfifo"
			# wait for fatrace to be forked
			cat "${tmpdir}/myfifo" > /dev/null
			;;
		post-realbuild)
			tmpdir="$2"
			# signal that the build is done
			echo > "${tmpdir}/myfifo"
			# wait for the parent process to finish and exit
			# if we do not do this then schroot cannot umount
			# because our script will still have the directory as
			# its working dir
			cat "${tmpdir}/myfifo" > /dev/null
			# give it some time to really exit (value is arbitrary)
			sleep 1
			;;
		equivs)
			namever="$2"
			# create and install a package with same name and version but without dependencies
			# removing Source: field because of bug#751942
			apt-cache show --no-all-versions $namever \
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
else
	echo "usage: " >&2
	echo "   $0 tmpdir"
	echo "   $0 [chroot-setup|pre-realbuild|post-realbuild] tmpdir"
	echo "   $0 equivs pkgname"
	exit 1
fi
