# Media Fixer - ensure your media collection is consistent

Having a big collection of movies, TV shows or, in general, any kind of videos can lead to high fragmentation in video formats, codecs and sizes. It might be desirable to encode / resize the videos to one common codec or resolution to reduce required disk real estate or provide consistent streaming.

There are many other tools out there to achieve this result, and they are often very complex and difficult to manage.

Media Fixer is a **bash script** that aims at perform the same task, but from the CLI and with a single command that you run and let it do it's jobs.

## Requirements

Media Fixer has been tested on Linux only. It could work on Windows (WSL) or MacOS, but please do not open tickets or request assistance on anything but Linux.

You need to have the following installed on your system:
- FFMPEG (it's used under the hood for all conversions and encodings it's mandatory)
- mediainfo (it's required to scan existing video files to detect if they need conversion or encoding or not)
- Basic linux tools (mv, rm, cp, cat...)

## Installation

Clone the repository and run the script, it's that simple.


## Usage


## queue files

## Logs

----

Media Fixer has been developed by Willy Gardiol, it's provided under the GPLv3 License. https://www.gnu.org/licenses/gpl-3.0.html
Media Fixer is publicly available at: https://github.com/gardiol/media_fixer



