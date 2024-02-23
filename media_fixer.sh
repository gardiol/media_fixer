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


######### Begin of script #############

scan_path=$1
if [ -z "${scan_path}" ]
then
	print_notice "No path specified on command line... using current folder as default."
	scan_path=$(pwd)
fi

# Scan folders / subfolders and file files...
find . -type f -exec file -N -i -- {} + | sed -n 's!: video/[^:]*$!!p' | {
while read line
do
	change_container=0
	encode=0
	resize=0

	full_filename=${line}
	filepath="${full_filename%/*}"
	filename="${full_filename##*/}"
	extension="${filename##*.}"
	stripped_filename="${filename%.*}"
	
	print_notice "Analyzing file '${full_filename}'..."

	parse_mediainfo_output "${full_filename}" "General" "Format"
	if [ $? -eq 0 ]
	then
		if [ "${mediainfo_value}" != "${CONTAINER}" ]
		then
			print_notice "Container needs to be converted from '${mediainfo_value}' to '${CONTAINER}'..."
			change_container=1
		else 
			print_notice "Container already '${CONTAINER}'."
		fi
	else
		print_error "Unable to parse General Format"
	fi


	parse_mediainfo_output "${full_filename}" "Video" "Format"
	if [ $? -eq 0 ]
	then
		if [ "${mediainfo_value}" != "${VIDEO_CODEC}" ]
		then
			print_notice "Movie needs to be encoded from '${mediainfo_value}' to '${VIDEO_CODEC}'..."
			encode=1
		else 
			print_notice "Video already at '${VIDEO_CODEC}' encoding."
		fi
	else
		print_error "Unable to parse Video Format"
	fi

	parse_mediainfo_output "${full_filename}" "Video" "Height"
	mediainfo_value="${mediainfo_value% *}"
	if [ $? -eq 0 ]
	then
		if [ "${mediainfo_value}" != "${VIDEO_HEIGHT}" ]
		then
			print_notice "Movie needs to be resized from '${mediainfo_value}' to '${VIDEO_HEIGHT}'..."
			resize=1
		else 
			print_notice "Video already at '${VIDEO_HEIGHT}' resolution."
		fi
	else
		print_error "Unable to parse Video Height"
	fi

	if [ $change_container -eq 1 -o $encode -eq 1 -o $resize -eq 1 ]
	then
		print_notice "   Video needs to be processed."
		(
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
				exec_command ffmpeg -nostdin -find_stream_info -i "${working_filename}" -map 0 -map -0:d -codec copy -codec:s srt "${intermediate_filename}" &>> "${LOG_FILE}"
				if [ $? -eq 0 ]
				then
					print_notice "Transmux ok."
					exec_command mv "${intermediate_filename}" "${working_filename}" &>> "${LOG_FILE}"
				else
					print_error "Transmux failed!"
					exec_command rm -f "${intermediate_filename}" &>> "${LOG_FILE}"
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

					exec_command ffmpeg -nostdin -i "${source_filename}" ${ffmpeg_options} "${intermediate_filename}" &>> "${LOG_FILE}"
					if [ $? -eq 0 ]
					then
						print_notice "Encoding ok."
						exec_command mv "${intermediate_filename}" "${working_filename}" &>> "${LOG_FILE}"
					else
						print_error "Encoding failed!"
						exec_command rm -f "${intermediate_filename}" &>> "${LOG_FILE}"
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
					exec_command mv "${working_filename}" "${destination_filename}" &>> "${LOG_FILE}"
					if [ $? -eq 0 ]
					then
						if [ "${filename}" != "${destination_filename}" ]
						then
							print_notice "Removing original file..."
							exec_command rm -f "${filename}" &>> "${LOG_FILE}"
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
		else
			print_error "Unable to cd to '${filepath}'"
		fi 
		) 
	fi # change container or encode

done

}

print_notice "All done."
exit 0

