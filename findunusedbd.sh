#!/bin/sh -ex
# start this script without arguments and then start sbuild as:
#
#    sbuild --chroot-setup-commands='/home/findunusedbd.sh chroot-setup' --starting-build-commands='/home/findunusedbd.sh starting-build' --finished-build-commands='/home/findunusedbd.sh finished-build'

get_metaset() {
	name=$1
	ver=$2
	ismeta="no"
	# now run all tests for meta package and skip to the end if package was
	# found to be a meta package by one of the methods
	# check for tag role::dummy and role::metapackage
	if [ $ismeta = "no" ]; then
		# we need grep-dctrl because the Tag field can be multi-line
		if apt-cache show --no-all-versions "${name}=${ver}" \
			| grep-dctrl -P "" -s Tag -n \
			| sed 's/, /\n/g; s/[, ]//g;' \
			| egrep '^(role::metapackage|role::dummy)$' \
			> /dev/null; then
			ismeta="yes"
		fi
	fi
	# check if there is any regular file in the package besides /usr/share/doc
	if [ $ismeta = "no" ]; then
		apt-get download "${name}=${ver}" > /dev/null
		# strip off architecture qualifier
		pkgname=`echo $name | cut -d ':' -f 1`
		mkdir "$pkgname"
		# we cannot include the version here because apt urlencodes the : character
		dpkg --extract ${pkgname}_*.deb $pkgname
		if [ -d ${pkgname}/usr/share/doc ]; then
			rm -r ${pkgname}/usr/share/doc
		fi
		# check if besides /usr/share/doc there is any regular file
		# in this package (symlinks do not count)
		if [ `find $pkgname -type f | wc -l` -eq 0 ]; then
			ismeta="yes"
		fi
		rm -r ${pkgname}_*.deb $pkgname
	fi
	if [ $ismeta = "yes" ]; then
		# retrieve all its unversioned dependencies
		# we already require grep-dctrl above so we can use it now too
		apt-cache depends --important --installed "${name}=${ver}" \
			| awk ' $1 ~ /\|?(Depends|PreDepends):/ { print $2; }'
	fi
	# output this package as well in any case
	echo $name
}

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
		starting-build)
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
				# skip all sbuild dummy packages
				case $name in
					sbuild-build-depends*) continue;;
				esac
				if grep --line-regexp "${name}=${ver}" "${tmpdir}/bdselection.list"; then
					# if the package contains no other files than in /usr/share/doc
					# or if all the other files are symlinks
					# or if it is tagged role::dummy
					# or if it is tagged role::metapackage
					# then it is a meta package and we append to the file it contains
					# the files contained by the packages it depends upon
					get_metaset $name $ver | sort | uniq \
						| while read pkgname; do
							dpkg --listfiles $pkgname
						done | sort | uniq \
						> "${tmpdir}/${name}=${ver}"
				fi
			done
			# find sbuild dummy package name
			dummypkgname=`dpkg --get-selections | awk '{ print $1; }' \
				| grep sbuild-build-depends \
				| grep -v sbuild-build-depends-core-dummy \
				| grep -v sbuild-build-depends-essential-dummy \
				| grep -v sbuild-build-depends-lintian-dummy`
			# output the dependencies of the sbuild dummy package
			# we use apt to show dependencies because we do not want
			# disjunctions or purely virtual packages to be in the output
			apt-cache depends --important --installed $dummypkgname \
				| awk ' $1 ~ /\|?(Depends|PreDepends):/ { print $2; }' \
				| sort \
				| uniq \
				> "${tmpdir}/sbuild-dummy-depends"
			# output the schroot id to start tracing
			echo $SCHROOT_SESSION_ID > "${tmpdir}/myfifo"
			# wait for fatrace to be forked
			cat "${tmpdir}/myfifo" > /dev/null
			;;
		finished-build)
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
			name=`echo $namever | cut -d '=' -f 1 | cut -d ':' -f 1`
			ver=`echo $namever | cut -d '=' -f 2`
			# if the package contains no other files than in /usr/share/doc
			# or if all the other files are symlinks
			# or if it is tagged role::dummy
			# or if it is tagged role::metapackage
			# then it is a meta package and we also create fake equivs
			# packages for all packages it depends upon
			get_metaset $name $ver | sort | uniq \
				| while read pkgname; do
					# create and install a package with same name and version but without dependencies
					# removing Source: field because of bug#751942
					# we keep the Provides field because otherwise the new package might not
					# satisfy the dependency
					apt-cache show --no-all-versions $pkgname \
						| grep -v "^Pre-Depends:" \
						| grep -v "^Depends:" \
						| grep -v "^Recommends:" \
						| grep -v "^Suggests:" \
						| grep -v "^Conflicts:" \
						| grep -v "^Breaks:" \
						| grep -v "^Replaces:" \
						| grep -v "^Source:" \
						| equivs-build -
					# we use a wildcard because there should only be a single file anyways
					dpkg -i ${pkgname}_*.deb
					rm ${pkgname}_*.deb
				done
			# now that all fake packages are installed we need to
			# remove all those dependencies that are not needed anymore
			apt-get autoremove --assume-yes
			;;
		*)
			echo "invalid argument: $1" >&2
			;;
	esac
else
	echo "usage: " >&2
	echo "   $0 tmpdir"
	echo "   $0 [chroot-setup|starting-build|finished-build] tmpdir"
	echo "   $0 equivs pkgname"
	exit 1
fi
