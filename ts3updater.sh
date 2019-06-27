#!/bin/bash
# Script Name: ts3updater.sh
# Author: eminga, amended by Oekn5w
# Version: 1.6
# Description: Installs and updates TeamSpeak 3 servers
# License: MIT License

# change specific to your system
tsdir='/home/oekn5w/teamspeak3-server_linux_amd64'
startscript='/etc/init.d/teamspeak'
backupscript='tar -cjf /home/oekn5w/backup-$(date -I).tar.bz2 -C /home/oekn5w/teamspeak3-server_linux_amd64'

USER='Oekn5w'

cd "$(dirname "$0")" || exit 1

# check whether the dependencies curl, jq, and tar are installed
if ! command -v curl > /dev/null 2>&1; then
	echo 'curl not found' 1>&2
	exit 1
elif ! command -v jq > /dev/null 2>&1; then
	echo 'jq not found' 1>&2
	exit 1
elif ! command -v tar > /dev/null 2>&1; then
	echo 'tar not found' 1>&2
	exit 1
fi

# determine os and cpu architecture
os=$(uname -s)
if [ "$os" = 'Darwin' ]; then
	jqfilter='.macos'
else
	if [ "$os" = 'Linux' ]; then
		jqfilter='.linux'
	elif [ "$os" = 'FreeBSD' ]; then
		jqfilter='.freebsd'
	else
		echo 'Could not detect operating system. If you run Linux, FreeBSD, or macOS and get this error, please open an issue on Github.' 1>&2
		exit 1
	fi

	architecture=$(uname -m)
	if [ "$architecture" = 'x86_64' ] || [ "$architecture" = 'amd64' ]; then
		jqfilter="${jqfilter}.x86_64"
	else
		jqfilter="${jqfilter}.x86"
	fi
fi

# download JSON file which provides information on server versions and checksums
server=$(curl -Ls 'https://www.teamspeak.com/versions/server.json' | jq "$jqfilter")

# determine installed version by parsing the most recent entry of the CHANGELOG file
if [ -e "${tsdir}/CHANGELOG" ]; then
	old_version=$(grep -Eom1 'Server Release \S*' "${tsdir}/CHANGELOG" | cut -b 16-)
else
	old_version='-1'
fi

version=$(printf '%s' "$server" | jq -r '.version')

if [ "$old_version" != "$version" ]; then
	echo "New version available: $version"
	checksum=$(printf '%s' "$server" | jq -r '.checksum')
	links=$(printf '%s' "$server" | jq -r '.mirrors | values[]')

	# order mirrors randomly
	if command -v shuf > /dev/null 2>&1; then
		links=$(printf '%s' "$links" | shuf)
	fi

	tmpfile=$(su $USER -c "mktemp '${TMPDIR:-/tmp}/ts3updater.XXXXXXXXXX'")
	i=1
	n=$(printf '%s\n' "$links" | wc -l)

	# try to download from mirrors until download is successful or all mirrors tried
	while [ "$i" -le "$n" ]; do
		link=$(printf '%s' "$links" | sed -n "$i"p)
		echo "Downloading the file $link"
		su $USER -c "curl -Lo '$tmpfile' '$link'"
		if [ $? = 0 ]; then
			i=$(( n + 1 ))
		else
			i=$(( i + 1 ))
		fi
	done

	if command -v sha256sum > /dev/null 2>&1; then
		sha256=$(sha256sum "$tmpfile" | cut -b 1-64)
	elif command -v shasum > /dev/null 2>&1; then
		sha256=$(shasum -a 256 "$tmpfile" | cut -b 1-64)
	elif command -v sha256 > /dev/null 2>&1; then
		sha256=$(sha256 -q "$tmpfile")
	else
		echo 'Could not generate SHA256 hash. Please make sure at least one of these commands is available: sha256sum, shasum, sha256' 1>&2
		rm "$tmpfile"
		exit 1
	fi

	if [ "$checksum" = "$sha256" ]; then
		if [ -e "${tsdir}/ts3server_startscript.sh" ]; then
			# check if server is running
			if [ -e 'ts3server.pid' ]; then
				$startscript stop
			else
				server_stopped=true
			fi
		else
			echo 'given ts3 path is invalid'
			rm "$tmpfile"
			exit 1
		fi

		if [ "$backupscript" != "" ]; then
			su $USER -c "$backupscript"
		fi

		# extract the archive into the installation directory and overwrite existing files
		su $USER -c "tar --strip-components 1 -xf '$tmpfile' '$tsdir'"
		if [ "$1" != '--dont-start' ] && [ "$server_stopped" != true ]; then
			$startscript start
		fi
	else
		echo 'Checksum of downloaded file is incorrect!' 1>&2
		rm "$tmpfile"
		exit 1
	fi

	rm "$tmpfile"
else
	echo "The installed server is up-to-date. Version: $version"
fi
