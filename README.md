# Media Fixer - ensure your media collection is consistent

Having a big collection of movies, TV shows or, in general, any kind of videos can lead to high fragmentation in video formats, codecs and sizes. It might be desirable to encode / resize the videos to one common codec or resolution to reduce required disk real estate or provide consistent streaming.

There are many other tools out there to achieve this result, and they are often very complex and difficult to manage.

Media Fixer is a **bash script** that aims at perform the same task, but from the CLI and with a single command that you run and let it do it's jobs.

## Requirements

Media Fixer has been tested on Linux only. It could work on Windows (WSL) or MacOS, but please do not open tickets or request assistance on anything but Linux.

You need to have the following installed on your system:
- https://ffmpeg.org/ (it's used under the hood for all conversions and encodings it's mandatory)
- https://github.com/MediaArea/MediaInfo (it's required to scan existing video files to detect if they need conversion or encoding or not)
- Basic linux tools (mv, rm, cp, cat...)

## Installation

Clone the repository and run the script, it's that simple.


## Usage

Running the script will prompt you the  usage instructions. The list of accepter options are:
- `-l logile`: full path to logfile. Optional. Default is mediafixer.log in current folder
- `-q queue_path`: path to folder where queue files will be created. Optional. Default is current folder
- `-r prefix`: a prefix for the queue filesnames. Optional. Default is empty
- `-a`: scan current folder and subfolders. Must be specified in alternative to `-p path`.
- `-p scanpath`: scan this path and it's subfolders. Must be specified in alternative to `-a`
- `-t`: force test mode. In test mode, no videos will be modified, only actions will be logged.
- `-f`: force queue analysis (see below)
- `-d`: delete stale temporary files. Optional. Default is to print a warning if a stale temp file is found from a previous run
- `-x`: retry all failed conversions. Cannot be enabled with `-f`. Will use the failed queue to retry the conversions.
- `-s`: only clean stale temp files, do not do anything else. Will still scan all the video files.
- `-i`: after scanning, wait for user input before starting the conversions.

**Note:** either `-a` or `-p scanpath` must be provided for operations to start.

### queue files

Media Fixer will scan a path and build a list of queue files.

 The queue files are the following:
- [queue-path/]prefix]mediafixer_queue.skipped     = store list of videos that don't need to be processed
- [queue-path/]prefix]mediafixer_queue.failed      = store list of videos that failed conversion
- [queue-path/]prefix]mediafixer_queue.completed   = store list of videos successfully converted
- [queue-path/]prefix]mediafixer_queue.in_progress = store list of videos under process
- [queue-path/]prefix]mediafixer_queue.leftovers   = list of temporary files that you should delete
- 
 Upon start, if the in_progress queue is not empty, it will be used without re-scanning
 all the videos. If you want to force a full rescan, use the -f option, in this case all the queue files will be deleted before proceeding.

## How it works

The script will first scan the path (either the current path with `-a` or a custom path with `-p` flags) for all contained video files, 
then parse each video file it found to verify if it matches the requested video container, video codec, and video size (width x height).

The filenames of the videos are then sorted out in the queue files (see above), so that any subsequent run of the script will not perform the
scan & analyze phase again (unless you specify the `-f` flag):
- Any video that is already in the request format and size: it's filename goes into the skipped queue
- Any video that needs any kind of processing, will have it's filename placed in the in_progress queue (with some details of what needs to be done)
- Any video file that fails to analyze will have it's filename placed in the failed queue
- Any stale temporary file found, will have it's filename stored in the leftovers queue, unless the `-d` flag is specified.

After the scanning and analysis phase is complete, the script will start converting all the video files which are in the in_progress queue. 
There are three different operations possible:
- replace the container (from AVI ro MKV, for example)
- Encoding to a different CODEC (from x264 to AV1 for example)
- Resizing (from 1080p to 720p for example)

Any video that fails the conversion at any stage, wll have it's filename in the failed queue. If all the steps are completed properly, the filename will mve to the completed queue.

The desired formats can cusotmize by modifying the following environment variables:

    export MEDIAFIXER_CONTAINER="Matroska"
    export MEDIAFIXER_CONTAINER_EXTENSION="mkv"
    export MEDIAFIXER_VIDEO_CODEC="AV1"
    export MEDIAFIXER_VIDEO_WIDTH="1280"
    export MEDIAFIXER_VIDEO_HEIGHT="720"

These, if set before starting the script, will take precedence on the default built-in values.

In addition, you can export the following advanced variables:

    FFMPEG_EXTRA_OPTS="-fflags +genpts"
    FFMPEG_ENCODE="-c:v libsvtav1 -crf 38"
    FFMPEG_RESIZE="-vf scale=${VIDEO_WIDTH}:${VIDEO_HEIGHT}"

But be careful, you must know what you are doing here or things **will break**.

### Container conversion

Container conversion is done first. If the video container doesn't match the requested one, the video will be re-containerized using FFMPEG. This is a **lossless** conversion, and usually pretty fast.

Selecting the best container is not trivial, because not all CODECS and formats can be supported. Matroska is probably the most logical one in all cases, and also the default one.

### Encoding

Encoding is done at the same time of resizing. This is usually a **loss** conversion and it's better done only once for a video. You should download directly the videos in the codec you prefer to avoid consumning encoding operations and loss of video quality. You usually want to recode in a different codec when you aim at consistency for streaming, or to save significant disk real estate. 

By default GPUs will**not** be used, because they are meant for streaming and not storing, creating worse output that CPU based encoding. If you need GPU encoding, you should maunally change your ffmpeg options with the environment variables above.

### Resizing

Resizing is done when the original video is not in the requested size. 

Since it make no sense to resize upward, from a smaller video resolution to a bigger one, Media Fixer will **not** resize a smaller video to a bigger size. At the same time, any resising wull never change the aspect ratio of the video. The resizing is focused on the y-resolution (1080p, 720p, 480p, etc) for this reason. If you need to alter the aspect ratio, you need to cusotmize your ffmpeg options with the environment variables above.




----

Media Fixer has been developed by Willy Gardiol, it's provided under the GPLv3 License. https://www.gnu.org/licenses/gpl-3.0.html
Media Fixer is publicly available at: https://github.com/gardiol/media_fixer



