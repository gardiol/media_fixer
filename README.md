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


## queue files

Media Fixer will scan a path and build a list of queue files.

 The queue files are the following:
- [queue-path/]prefix]mediafixer_queue.temp        = store list of videos before they are analyzed
- [queue-path/]prefix]mediafixer_queue.skipped     = store list of videos that don't need to be processed
- [queue-path/]prefix]mediafixer_queue.failed      = store list of videos that failed conversion
- [queue-path/]prefix]mediafixer_queue.completed   = store list of videos successfully converted
- [queue-path/]prefix]mediafixer_queue.in_progress = store list of videos under process
- [queue-path/]prefix]mediafixer_queue.leftovers   = list of temporary files that you should delete
- 
 Upon start, if the in_progress queue is not empty, it will be used without re-scanning
 all the videos. If you want to force a full rescan, use the -f option, in this case all the queue files will be deleted before proceeding.




----

Media Fixer has been developed by Willy Gardiol, it's provided under the GPLv3 License. https://www.gnu.org/licenses/gpl-3.0.html
Media Fixer is publicly available at: https://github.com/gardiol/media_fixer



