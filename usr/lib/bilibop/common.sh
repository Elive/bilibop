# /usr/lib/bilibop/common.sh
#
# Copyright (C) 2011-2017, Yann Amar <quidame@poivron.org>
# License GPL-3.0+
#
# This program is free software: you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation, either version 3 of the License, or
# (at your option) any later version.
#
# This package is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public License
# along with this program. If not, see <http://www.gnu.org/licenses/>.
# Or write to the Free Software Foundation, Inc., 59 Temple Place,
# Suite 330, Boston, MA  02111-1307  USA.
#
# On Debian systems, the complete text of the GNU General
# Public License version 3 can be found in "/usr/share/common-licenses/GPL-3".


# For tests and debug purposes, set it to 'true':
[ "${DEBUG}" = "true" ] || DEBUG="false"

# README {{{
#
#> dm-crypt/LUKS, LVM, loopback, and aufs root filesystems (and combinations
#  of them) are now fully supported. Btrfs and overlay filesystems are also
#  partially supported (not fully tested).
#> Functions that just output information about devices/filesystems can be
#  called by any unprivileged user.

# Shell compatibility ======================================================={{{
# The bilibop-common shell functions use a lot of variable subtitutions and
# builtin commands. Some of them can not work with some shells. The functions
# have been tested:
# 1. with a lot of multilayer settings (combinations of LVM, LUKS, loop and
#    aufs)
# 2. by running the following script (where ${SHELL} is replaced by /bin/dash,
#    /bin/bash, /bin/sash -f, /bin/posh, /bin/busybox sh, /bin/ksh, /bin/zsh,
#    or /usr/lib/klibc/bin/sh.shared, etc.):
# ----------
# #!${SHELL}
# . /usr/lib/bilibop/common.sh ; physical_hard_disk
# ----------
# 3. by running the previous script with /bin/sh as ${SHELL} and linking
#    /bin/sh successively to dash, bash, sash, posh, busybox, ksh, zsh, or
#    /usr/lib/klibc/bin/sh.shared, etc.
#
# This has been tested and works with:
# - /bin/bash
# - /bin/dash
# - /bin/busybox sh
# - /usr/lib/klibc/bin/sh.shared
# which are the default available shells on a Debian system (bash, dash) and
# its initramdisk built with initramfs-tools (busybox sh, klibc sh.shared).
#
# And also works with:
# - /bin/mksh
# - /bin/mksh-static
# - /bin/bash-static
# - /bin/posh
# - /bin/zsh4
#
# This has been tested and works under certain conditions with:
# - /bin/sash       Works when the script begins with #!/bin/sash -f, but not
#                   when it begins with #!/bin/sh and /bin/sh is linked to
#                   sash.
#
# This has been tested and don't work with:
# - /bin/pdksh      (this shell has no 'printf' builtin)
# - /bin/ksh93      (this shell has no 'local' builtin)
# - /usr/bin/yash   (this shell has no 'local' builtin, and '[' is not
#                   implemented when the shell is called as 'sh'; and in all
#                   cases, yash being in /usr/bin, it should be considered as
#                   unusable for bilibop purposes)
#
# Because the 'echo' builtin command is not samely implemented in all shells
# (especially the '-e' option is implicit in dash's echo), we never use this
# command with options, and never use escaped characters (\t, \n, \c...) in
# the string to echo.
# }}}
# Needed external commands: ================================================={{{
# Here is a table of external GNU commands used in the following functions.
# Some of them having different options and behaviors when they are provided
# by 'busybox' or 'klibc', we note here which are working or not in the context
# of these functions (this is a base to write an initramfs-tools hook). 'YES'
# means it works, 'NO' means it don't, and '-' means it is not provided.
#
# GNU tools                 busybox builtins                klibc commands
# ------------------------------------------------------------------------------
# /bin/cat                  YES                             YES
# /bin/df                   YES                             -
# /bin/grep                 YES                             -
# /bin/readlink             YES                             NO
# /bin/sed                  YES                             -
# /bin/udevadm              -                               -
#
# Now we can say:
# - there is no need to add 'cat'.
# - 'udevadm' must be added (we assume udev provides a hook to do that).
# - if 'busybox' is not added into the initramdisk, we have to use the 'df',
#   'grep', 'readlink' and 'sed' GNU commands.
#   So, if busybox is not available into the initramdisk:
#   * add 'df', 'grep' and 'sed'
#   * replace the klibc's 'readlink' by the GNU one
#
# }}}
# Needed files: ============================================================={{{
# To run correctly, the bilibop functions need to read information into some
# virtual files or directory, especially:
#
# /dev/* (or /dev/*)
# /dev/block/*
# /proc/cmdline
# /proc/filesystems
# /proc/mounts
# /proc/partitions
# /sys/block/sd?/removable
# /sys/block/dm-?/slaves
# /sys/block/loop?*/loop/backing_file
# /sys/class/block/*/dev
# /sys/fs/aufs/si_*/br?
#
# So we assume that /dev, /proc and /sys are mounted. If you have to use this
# file from into a chrooted environment, you have to do something like that:
#
# # mount DEVICE /mnt
# # mount -t sysfs -o nodev,noexec,nosuid sysfs /mnt/sys
# # mount -t proc -o nodev,noexec,nosuid proc /mnt/proc
# # mount -t devtmpfs -o mode=0755 udev /mnt/dev
# and optionally:
# # mount -t tmpfs -o nosuid,nodev tmpfs /mnt/tmp
# # mount -t tmpfs -o nosuid,size=10%,mode=0755 tmpfs /mnt/run
# # mkdir -p /mnt/dev/pts /mnt/run/lock /mnt/run/shm
# # mount -t devpts -o noexec,nosuid,gid=5,mode=0620 devpts /mnt/dev/pts
# # mount -t tmpfs -o noexec,nodev,nosuid,size=10% tmpfs /mnt/run/lock
# # mount -t tmpfs -o nosuid,nodev tmpfs /mnt/run/shm
# and finally:
# # chroot /mnt
# }}}

# }}}

# bilibop_common_functions() ================================================{{{
# What we want is: output a list of useful bilibop functions, to use them
# manually.
bilibop_common_functions() {
    cat >&2 <<EOF
aufs_dirs <MOUNTPOINT>
aufs_mountpoints
aufs_readonly_branch <MOUNTPOINT>
aufs_writable_branch <MOUNTPOINT>
backing_file_from_loop <DEVICE>
device_nodes
device_node_from_major_minor <MAJ:MIN>
device_id_of_file <FILE|DIR>
find_mountpoint <FILE|DIR>
get_biliop_variables
is_aufs_mountpoint [-q] <MOUNTPOINT>
is_btrfs_mountpoint [-q] <MOUNTPOINT>
is_overlay_mountpoint [-q] <MOUNTPOINT>
is_removable <DEVICE>
mapper_name_from_dm_node <DEVICE>
major_minor_from_device_node <DEVICE>
overlay_mountpoints
overlay_lowerdir <MOUNTPOINT>
overlay_upperdir <MOUNTPOINT>
overlay_workdir <MOUNTPOINT>
physical_hard_disk [FILE|DIR|DEVICE]
query_sysfs_attrs <DEVICE>
query_udev_envvar <DEVICE>
underlying_device <FILE|DIR|DEVICE>
underlying_device_from_aufs <MOUNTPOINT>
underlying_device_from_btrfs <MOUNTPOINT>
underlying_device_from_overlayfs <MOUNTPOINT>
underlying_device_from_device <DEVICE>
underlying_device_from_dm <DEVICE>
underlying_device_from_file <FILE|DIR>
underlying_device_from_loop <DEVICE>
underlying_partition <FILE|DIR|DEVICE>
EOF
}
# ===========================================================================}}}

### INTERNAL FUNCTIONS ###
### The following functions can be called by others in this file, except the
### last one, 'physical_hard_disk'.
### Here is the main function's dependency tree {{{
#
# physical_hard_disk
# |__underlying_partition
#    |__underlying_device
#    |  |__underlying_device_from_device
#    |  |  |__underlying_device_from_dm
#    |  |  |__underlying_device_from_loop
#    |  |     |__backing_file_from_loop
#    |  |     |__device_id_of_file
#    |  |     |__underlying_device_from_file __ see below
#    |  |     |__device_node_from_major_minor   vvvvvvvvv
#    |  |
#    |  |__underlying_device_from_file _<<_<<_<<_  possible loop entry point
#    |     |__device_id_of_file                  |
#    |     |__find_mountpoint                    |
#    |     |__is_aufs_mountpoint                 |
#    |     |  |__canonical                       |
#    |     |                                     |
#    |     |__underlying_device_from_aufs        |
#    |     |  |__aufs_readonly_branch            |
#    |     |  |  |__aufs_dirs_if_brs0            |
#    |     |  |  |  |__is_aufs_mountpoint        |
#    |     |  |  |     |__canonical              |
#    |     |  |  |                               |
#    |     |  |  |__aufs_si_directory            |
#    |     |  |     |__is_aufs_mountpoint        |
#    |     |  |        |__canonical              |
#    |     |  |                                  |
#    |     |  |__device_id_of_file               |
#    |     |  |__underlying_device_from_file _>>_| possible loop entry point
#    |     |  |__device_node_from_major_minor    |
#    |     |                                     |
#    |     |__is_overlay_mountpoint              |
#    |     |  |__canonical                       |
#    |     |                                     |
#    |     |__underlying_device_from_overlayfs   |
#    |     |  |__overlay_lowerdir                |
#    |     |  |  |__is_overlay_mountpoint        |
#    |     |  |  |  |__canonical                 |
#    |     |  |  |                               |
#    |     |  |  |__canonpath                    |
#    |     |  |                                  |
#    |     |  |__device_id_of_file               |
#    |     |  |__underlying_device_from_file _>>_| possible loop entry point
#    |     |  |__device_node_from_major_minor
#    |     |
#    |     |__is_btrfs_mountpoint
#    |     |  |__canonical
#    |     |
#    |     |__underlying_device_from_btrfs
#    |     |__device_node_from_major_minor
#    |
#    |__underlying_device_from_device
#       |__underlying_device_from_dm
#       |__underlying_device_from_loop
#          |__backing_file_from_loop
#          |__device_id_of_file              ^^^^^^^^^
#          |__underlying_device_from_file __ see above
#          |__device_node_from_major_minor
#
# }}}

# canonical() ==============================================================={{{
# What we want is: remove trailing slash of a directory name (to match with the
# /proc/mounts mountpoints, between others). Another solution? Maybe:
# local arg="${1%/}"; echo "${arg:-/}"
# But this is a little bit different: if $1 is empty, the output is "/". Try
# again.
canonical() {
    ${DEBUG} && echo "> canonical $@" >&2
    case    "${1}" in
        /)  echo "/" ;;
        *)  echo "${1%/}" ;;
    esac
}
# ===========================================================================}}}
# canonpath() ==============================================================={{{
# What we want is: canonicalize a pathname even if the file (and even its
# parent directories) does not exist. Just do not try to resolve any part of
# the path; instead, rely only on path separators and specific patterns that
# allow us to logically shorten the path.
canonpath() {
    ${DEBUG} && echo "> canonpath $@" >&2
    local pathname
    case "${1}" in
        "") return 0;;
        /*) pathname="${1}";;
        *)  pathname="${PWD}/${1}";;
    esac
    while true; do
        case "${pathname}" in
            *//*|*/./*|*/../*|*/|*/.|*/..)
                pathname="$(echo "${pathname}" | sed -re 's,(/+\.?)+/+,/,g; s,^(/+\.\.)+(/+|$),/,; s,[^/]+/+\.\.(/+|$),/,; s,/+,/,g; s,(/+\.?)+$,,')"
                ;;
            "")
                echo "/"
                break
                ;;
            *)
                echo "${pathname}"
                break
                ;;
        esac
    done
}
# ===========================================================================}}}
# find_mountpoint() ========================================================={{{
# What we want is: output the mountpoint of the filesystem the file or directory
# given as argument depends is onto. Because it outputs the last field of the
# last line of the 'df' output, df don't need the '-P' (POSIX format) option,
# and so we are sure it works with all df commands or builtins (busybox).
# The use of directories is to work around overlayfs design (files and dirs are
# not treated the same way, see "stat inconsistency with overlayfs" thread in
# http://www.spinics.net/lists/linux-unionfs/index.html#00197). In my tests,
# the only one case where replacing a file path by its dirname may affect the
# result of df, stat... is for bind-mounted files (and when the two files are
# not on the same fs).
find_mountpoint() {
    ${DEBUG} && echo "> find_mountpoint $@" >&2
    if      [ -d "${1}" ]
    then    df "${1}"
    else    df "${1%/*}"
    fi |
    sed -ne '$s,.* \([^[:blank:]]\+\)$,\1,p'
}
# ===========================================================================}}}
# device_node_from_major_minor() ============================================{{{
# What we want is: translate the 'major:minor' given as argument to the
# corresponding device node. What is the best way?
device_node_from_major_minor() {
    ${DEBUG} && echo "> device_node_from_major_minor $@" >&2
    local dev="$(readlink -f /sys/dev/block/${1})"
    [ -b "/dev/${dev##*/}" ] && echo "/dev/${dev##*/}"
}
# ===========================================================================}}}
# device_id_of_file() ======================================================={{{
# What we want is: output the major:minor of the filesystem containing the
# file or directory given as argument. See the 'find_mountpoint()' function
# above, and its comments about "stat inconsistency with overlayfs".
device_id_of_file() {
    ${DEBUG} && echo "> device_id_of_file $@" >&2
    if      [ -d "${1}" ]
    then    udevadm info --device-id-of-file "${1}"
    else    udevadm info --device-id-of-file "${1%/*}"
    fi
}
# ===========================================================================}}}
# is_btrfs_mountpoint() ====================================================={{{
# What we want is: check if a directory given as argument is a btrfs mountpoint
# and print the corresponding line from /proc/mounts. Accepts the '-q' (quiet)
# option: print nothing, but return a 0/1 exit value. This is due to the fact
# that btrfs mountpoints get 0 as their major device ID.
is_btrfs_mountpoint() {
    ${DEBUG} && echo "> is_btrfs_mountpoint $@" >&2
    local   opt=
    case    "${1}" in
        -*)
            opt="${1}"
            shift ;;
    esac
    grep ${opt} "^[^ ]\+ $(canonical ${1}) btrfs " /proc/mounts
}
# ===========================================================================}}}
# is_aufs_mountpoint() ======================================================{{{
# What we want is: check if a directory given as argument is an aufs mountpoint
# and print the corresponding line from /proc/mounts. Accepts the '-q' (quiet)
# option: print nothing, but return a 0/1 exit value.
is_aufs_mountpoint() {
    ${DEBUG} && echo "> is_aufs_mountpoint $@" >&2
    local   opt=
    case    "${1}" in
        -*)
            opt="${1}"
            shift ;;
    esac
    grep ${opt} "^[^ ]\+ $(canonical ${1}) aufs " /proc/mounts
}
# ===========================================================================}}}
# aufs_si_directory() ======================================================={{{
# What we want is: output the sysfs directory where information can be found
# about an aufs mount point given as argument.
aufs_si_directory() {
    ${DEBUG} && echo "> aufs_si_directory $@" >&2
    is_aufs_mountpoint "${1}" | sed -e 's|.*si=\([^ ,]\+\).*|/sys/fs/aufs/si_\1|'
}
# ===========================================================================}}}
# aufs_dirs_if_brs0() ======================================================={{{
# What we want is: output all the underlying mountpoints (called branches) an
# aufs filesystem given as argument is made of, by parsing /proc/mounts. This
# needs aufs module loaded with brs=0 parameter (not the default).
aufs_dirs_if_brs0() {
    ${DEBUG} && echo "> aufs_dirs_if_brs0 $@" >&2
    is_aufs_mountpoint "${1}" | sed -e 's@.*[ ,]br:\([^ ,]\+\).*@\1@ ; s@:@ @g'
}
# ===========================================================================}}}
# aufs_readonly_branch() ===================================================={{{
# What we want is: output the lower (readonly) branch of an aufs mount point
# given as argument.
aufs_readonly_branch() {
    ${DEBUG} && echo "> aufs_readonly_branch $@" >&2
    local   br
    case  "$(cat /sys/module/aufs/parameters/brs)" in
        0)
            for br in $(aufs_dirs_if_brs0 "${1}")
            do
                echo ${br} | grep -q '=r[or]\(+wh\)\?$' &&
                echo ${br%\=r*}
            done
            ;;
        *)
            for br in $(aufs_si_directory "${1}")/br?
            do
                grep '=r[or]\(+wh\)\?$' ${br} | sed -e 's,=r[or].*,,'
            done
            ;;
    esac
}
# ===========================================================================}}}
# is_overlay_mountpoint() ==================================================={{{
# What we want is: check if a directory given as argument is an overlayfs
# mountpoint and print the corresponding line from /proc/mounts. Accepts the
# '-q' (quiet) option: print nothing, but return a 0/1 exit value.
is_overlay_mountpoint() {
    ${DEBUG} && echo "> is_overlay_mountpoint $@" >&2
    local   opt=
    case    "${1}" in
        -*)
            opt="${1}"
            shift ;;
    esac
    grep ${opt} "^[^ ]\+ $(canonical ${1}) overlay " /proc/mounts
}
# ===========================================================================}}}
# overlay_lowerdir() ========================================================{{{
# What we want is: output the lowerdir (readonly branch) of an overlayfs mount
# point given as argument.
overlay_lowerdir() {
    ${DEBUG} && echo "> overlay_lowerdir $@" >&2
    canonpath $(is_overlay_mountpoint "${1}" | sed -e 's@.*[ ,]lowerdir=\([^ ,]\+\).*@\1@ ; s@/\+@/@g')
}
# ===========================================================================}}}
# backing_file_from_loop() =================================================={{{
# What we want is: output the backing file of a loopback device given as
# argument. This requires kernel >= 2.6.37. Great thing! Before that, it was
# necessary to call losetup (as root) and parse its output, with possible
# failures: the filename is truncated (currently 64 characters) and even,
# depending on the version of the command or its implementation, it can be
# relative to the directory from where the command was called to setup the
# device... an other solution is to parse the output of losetup and use
# the major:minor of the device and the inode number of the file to find it.
# Pfff! See now:
backing_file_from_loop() {
    ${DEBUG} && echo "> backing_file_from_loop $@" >&2
    [ -f /sys/block/${1##*/}/loop/backing_file ] &&
    cat /sys/block/${1##*/}/loop/backing_file
}
# ===========================================================================}}}
# underlying_device_from_loop() ============================================={{{
# What we want is: output the underlying device of a loop device given as
# argument. If the loop device is associated to a block device, then output it;
# otherwise, find the device from its major:minor numbers. This function has
# been entirely rewritten to not depend on losetup, but requires kernel version
# >= 2.6.37.
underlying_device_from_loop() {
    ${DEBUG} && echo "> underlying_device_from_loop $@" >&2
    local   lofile="$(backing_file_from_loop ${1})" || return 1
    if      [ -b "${lofile}" ]
    then    readlink -f "${lofile}"
    else
            local   id
            if      [ -e "${lofile}" ]
            then    id=$(device_id_of_file "${lofile}")
            elif    [ -r "${1}" ]
            then    # For some cases, when the loop device is set from inside
                    # the initramfs (Live Systems) and /sys/*/loop/backing_file
                    # is out of sync
                    local   dev="$(/sbin/losetup ${1} | sed "s;^${1}: \[\([0-9a-f]\{4\}\)\].*;\1;")"
                    id="$((0x${dev}/256)):$((0x${dev}%256))"
            else    return 1
            fi
            case    "${id}" in
                "")
                    return 1
                    ;;
                0:*)
                    underlying_device_from_file "${lofile}"
                    ;;
                *)
                    device_node_from_major_minor "${id}"
                    ;;
            esac
    fi
}
# ===========================================================================}}}
# underlying_device_from_aufs() ============================================={{{
# What we want is: output the underlying device of the (generally) readonly
# branch of an aufs mountpoint given as argument. We assume that there is only
# and at least one physical device used to build the aufs (but the directory
# is not necessarly the mountpoint of this device), other branch(s) being
# virtual fs. Note that if there are more than one readonly branch, the first
# block device found wins.
underlying_device_from_aufs() {
    ${DEBUG} && echo "> underlying_device_from_aufs $@" >&2
    local dev dir
    for dir in $(aufs_readonly_branch "${1}"); do
        dev="$(device_id_of_file "${dir}")"
        case "${dev}" in
            "")
                continue
                ;;
            0:*)
                # aufs mounts can't be nested; but this may be btrfs
                dev="$(underlying_device_from_file "${dir}")"
                ;;
            *)
                dev="$(device_node_from_major_minor "${dev}")"
                ;;
        esac
        if [ -b "${dev}" ]; then
            readlink -f "${dev}"
            return 0
        fi
    done
    return 1
}
# ===========================================================================}}}
# underlying_device_from_overlayfs() ========================================{{{
# What we want is: output the underlying device of the (generally) readonly
# branch of an overlayfs mountpoint given as argument. We assume that there is
# only and at least one physical device used to build the overlayfs (but the
# directory is not necessarly the mountpoint of this device), other branch(es)
# being virtual fs.
underlying_device_from_overlayfs() {
    ${DEBUG} && echo "> underlying_device_from_overlayfs $@" >&2
    local   dev dir="$(overlay_lowerdir "${1}")"

    # First case: overlayfs mountpoint is set at runtime, so the lowerdir
    # value is up-to-date. Think that when setting up overlayfs mountpoint
    # from the initramdisk environment, using same pathnames than what they
    # will be at runtime may ease the task.
    if [ -d "${dir}" ] && grep -q "^/[^ ]\+ ${dir} " /proc/mounts; then
        dev="$(device_id_of_file ${dir})"
    else
        # overlayfs mountpoint has been set at boottime (within the initrd env)
        # and the value of 'lowerdir' found in /proc/mounts is obsolete. There
        # is no safe way to know the current and actual lowerdir mountpoint. We
        # have to assume some arbitrary conditions to take a chance to find the
        # underlying device. This depends on arbtrary paths used in initrd
        # scripts (tested with live-boot 5.0~a1-1 - experimental)
        # First fallback: rely on the lowerdir's basename
        dir="$(grep '^/' /proc/mounts | sed -e 's|^[^ ]\+ \([^ ]\+\) .*|\1|' | grep "/${dir##*/}$")"
        if [ -d "${dir}" ]; then
            dev="$(device_id_of_file ${dir})"
        fi
    fi
    case "${dev}" in
        "")
            ;;
        0:*)
            dev="$(underlying_device_from_file "${dir}")"
            ;;
        *)
            dev="$(device_node_from_major_minor "${dev}")"
            ;;
    esac

    [ -b "${dev}" ] && readlink -f "${dev}"
}
# ===========================================================================}}}
# underlying_device_from_btrfs() ============================================{{{
# What we want is: output the underlying device of a btrfs mountpoint given as
# argument. Such filesystems are not directly mapped to the block device they
# are written on: the device ID (major:minor) of a file on btrfs is not the
# same than the block device itself (say 8:1 for /dev/sda1), but a virtual one
# (with 0 as the major number).
underlying_device_from_btrfs() {
    ${DEBUG} && echo "> underlying_device_from_btrfs $@" >&2
    local dev="$(grep "^/[^[:blank:]]\+\s${1}\sbtrfs\s" /proc/mounts | sed -e 's|^\([^ ]\+\)\s.*|\1|')"
    [ -b "${dev}" ] && readlink -f "${dev}"
}
# ===========================================================================}}}
# underlying_device_from_dm() ==============================================={{{
# What we want is: output the underlying device of a dm device given as
# argument. This function has been rewritten to not depend on dmsetup, grep and
# sed. A loop is now used to output the final underlying device, not just the
# parent device (for example for LUKS/LVM combinations). The output will be of
# the form /dev/sdXN or /dev/loopN. As for the aufs, we assume that the scheme
# is very simple, and there is only and at least one slave device per dm device
# (this is the case for bilibop: because it runs from an external media, RAID
# is not used as the root filesystem, and if LVM is used, this is to create
# several LV in a VG, not several PV in a VG).
underlying_device_from_dm() {
    ${DEBUG} && echo "> underlying_device_from_dm $@" >&2
    local   slave dev="$(readlink -f "${1}")"
    dev="${dev##*/}"
    while   true
    do
        case    "${dev}" in
            dm-*)
                #slave="$(parent_device_from_dm /dev/${dev})"
                slave="$(echo /sys/block/${dev}/slaves/*)"
                [ "${slave}" = "/sys/block/${dev}/slaves/*" ] && return 3
                dev="${slave##*/}"
                ;;
            *)
                echo "/dev/${dev}"
                return 0
                ;;
        esac
    done
}
# ===========================================================================}}}
# underlying_device_from_device() ==========================================={{{
# What we want is: find the underlying device of a device (dm-crypt, loop or
# LVM) given as argument. This function can be included into a loop to finally
# output a device name that has no parent/underlying device, i.e a partition.
underlying_device_from_device() {
    ${DEBUG} && echo "> underlying_device_from_device $@" >&2
    local   dev="${1}"
    case    "${dev}" in
        /dev/dm-[0-9]*)
            underlying_device_from_dm "${dev}"
            ;;
        /dev/loop[0-9]*)
            underlying_device_from_loop "${dev}"
            ;;
        /dev/*)
            readlink -f "${dev}"
            ;;
        *)
            return 1
    esac
}
# ===========================================================================}}}
# underlying_device_from_file() ============================================={{{
# What we want is: output the filesystem containing a file given as argument,
# even if the filesystem is mounted as the lower branch of an aufs mountpoint.
underlying_device_from_file() {
    ${DEBUG} && echo "> underlying_device_from_file $@" >&2
    local   id="$(device_id_of_file "${1}")" dev mntpnt
    if      [ "${id%:*}" = "0" ]
    then
            # 0 is the major number of all ramfs (tmpfs, devtmpfs, sysfs, proc
            # and others). If the file is hosted on a such virtual filesystem,
            # we encounter an alternative: the file is on aufs/overlay/btrfs
            # and we continue after a jump on the real block device under the
            # aufs/overlay/btrfs, or we stop there.
            mntpnt="$(find_mountpoint "${1}")"
            if      is_aufs_mountpoint -q "${mntpnt}"
            then    dev="$(underlying_device_from_aufs "${mntpnt}")"
            elif    is_overlay_mountpoint -q "${mntpnt}"
            then    dev="$(underlying_device_from_overlayfs "${mntpnt}")"
            elif    is_btrfs_mountpoint -q "${mntpnt}"
            then    dev="$(underlying_device_from_btrfs "${mntpnt}")"
            fi
    else
            dev="$(device_node_from_major_minor "${id}")"
    fi

    [ -b "${dev}" ] && readlink -f "${dev}"
}
# ===========================================================================}}}
# underlying_device() ======================================================={{{
# What we want is: output the underlying device node of a file/directory or
# block device given as argument. All is explained in the previous functions.
# The question here is to know what to do with the symlinks: follow them, or
# not? For a lot of them, there is no importance, but for something as /etc/mtab
# linked to /proc/mounts, this makes a big difference. For the moment, we have
# choosen to not follow them... Maybe we have to clean some other function in
# the same sense.
# NEWS: the 'find_mountpoint' function uses df which operates on the pointed
# file, not on the symlink.
underlying_device() {
    ${DEBUG} && echo "> underlying_device $@" >&2
    local   dev target="${1}"

    if      [ -b "${target}" ]
    then
            dev="$(underlying_device_from_device "${target}")"

    elif    [ -f "${target}" -o -d "${target}" ]
    then
            dev="$(underlying_device_from_file "${target}")"
    fi

    if      [ -b "${dev}" ]
    then    echo "${dev}"
    else    return 3
    fi
}
# ===========================================================================}}}
# underlying_partition() ===================================================={{{
# What we want is: output the partition which the device, or directory, or
# file given as argument is on. With this simple loop, supports combinations
# of mapped devices (LVM, dm-crypt), loopback devices and aufs filesystems.
underlying_partition() {
    ${DEBUG} && echo "> underlying_partition $@" >&2
    local   old new="$(underlying_device "${1}")"

    while   true
    do
        case "${new}" in
            "")
                return 1
                ;;
            "/dev"/sd[a-z]*)
                echo "${new}"
                return 0
                ;;
            "${old}")
                echo "${new}"
                return 0
                ;;
        esac
        old="${new}"
        new="$(underlying_device_from_device "${old}")"
    done
}
# ===========================================================================}}}
# physical_hard_disk() ======================================================{{{
# What we want is: output the physical hard disk node of a device, file or
# directory given as argument. The main usage is: 'physical_hard_disk /', or
# just 'physical_hard_disk'. The thing to do here is to find the whole disk
# name after 'underlying_partition' has given the partition name.
physical_hard_disk() {
    ${DEBUG} && echo "> physical_hard_disk $@" >&2
    [ -z "${1}" ] && eval set -- /
    local   blk dev disk=

    if      [ -b "${1}" -a -e "/sys/class/block/${1##*/}" -a ! -e "/sys/devices/virtual/block/${1##*/}" ]
    then    dev="${1}"
    else    dev="$(underlying_partition "${1}")"
    fi

    for blk in /sys/block/*
    do
        blk="${blk##*/}"
        case    "${blk}" in
            dm-*|loop*|ram*)
                continue ;;
        esac

        case    "${dev}" in
            /dev/${blk}*)
                disk="/dev/${blk}"
                break
                ;;
        esac
    done

    if      [ -b "${disk}" ]
    then    echo "${disk}"
    elif    [ "${1}" = "/" ]
    then    return 127
    else    # If the argument is a file/directory in a virtual fs, there is no
            # way to find its hosting block device name. It don't exist. This
            # seems simple, but how to manage other cases?
            return 3
    fi
}
# ===========================================================================}}}


### OTHER FUNCTIONS ###
### only called from other scripts (from bilibop-lockfs and bilibop-rules, and
### maybe others).

# unknown_argument() ========================================================{{{
# A general error message for helper scripts.
unknown_argument() {
    ${DEBUG} && echo "> unknown_argument $@" >&2
    cat <<EOF
${0##*/}: unrecognized argument (${1}).
EOF
}
# ===========================================================================}}}
# required_argument() ======================================================={{{
# An other error message for helper scripts.
required_argument() {
    ${DEBUG} && echo "> required_argument $@" >&2
    cat <<EOF
${0##*/}: argument is required.
EOF
}
# ===========================================================================}}}

# get_bilibop_variables() ==================================================={{{
# What we want is: get bilibop variables from its configuration file if it
# exists, and set/overwrite the most important of them (BILIBOP_RUNDIR). If not
# existing, BILIBOP_COMMON_BASENAME is set to 'bilibop'.
# This function can be called from into the running system, or from into the
# initramdisk. In this case, the mountpoint of the future root filesystem
# (${rootmnt}) must be given as argument.
get_bilibop_variables() {
    ${DEBUG} && echo "> get_bilibop_variables $@" >&2
    if      [ -f ${1}/etc/bilibop/bilibop.conf ]
    then    . ${1}/etc/bilibop/bilibop.conf
    fi
    BILIBOP_RUNDIR="/run/${BILIBOP_COMMON_BASENAME:=bilibop}"
}
# ===========================================================================}}}
# get_aufs_variables() ======================================================{{{
# What we want is: set the default aufs variables (used by the aufs tools) and
# override them by the admin settings, just as do the aufs tools.
get_aufs_variables() {
    ${DEBUG} && echo "> get_aufs_variables $@" >&2
    AUFS_SUPER_MAGIC="1635083891"
    AUFS_SUPER_MAGIC_HEX="0x61756673"
    AUFS_WH_PFX=".wh."
    AUFS_WH_PFX2=".wh..wh."
    AUFS_WH_BASE=".wh..wh.aufs"
    AUFS_WH_DIROPQ=".wh..wh..opq"
    AUFS_WH_PLINKDIR=".wh..wh.plnk"
    AUFS_WH_ORPHDIR=".wh..wh.orph"
    if      [ -f /etc/default/aufs ]
    then    . /etc/default/aufs
    fi
}
# ===========================================================================}}}

# aufs_dirs() ==============================================================={{{
# What we want is: output all the underlying mountpoints (called branches) an
# aufs filesystem given as argument is made of.
aufs_dirs() {
    ${DEBUG} && echo "> aufs_dirs $@" >&2
    local   br
    case  "$(cat /sys/module/aufs/parameters/brs)" in
        0)
            for br in $(aufs_dirs_if_brs0 "${1}")
            do
                echo ${br}
            done
            ;;
        *)
            for br in $(aufs_si_directory "${1}")/br?
            do
                cat ${br}
            done
            ;;
    esac
}
# ===========================================================================}}}
# aufs_mountpoints() ========================================================{{{
# What we want is: output the mountpoints of all aufs filesystems.
aufs_mountpoints() {
    ${DEBUG} && echo "> aufs_mountpoints $@" >&2
    grep '^[^ ]\+ /[^ ]* aufs .*[, ]si=[0-9a-f]\+[, ].*' /proc/mounts |
    sed -e 's,^[^ ]\+ \(/[^ ]*\) aufs .*,\1,'
}
# ===========================================================================}}}
# aufs_writable_branch() ===================================================={{{
# What we want is: output the upper (read-write) branch of an aufs mount point
# given as argument.
aufs_writable_branch() {
    ${DEBUG} && echo "> aufs_writable_branch $@" >&2
    local   br
    case  "$(cat /sys/module/aufs/parameters/brs)" in
        0)
            for br in $(aufs_dirs_if_brs0 "${1}")
            do
                echo ${br} | grep -q '=rw\(+nolwh\)\?$' &&
                echo ${br%\=rw*}
            done
            ;;
        *)
            for br in $(aufs_si_directory "${1}")/br?
            do
                grep '=rw\(+nolwh\)\?$' ${br} | sed -e 's,=rw.*,,'
            done
            ;;
    esac
}
# ===========================================================================}}}

# overlay_mountpoints() ====================================================={{{
# What we want is: output the mountpoints of all overlay filesystems.
overlay_mountpoints() {
    ${DEBUG} && echo "> overlay_mountpoints $@" >&2
    grep '^[^ ]\+ /[^ ]* overlay .*[, ]lowerdir=/.\+[, ].*' /proc/mounts |
    sed -e 's,^[^ ]\+ \(/[^ ]*\) overlay .*,\1,'
}
# ===========================================================================}}}
# overlay_upperdir() ========================================================{{{
# What we want is: output the upperdir (writable branch) of an overlayfs mount
# point given as argument.
overlay_upperdir() {
    ${DEBUG} && echo "> overlay_upperdir $@" >&2
    canonpath $(is_overlay_mountpoint "${1}" | sed -e 's@.*[ ,]upperdir=\([^ ,]\+\).*@\1@ ; s@/\+@/@g')
}
# ===========================================================================}}}
# overlay_workdir() ========================================================={{{
# What we want is: output the upperdir (writable branch) of an overlayfs mount
# point given as argument.
overlay_workdir() {
    ${DEBUG} && echo "> overlay_workdir $@" >&2
    canonpath $(is_overlay_mountpoint "${1}" | sed -e 's@.*[ ,]workdir=\([^ ,]\+\).*@\1@ ; s@/\+@/@g')
}
# ===========================================================================}}}

# is_removable() ============================================================{{{
# What we want is: check if a whole disk node given as argument is seen as
# removable from its sysfs attribute. If yes, this means the disk given as
# argument is an USB stick (or a CD/DVD).
is_removable() {
    ${DEBUG} && echo "> is_removable $@" >&2
    [ "$(cat /sys/block/${1##*/}/removable)" = "1" ]
}
# ===========================================================================}}}
# is_readonly() ============================================================={{{
# What we want is: check if a block device given as argument is writable.
is_readonly() {
    ${DEBUG} && echo "> is_readonly $@" >&2
    [ "$(cat /sys/class/block/${1##*/}/ro)" = "1" ]
}
# ===========================================================================}}}

# device_nodes() ============================================================{{{
# What we want is: output the list of device nodes from /proc/partitions.
device_nodes() {
    ${DEBUG} && echo "> device_nodes $@" >&2
    grep '[[:digit:]]' /proc/partitions | sed 's,.* \([^ ]\+\)$,\1,'
}
# ===========================================================================}}}
# extended_partition() ======================================================{{{
# What we want is: output the primary extended partition device node of a drive
# given as argument.
extended_partition() {
    ${DEBUG} && echo "> extended_partition $@" >&2
    local   part
    for     part in ${1}?*
    do
            case    "$(cat /sys/class/block/${part##*/}/partition)" in
                [1-4])
                    ID_PART_ENTRY_TYPE=
                    eval "$(query_udev_envvar ${part})"
                    case    "${ID_PART_ENTRY_TYPE}" in
                        0x5|0xf|0x85)
                            echo "${part}"
                            return 0
                            ;;
                        *)
                            continue
                            ;;
                    esac
                    ;;
                *)
                    return 1
                    ;;
            esac
    done
    return 1
}
# ===========================================================================}}}
# parent_device_from_dm() ==================================================={{{
# What we want is: output the direct parent device (slave) of a dm device given
# as argument.
parent_device_from_dm() {
    ${DEBUG} && echo "> parent_device_from_dm $@" >&2
    local   dev="$(readlink -f "${1}")"
    local   slave="$(echo /sys/block/${dev##*/}/slaves/*)"
    [ "${slave}" = "/sys/block/${dev##*/}/slaves/*" ] && return 3
    echo "/dev/${slave##*/}"
}
# ===========================================================================}}}
# mapper_name_from_dm_node() ================================================{{{
# What we want is: output the basename (in /dev/mapper) of a dm device node
# (dm-*) given as argument.
mapper_name_from_dm_node() {
    ${DEBUG} && echo "> mapper_name_from_dm_node $@" >&2
    cat /sys/block/${1##*/}/dm/name
}
# ===========================================================================}}}
# major_minor_from_device_node() ============================================{{{
# What we want is: translate the device node given as argument to the
# corresponding major:minor.
major_minor_from_device_node() {
    ${DEBUG} && echo "> major_minor_from_device_node $@" >&2
    cat /sys/class/block/${1##*/}/dev
}
# ===========================================================================}}}
# query_sysfs_attrs() ======================================================={{{
# What we want is: query the sysfs attributes database for a device node given
# as argument.
query_sysfs_attrs() {
    ${DEBUG} && echo "> query_sysfs_attrs $@" >&2
    udevadm info --attribute-walk --name "${1}"
}
# ===========================================================================}}}
# query_udev_envvar() ======================================================={{{
# What we want is: query the udev properties database for a device node given
# as argument. The --export option is mandatory to eval the output of this
# command.
query_udev_envvar() {
    ${DEBUG} && echo "> query_udev_envvar $@" >&2
    udevadm info --query property --name "${1}" --export
}
# ===========================================================================}}}

# vim: et sw=4 sts=4 ts=4 fdm=marker fcl=all
