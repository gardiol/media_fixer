#!/bin/bash
# By Willy Gardiol, provided under the GPLv3 License. https://www.gnu.org/licenses/gpl-3.0.html
# Publicly available at: https://github.com/gardiol/media_fixer
# You can contact me at willy@gardiol.org

TEST_ONLY=0
DEBUG=1
LOG_FILE="$(pwd)/media_fixer.log"

CONTAINER="Matroska"
CONTAINER_EXTENSION="mkv"
VIDEO_CODEC="AV1"
VIDEO_WIDTH="1280"
VIDEO_HEIGHT="720"

FFMPEG_EXTRA_OPTS="-fflags +genpts"
FFMPEG_ENCODE="-c:v libsvtav1 -crf 38"
FFMPEG_RESIZE="-vf scale=${VIDEO_WIDTH}:${VIDEO_HEIGHT}"

# Check valid log file
test -z "${LOG_FILE}" && LOG_FILE=/dev/null
test ${TEST_ONLY} -eq 1 && DEBUG=1

# loggig, debugging and general print functions
function print_debug
{
	test ${DEBUG} -eq 1 && echo ' [DEBUG] '$@  | tee -a "${LOG_FILE}"
}

function print_notice
{
	echo $@ | tee -a "${LOG_FILE}"
}

function print_error
{
	echo ' [ERROR] '$@ | tee -a "${LOG_FILE}"
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
        print_notice "- running command: '""$@""'"
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
	export mediainfo_value=$(mediainfo "$filename" | while read line
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
			print_notice "Container needs to be converted from '${mediainfo_value}' to '${CONTAINER}'..."
			l_change_container=1
		else 
			print_notice "Container already '${CONTAINER}'."
		fi

		parse_mediainfo_output "${full_filename}" "Video" "Format"
		if [ $? -eq 0 ]
		then
			if [ "${mediainfo_value}" != "${VIDEO_CODEC}" ]
			then
				print_notice "Movie needs to be encoded from '${mediainfo_value}' to '${VIDEO_CODEC}'..."
				l_encode=1
			else 
				print_notice "Video already at '${VIDEO_CODEC}' encoding."
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
						print_notice "Movie needs to be resized from '${mediainfo_value}' to '${VIDEO_HEIGHT}'..."
						l_resize=1
					else
						print_notice "Not resizing upward: '${mediainfo_value}' is smaller than '${VIDEO_HEIGHT}'."
					fi
				else 
					print_notice "Video already at '${VIDEO_HEIGHT}' resolution."
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
			print_notice "   Video needs to be processed."
		fi
	fi
	export result=$l_result
	export change_container=$l_change_container
	export encode=$l_encode
	export resize=$l_resize
}


######### Begin of script #############

scan_path=$1
if [ -z "${scan_path}" ]
then
	print_notice "No path specified on command line... using current folder as default."
	scan_path=$(pwd)
fi

create_queue=0
queue_file="processing_queue"
if [ -e ${queue_file}.in_progress ]
then
	line=$(head -n 1 ${queue_file}.in_progress)
	if [ "${line}" = "" ]
	then
		create_queue=1
	fi
else
	create_queue=1
fi

if [ ${create_queue} -eq 1 ]
then
	# Scan folders / subfolders and file files...
	print_notice "Calculating queues..."
	for j in skipped failed completed in_progress temp
	do
		test -e ${queue_file}.${j} && rm ${queue_file}.${j}
	done

	find . -type f -exec file -N -i -- {} + | sed -n 's!: video/[^:]*$!!p' | {
	while read line
	do
		# temp files end with ".working", those needs to be ignored
		is_temp=${line%working}
		if [ "${line%working}" = "${line}" ]
		then
			echo ${line} >> ${queue_file}.temp
		else
			print_notice "Skipping file '${line}' because it seems a temporary file, you should maybe delete it?"
		fi
	done
	}
fi

print_notice "Queue has "$(cat ${queue_file}.temp | wc -l)" videos to be analyzed..."

# Iterate all files...
line=$(head -n 1 ${queue_file}.temp)
while [ "${line}" != "" ]
do
	result=0
	change_container=0
	encode=0
	resize=0
	preprocess_video_file "${line}"

	# Remove file from queue...
	tail -n +2 ${queue_file}.temp > ${queue_file}.cleaned
	mv ${queue_file}.cleaned ${queue_file}.temp

	# Move file to appropriate new queue
	if [ $result -eq 0 ]
	then
		# add file to failed queue
		print_notice "Video '${line}' added to failed queue"
		echo ${line} >> ${queue_file}.failed
	elif [ $result -eq 2 ]
	then
		# add file to skipped queue
		print_notice "Video '${line}' added to skipped queue"
		echo ${line} >> ${queue_file}.skipped
	elif [ $result -eq 1 ]
	then
		# add file to process queue
		print_notice "Video '${line}' added to processing queue (${change_container} ${encode} ${resize})"
		echo "${line}|||| ${change_container} ${encode} ${resize}" >> ${queue_file}.in_progress
	else
		print_notice "Invalid value of '$result' in result!"
	fi
	line=$(head -n 1 ${queue_file}.temp)
done

test -e ${queue_file}.failed || touch ${queue_file}.failed
test -e ${queue_file}.skipped || touch ${queue_file}.skipped
test -e ${queue_file}.in_progress || touch ${queue_file}.in_progress

print_notice "Failed queue has "$(cat ${queue_file}.failed | wc -l)" videos."
print_notice "Skipped queue has "$(cat ${queue_file}.skipped | wc -l)" videos."
print_notice "Work queue has "$(cat ${queue_file}.in_progress | wc -l)" videos to be processed..."


# Iterate all files...
line=$(head -n 1 ${queue_file}.in_progress)
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

	echo "Processing: '$full_filename'..."

	if [ $change_container -eq 1 -o $encode -eq 1 -o $resize -eq 1 ]
	then
		result=0
		print_notice "   Video needs to be processed."
		my_cwd="$PWD"
		print_notice "Relocating to path '${filepath}' for easier operations..."
		if cd "${filepath}"
		then
			error=0
			working_filename="${stripped_filename}.working"			
			print_notice "Copying original to '${working_filename}'..."
			exec_command cp "${filename}" "${working_filename}" &>> "${LOG_FILE}"

			if [ $change_container -eq 1 ]
			then 
				intermediate_filename="${stripped_filename}.tmuxed".${CONTAINER_EXTENSION}
				print_notice "Transmuxing from '${working_filename}' to '${intermediate_filename}'..."
				exec_command ffmpeg -fflags +genpts -nostdin -find_stream_info -i "${working_filename}" -map 0 -map -0:d -codec copy -codec:s srt "${intermediate_filename}" &>> "${LOG_FILE}"
				if [ $? -eq 0 ]
				then
					print_notice "Transmux ok."
					exec_command mv "${intermediate_filename}" "${working_filename}" &>> "${LOG_FILE}"
				else
					print_error "Transmux failed!"
					exec_command rm -f "${intermediate_filename}"
					error=1
				fi
			fi # transmux

			if [ $error -eq 0 ]
			then
				if [ $encode -eq 1 -o $resize -eq 1 ]
				then
					source_filename="${working_filename}"
					intermediate_filename="${stripped_filename}.encoded".${CONTAINER_EXTENSION}
					print_notice "Encoding from '${source_filename}' to '${intermediate_filename}'" 

					ffmpeg_options=
					if [ $encode -eq 1 ]
					then
						ffmpeg_options=${FFMPEG_ENCODE}
					fi
	
					if [ $resize -eq 1 ]
					then
						ffmpeg_options="${ffmpeg_options} ${FFMPEG_RESIZE}"
					fi

					exec_command ffmpeg -fflags +genpts -nostdin -i "${source_filename}" ${ffmpeg_options} "${intermediate_filename}"
					if [ $? -eq 0 ]
					then
						print_notice "Encoding ok."
						exec_command mv "${intermediate_filename}" "${working_filename}"
					else
						print_error "Encoding failed!"
						exec_command rm -f "${intermediate_filename}"
						error=1
					fi
				fi # encore or resize
			fi # error = 0

			if [ $error -eq 0 ]
			then
				if [ -e "${working_filename}" ]
				then
					destination_filename="${stripped_filename}.${CONTAINER_EXTENSION}"
					print_notice "Moving final product from '${working_filename}' to '${destination_filename}'..."
					exec_command mv "${working_filename}" "${destination_filename}"
					if [ $? -eq 0 ]
					then
						result=1
						if [ "${filename}" != "${destination_filename}" ]
						then
							print_notice "Removing original file..."
							exec_command rm -f "${filename}"
						else
							print_notice "Original file has been replaced with converted file."
						fi
					else
						print_error "Unable to move converted file, not deleting original."
					fi
				else
					print_error "Missing working file '${working_filename}', something went wrong!"
				fi
			else
				print_error "Something went wrong in conversion."
			fi
			cd "$my_cwd"
		else
			print_error "Unable to cd to '${filepath}'"
		fi 
		
	fi # change container or encode

	print_notice "Removing processed file from processing queue..."
	if [ ${result} -eq 1 ]
	then
		echo ${line} >> ${queue_file}.completed
	else
		echo ${full_filename} >> ${queue_file}.failed
	fi

	# remove from queue
	tail -n +2 ${queue_file}.in_progress > ${queue_file}.cleaned
	mv ${queue_file}.cleaned ${queue_file}.in_progress
	line=$(head -n 1 ${queue_file}.in_progress)

done

print_notice "All done."
exit 0

