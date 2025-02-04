#!/bin/bash
# By Willy Gardiol, provided under the GPLv3 License. https://www.gnu.org/licenses/gpl-3.0.html
# Publicly available at: https://github.com/gardiol/media_fixer
# You can contact me at willy@gardiol.org


# where is your "mediainfo" executable
MEDIAINFO_EXE=$(which mediainfo)
# where is your "ffmpeg" executable
FFMPEG_EXE=$(which ffmpeg)
CP_EXE=$(which cp)
MV_EXE=$(which mv)
RM_EXE=$(which rm)


# Define how your videos needs to be converted to.
#
# Which container format to use
if [ "${MEDIAFIXER_CONTAINER}" != "" ]
then
	CONTAINER="${MEDIAFIXER_CONTAINER}"
else
	CONTAINER="Matroska"
fi

if [ "${MEDIAFIXER_CONTAINER_EXTENSION}" != "" ]
then
	CONTAINER_EXTENSION="${MEDIAFIXER_CONTAINER_EXTENSION}"
else
	CONTAINER_EXTENSION="mkv"
fi

# Which codec to use for re-encoding if needed
if [ "${MEDIAFIXER_VIDEO_CODEC}" != "" ]
then
	VIDEO_CODEC="${MEDIAFIXER_VIDEO_CODEC}"
else
	VIDEO_CODEC="AV1"
fi

# Which video resolution to aim for
if [ "${MEDIAFIXER_VIDEO_WIDTH}" != "" ]
then
	VIDEO_WIDTH="${MEDIAFIXER_VIDEO_WIDTH}"
else
	VIDEO_WIDTH="1280"
fi
if [ "${MEDIAFIXER_VIDEO_HEIGHT}" != "" ]
then
	VIDEO_HEIGHT="${MEDIAFIXER_VIDEO_HEIGHT}"
else
	VIDEO_HEIGHT="720"
fi

# Additional FFMPEG specific settings
if [ "${MEDIAFIXER_FFMPEG_EXTRA_OPTS}" != "" ]
then
	FFMPEG_EXTRA_OPTS="${MEDIAFIXER_FFMPEG_EXTRA_OPTS}"
else
	FFMPEG_EXTRA_OPTS="-fflags +genpts"
fi

if [ "${MEDIAFIXER_FFMPEG_ENCODE}" != "" ]
then
	FFMPEG_ENCODE="${MEDIAFIXER_FFMPEG_ENCODE}"
else
	FFMPEG_ENCODE="-c:v libsvtav1 -crf 38"
fi

if [ "${MEDIAFIXER_FFMPEG_RESIZE}" != "" ]
then
	FFMPEG_RESIZE="${MEDIAFIXER_FFMPEG_RESIZE}"
else
	FFMPEG_RESIZE="-vf scale=${VIDEO_WIDTH}:${VIDEO_HEIGHT}"
fi

# loggig and general print functions
function print_log
{
	echo $@ >> "${LOG_FILE}"
}

function print_notice
{
	echo $@ | tee -a "${LOG_FILE}"
}

function print_notice_nonl
{
	echo -n $@ | tee -a "${LOG_FILE}"
}

function print_error
{
	echo ' [ERROR] '$@ | tee -a "${LOG_FILE}"
}

function print_overwrite()
{
	local line="$@"
	echo -ne "${line}" \\r
}

__print_wait_state=0
function print_wait
{
	local c=""
	if [ ${__print_wait_state} -eq 0 ]
	then
		c="[.                 ]"
	elif  [ ${__print_wait_state} -eq 1 ]
	then
		c="[..                ]"
	elif  [ ${__print_wait_state} -eq 2 ]
	then
		c="[...               ]"
	elif  [ ${__print_wait_state} -eq 3 ]
	then
		c="[....              ]"
	elif  [ ${__print_wait_state} -eq 4 ]
	then
		c="[ ....             ]"
	elif  [ ${__print_wait_state} -eq 5 ]
	then
		c="[  ....            ]"
	elif  [ ${__print_wait_state} -eq 6 ]
	then
		c="[   ....           ]"
	elif  [ ${__print_wait_state} -eq 7 ]
	then
		c="[    ....          ]"
	elif  [ ${__print_wait_state} -eq 8 ]
	then
		c="[     ....         ]"
	elif  [ ${__print_wait_state} -eq 9 ]
	then
		c="[      ....        ]"
	elif  [ ${__print_wait_state} -eq 10 ]
	then
		c="[       ....       ]"
	elif  [ ${__print_wait_state} -eq 11 ]
	then
		c="[        ....      ]"
	elif  [ ${__print_wait_state} -eq 12 ]
	then
		c="[         ....     ]"
	elif  [ ${__print_wait_state} -eq 13 ]
	then
		c="[          ....    ]"
	elif  [ ${__print_wait_state} -eq 14 ]
	then
		c="[           ....   ]"
	elif  [ ${__print_wait_state} -eq 15 ]
	then
		c="[            ....  ]"
	elif  [ ${__print_wait_state} -eq 16 ]
	then
		c="[             .... ]"
	elif  [ ${__print_wait_state} -eq 17 ]
	then
		c="[              ....]"
	elif  [ ${__print_wait_state} -eq 18 ]
	then
		c="[               ...]"
	elif  [ ${__print_wait_state} -eq 19 ]
	then
		c="[                ..]"
	elif  [ ${__print_wait_state} -eq 20 ]
	then
		c="[                 .]"
	elif  [ ${__print_wait_state} -eq 21 ]
	then
		c="[                  ]"
	else
		c="[.                 ]"
		__print_wait_state=0
	fi
	print_overwrite "${c}"
	__print_wait_state=$(( __print_wait_state+1 ))
}

function trim() {
    local var="$*"
    # remove leading whitespace characters
    var="${var#"${var%%[![:space:]]*}"}"
    # remove trailing whitespace characters
    var="${var%"${var##*[![:space:]]}"}"
    printf '%s' "$var"
}

function exec_command
{
        print_log "- running command: '""$@""'"
        if [ ${TEST_ONLY} -eq 1 ]
        then
                print_notice " (command not executed because TEST_ONLY=1) "
        else
                "$@" &>> "${LOG_FILE}"
        fi
}


function parse_mediainfo_output
{
	local filename=$1
	local section=$2
	local row=$3

	local value=
	local section_found=0
	local row_found=0
	export mediainfo_value=$("${MEDIAINFO_EXE}" "$filename" | while read line
	do
		if [ $section_found -eq 0 ]
		then
			test "$line" = "$section" && section_found=1
		else
			if [ -z "$line" ]
			then
				return 255
			else
				local left=
				local right=
				IFS=: read left right <<< "$line"
				if [ "$(trim "$left")" = "$row" ]
				then
					echo $(trim "$right")
					return 0
				fi
			fi
		fi
	done)
	
	if [ $? -eq 0 ]
	then
		return 0
	else
		echo "ERROR: '$row' in '$section' not found"
		return 255
	fi
}

function count_lines()
{
	local filename="$1"
	cat "${filename}" | wc -l
}

function queue_pop_line()
{
	local filename="$1"
	local line=$(head -n 1 "${filename}")
	tail -n +2 "${filename}" > "${filename}".removal_in_progress
	"${MV_EXE}" "${filename}".removal_in_progress "${filename}"
	echo ${line}
}

function is_in_queue()
{
	local file="$2"
	local file_found=0
	local line=
	while read line
	do
		if [ "${line%||||*}" = "$2" ]
		then
			file_found=1
		fi
	done < "$1"
	export found=$file_found
}

function preprocess_video_file()
{
	local full_filename="$*"

	local l_result=2 # 0= failed, 1= success, 2= skipped
	local l_change_container=0
	local l_encode=0
	local l_resize=0

	print_notice "Analyzing file '${full_filename}'..."

	parse_mediainfo_output "${full_filename}" "General" "Format"
	if [ $? -eq 0 ]
	then
		if [ "${mediainfo_value}" != "${CONTAINER}" ]
		then
			print_notice "   - Conversion from '${mediainfo_value}' to '${CONTAINER}' needed"
			l_change_container=1
		fi

		parse_mediainfo_output "${full_filename}" "Video" "Format"
		if [ $? -eq 0 ]
		then
			if [ "${mediainfo_value}" != "${VIDEO_CODEC}" ]
			then
				print_notice "   - Encoding from '${mediainfo_value}' to '${VIDEO_CODEC}' needed"
				l_encode=1
			fi
			parse_mediainfo_output "${full_filename}" "Video" "Height"
			mediainfo_value="${mediainfo_value% *}"
			if [ $? -eq 0 ]
			then
				# remove blanks inside height string (since mediainfo will report 1080 as "1 080"):
				mediainfo_value=${mediainfo_value//[[:space:]]/}
				if [ "${mediainfo_value}" != "${VIDEO_HEIGHT}" ]
				then
					if [ ${mediainfo_value} -gt ${VIDEO_HEIGHT} ]
					then
						print_notice "   - Resize from '${mediainfo_value}' to '${VIDEO_HEIGHT}' needed"
						l_resize=1
					fi
				fi
			else
				print_error "Unable to parse Video Height"
				l_result=0
			fi
		else
			print_error "Unable to parse Video Format"
			l_result=0
		fi
	else
		print_error "Unable to parse General Format"
		l_result=0
	fi

	if [ $l_result -eq 0 ]
	then
		print_notice "   Video is invalid or corrupted and cannot be processed."
	else
		if [ $l_change_container -eq 1 -o $l_encode -eq 1 -o $l_resize -eq 1 ]
		then
			l_result=1
		fi
	fi
	export result=$l_result
	export change_container=$l_change_container
	export encode=$l_encode
	export resize=$l_resize
}

function print_usage()
{
	echo "Media Fixer - Reconvert your videos to your preferred container, codec and sizing"
	echo "Usage:"
	echo "   $0 [-l logfile] [-a] [-p path] [-q path] [-r prefix] [-t] [-f] [-d] [-x] [-s] [-i]"
	echo "  -l logfile - use logfile as logfile (optional)"
	echo "  -q q-path  - folder where the queue files will be stored (optional)"
	echo "  -r prefix  - prefix to use for personalized queue filenames (optional)"
	echo "  -a         - start from current folder to scan for videos"
	echo "  -p path    - start from path to scan for videos"
	echo "  -t         - force test mode on - default off (optional)"
	echo "  -f         - force queue analysis, cannot be enabled with -x"
	echo "  -d         - delete old temporary files when found (optional)"
	echo "  -x         - retry all failed conversions, cannot be enabled with -f"
	echo "  -s         - only clean stale files and exit (not compatible with -p or -a)"
	echo "  -i         - wait interactively for confirmation before starting conversions"
	echo " Either '-a' or '-p' must be present."
	echo " If '-l' is omitted, the logfile will be in current folder and called 'mediafixer.log'"
	echo " The queue files are the following:"
	echo "   [q-path/]prefix]mediafixer_queue.skipped     = store list of videos that don't need to be processed"
	echo "   [q-path/]prefix]mediafixer_queue.failed      = store list of videos that failed conversion"
	echo "   [q-path/]prefix]mediafixer_queue.completed   = store list of videos successfully converted"
	echo "   [q-path/]prefix]mediafixer_queue.in_progress = store list of videos under process"
	echo "   [q-path/]prefix]mediafixer_queue.leftovers   = list of temporary files that you should delete"
	echo "   [q-path/]prefix]mediafixer_queue.ignored     = list of videos that will be ignored"
	echo " Upon start, if the in_progress queue is not empty, it will be used without re-scanning"
	echo " all the videos. If you want to force a full rescan, use the -f option."
}

######### Begin of script #############

#### Ensure needed executables do exist
if [ "${MEDIAINFO_EXE}" = "" -o ! -e ${MEDIAINFO_EXE} ]
then
	echo "ERROR: missing 'mediainfo' executable, please install the mediainfo package."
	exit 255
fi

if [ "${FFMPEG_EXE}" = "" -o ! -e ${FFMPEG_EXE} ]
then
	echo "ERROR: missing 'ffmpeg' executable, please install the ffmpeg package."
	exit 255
fi

SCAN_PATH="$(pwd)"
QUEUE_PATH="${SCAN_PATH}"
LOG_FILE="${SCAN_PATH}/mediafixer.log"
PREFIX=""
TEST_ONLY=0
FORCE_SCAN=0
DELETE_OLD_TEMP=0
ONLY_DELETE_OLD_TEMP=0
INTERACTIVE=0
RESUME_FAILED=0
if [ "$1" = "" ]
then
	print_usage
	exit 2
else
	#### Parse commnand line
	while getopts "hal:p:q:r:tfdxis" OPTION
	do
	        case $OPTION in
	        l)
			LOG_FILE="${OPTARG}"
	                ;;
		i)
			INTERACTIVE=1
			;;
		x)
			RESUME_FAILED=1
			FORCE_SCAN=0
			;;
		d)
			DELETE_OLD_TEMP=1
			;;
		s)
			FORCE_SCAN=1
			DELETE_OLD_TEMP=1
			ONLY_DELETE_OLD_TEMP=1
			RESUME_FAILED=0
			;;
		p)
			SCAN_PATH="${OPTARG}"
			ONLY_DELETE_OLD_TEMP=0
			;;
		f)
			FORCE_SCAN=1
			RESUME_FAILED=0
			;;
		a)
			ONLY_DELETE_OLD_TEMP=0
			;;
		q)
			QUEUE_PATH="${OPTARG}"
			;;
		r)
			PREFIX="${OPTARG}"
			;;
		t)
			TEST_ONLY=1
			;;
	        h|*)
			print_usage
	                exit 1
	                ;;
	        esac
	done
fi

if [ ! -d "${SCAN_PATH}" ]
then
	echo "ERROR: scan path '${SCAN_PATH}' does not exist!"
	exit 254
fi

if [ ! -d ${QUEUE_PATH} ]
then
	echo "ERROR: custom queue path '${QUEUE_PATH}' does not exist!"
	exit 254
fi

# Check valid log file
test -z "${LOG_FILE}" && LOG_FILE=/dev/null

# From now on, we can use the print_notice / print_log etc functions...

print_notice " ^a "
print_notice " ^b "
print_notice " ^c "
print_notice "Running Media Fixer on $(date)"
print_notice "   Logfile: '${LOG_FILE}'"
test ${TEST_ONLY} -eq 1 && print_notice "Running in TEST mode"
test ${FORCE_SCAN} -eq 1 && print_notice "Forced scan of videos"
test ${RESUME_FAILED} -eq 1 && print_notice "Will retry all failed processing"
test ${DELETE_OLD_TEMP} -eq 1 && print_notice "Stale temporary files will be deleted"
test ${ONLY_DELETE_OLD_TEMP} -eq 1 && print_notice "Quit after deleting temp files"
test ${INTERACTIVE} -eq 1 && print_notice "Interactively wait for confirmation before conversion"
print_notice "   Base path: '${SCAN_PATH}'"
print_notice "   Queue path: '${QUEUE_PATH}'"

# Move to SCAN_PATH...

(cd "${SCAN_PATH}" && {
#
#  If the in_progress is present, and in_progress is not empty, videos will NOT be analyzed and searched again.
#  This is useful to stop execution and restart later.
#  If the in_progress file is missing or empty, the video search and analysis step is performed.
#

create_queue=0
queue_file="${QUEUE_PATH}/${PREFIX}mediafixer_queue"

if [ ${RESUME_FAILED} -eq 1 ]
then
	test -e "${queue_file}".failed && {
		cat "${queue_file}".failed >> "${queue_file}".in_progress
		${RM_EXE} "${queue_file}".failed
	}
fi

if [ ${FORCE_SCAN} -eq 0 ]
then
	if [ -e "${queue_file}".in_progress ]
	then
		line=$(head -n 1 "${queue_file}".in_progress)
		if [ "${line}" = "" ]
		then
			create_queue=1
		fi
	else
		create_queue=1
	fi
else
	create_queue=1
fi

# Perform video files search
if [ ${create_queue} -eq 1 ]
then
	# Scan for old temp file Scan folders / subfolders to find video files...
	print_notice "Building video queues, this can take a while, be patient..."
	for j in skipped failed completed in_progress temp leftovers ignored
	do
		echo -n > "${queue_file}".${j}
	done

	print_wait
	counter=0
	find . -type f -exec file -N -i -- {} + | sed -n 's!: video/[^:]*$!!p' | {
	while read line
	do
		counter=$(( counter+1 ))
		# write a nice running thingy
	        print_wait
		# stale temp files end with "mediafixer_working"
		if [ "${line%mediafixer_working}" = "${line}" ]
		then
			if [ ${ONLY_DELETE_OLD_TEMP} -eq 0 ]
			then
				found=0
				is_in_queue "${queue_file}".ignored "${line}"
				if [ $found -eq 0 ]
				then
					found=0
					is_in_queue "${queue_file}".failed "${line}"

					if [ $found -eq 0 ]
					then
						result=0
						change_container=0
						encode=0
						resize=0
						preprocess_video_file "${line}"

						# Move file to appropriate new queue
						if [ $result -eq 0 ]
						then
							print_log "Video '${line}' added to failed queue"
							echo ${line} >> "${queue_file}".failed
						elif [ $result -eq 2 ]
						then
							print_log "Video '${line}' added to skipped queue"
							echo ${line} >> "${queue_file}".skipped
						elif [ $result -eq 1 ]
						then
							print_log "Video '${line}' added to processing queue (${change_container} ${encode} ${resize})"
							echo "${line}|||| ${change_container} ${encode} ${resize}" >> "${queue_file}".in_progress
						else
							print_error "Invalid value of '$result' in result!"
						fi # result
					else
						print_log "Video '${line}' ignored because it's in the 'failed' list"
					fi # is in failed queue
				else
					print_log "Video '${line}' ignored because it's in the 'ignored' list"
				fi # is in ignored queue
			fi # delete old temp only
		else
			if [ ${DELETE_OLD_TEMP} -eq 0 ]
			then
				print_error "Skipping file '${line}' because it seems a temporary file, you should maybe delete it?"
				echo ${line} >> "${queue_file}".leftovers
			else
				print_log "Removing stale temporary file '${line}'"
				${RM_EXE} "${line}"
			fi
		fi
	done
	}

	print_notice "Analyzed ${counter} videos."
	if [ ${ONLY_DELETE_OLD_TEMP} -eq 1 ]
	then
		print_notice "Only delete temporary files: terminating operations."
		exit 0
	fi
fi # rescan all video files


TOTAL_WORK_LINES=$(count_lines "${queue_file}".in_progress)
WORKING_LINES=1
print_notice "Failed queue has "$(count_lines "${queue_file}".failed)" videos."
print_notice "Skipped queue has "$(count_lines "${queue_file}".skipped)" videos."
print_notice "Work queue has ${TOTAL_WORK_LINES} videos to be processed..."

if [ ${INTERACTIVE} -eq 1 ]
then
	echo "Ready to go? Press RETURN to start, or CTRL+C to abord."
	read dummy
fi

# Iterate the in_progress queue...
line=$(queue_pop_line "${queue_file}".in_progress)
while [ "${line}" != "" ]
do

	result=0

	full_filename=${line%||||*}
	filepath="${full_filename%/*}"
	filename="${full_filename##*/}"
	extension="${filename##*.}"
	stripped_filename="${filename%.*}"
	
	temp=${line#*||||}
	change_container=${temp%[[:space:]][[:digit:]][[:space:]][[:digit:]]}
	encode=${temp%[[:space:]][[:digit:]]}
	encode=${encode#[[:space:]][[:digit:]][[:space:]]}
	resize=${temp##[[:space:]][[:digit:]][[:space:]][[:digit:]][[:space:]]}

	print_notice "--- Processing video '$full_filename' [ ${WORKING_LINES} / ${TOTAL_WORK_LINES} ]"
	WORKING_LINES=$(( WORKING_LINES+1 ))

	if [ $change_container -eq 1 -o $encode -eq 1 -o $resize -eq 1 ]
	then
		result=0
		my_cwd="$PWD"
		if cd "${filepath}"
		then
			error=0
			gc_filename="${stripped_filename}.mediafixer_working"			
			print_log "Copying original to '${gc_filename}'..."
			exec_command "${CP_EXE}" "${filename}" "${gc_filename}" &>> "${LOG_FILE}"

			if [ $change_container -eq 1 ]
			then 
				intermediate_filename="${stripped_filename}.tmuxed".${CONTAINER_EXTENSION}
				print_notice_nonl "Transmuxing..."
				print_log "Transmuxing from '${gc_filename}' to '${intermediate_filename}'..."
				exec_command "${FFMPEG_EXE}" -fflags +genpts -nostdin -find_stream_info -i "${gc_filename}" -map 0 -map -0:d -codec copy -codec:s srt "${intermediate_filename}" &>> "${LOG_FILE}"
				if [ $? -eq 0 ]
				then
					print_notice_nonl " done. "
					exec_command "${MV_EXE}" "${intermediate_filename}" "${gc_filename}" &>> "${LOG_FILE}"
				else
					print_notice_nonl " failed! "
					exec_command "${RM_EXE}" -f "${intermediate_filename}"
					error=1
				fi
			fi # transmux

			if [ $error -eq 0 ]
			then
				if [ $encode -eq 1 -o $resize -eq 1 ]
				then
					source_filename="${gc_filename}"
					intermediate_filename="${stripped_filename}.encoded".${CONTAINER_EXTENSION}
					print_notice_nonl "Encoding..."
					print_log "Encoding from '${source_filename}' to '${intermediate_filename}'" 

					ffmpeg_options=
					if [ $encode -eq 1 ]
					then
						ffmpeg_options=${FFMPEG_ENCODE}
					fi
	
					if [ $resize -eq 1 ]
					then
						ffmpeg_options="${ffmpeg_options} ${FFMPEG_RESIZE}"
					fi

					exec_command "${FFMPEG_EXE}" -fflags +genpts -nostdin -i "${source_filename}" ${ffmpeg_options} "${intermediate_filename}"
					if [ $? -eq 0 ]
					then
						print_notice_nonl " done. "
						exec_command "${MV_EXE}" "${intermediate_filename}" "${gc_filename}"
					else
						print_notice_nonl " failed! "
						exec_command "${RM_EXE}" -f "${intermediate_filename}"
						error=1
					fi
				fi # encore or resize
			fi # error = 0

			if [ -e "${gc_filename}" ]
			then
				print_notice "Removing temporary file due to previous errors..."
				exec_command "${RM_EXE}" -f "${intermediate_filename}"
			fi

			# Needed to properly go to the next line since all last prints are without newline
			print_notice " "

			if [ $error -eq 0 ]
			then
				if [ -e "${gc_filename}" ]
				then
					destination_filename="${stripped_filename}.${CONTAINER_EXTENSION}"
					print_log "Moving final product from '${gc_filename}' to '${destination_filename}'..."
					exec_command "${MV_EXE}" "${gc_filename}" "${destination_filename}"
					if [ $? -eq 0 ]
					then
						result=1
						if [ "${filename}" != "${destination_filename}" ]
						then
							print_log "Removing original file..."
							exec_command "${RM_EXE}" -f "${filename}"
						else
							print_log "Original file has been replaced with converted file."
						fi
					else
						print_error "Unable to move converted file, not deleting original."
					fi
				else
					print_error "Missing gc file '${working_filename}', something went wrong!"
				fi
			else
				print_error "Something went wrong in conversion."
			fi
			cd "$my_cwd"
		else
			print_error "Unable to cd to '${filepath}'"
		fi 
		
	else
		print_notice "Nothing to do (!?!?)"
	fi # change container or encode

	print_log "Removing processed file from processing queue..."
	if [ ${result} -eq 1 ]
	then
		echo ${line} >> "${queue_file}".completed
	else
		echo ${line} >> "${queue_file}".failed
	fi

	# remove from queue
	line=$(queue_pop_line "${queue_file}".in_progress)

done

}) # moved to SCAN_PATH

print_notice "All done."
print_notice " ^x "
print_notice " ^y "
print_notice " ^z "
exit 0

