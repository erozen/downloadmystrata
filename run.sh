#!/bin/ash

# Wrapper script to call the main strata-get in a loop.
# Also sources config/setup before each run, so you can change config without having to restart the container.

## Guts of the main script.  Pulls down new files, copies them to the remote, and performs any follow-up action you may want
do_run() {
  if "$DIR"/strata-get.sh "$1" /remote
  then
    logger -s "$0 Download complete. Starting rclone."
    rclone --config /config/rclone.conf copyto /remote "$REMOTE"
    logger -s "$0 rclone complete."

    for file in /remote/*
    do
      [ ! -f "$file" ] && continue
      logger -s "$0 Examining $file for further action and clean up"
      ### For example, say you want to send all invoices to your accountant automatically
      # echo "$file" | grep -qi "invoice" && echo | mail -s "New invoice recieved - $file" your-accountant@example.com -A "$file"
      rm -f "$file"
    done
    # Disabled debugging enabled by error for last file
    [ "$VERBOSE" == "enabled-by-error" ] && export VERBOSE=""
  else
    logger -s -p 4 "$0 Download failed."
    # Enable debugging for next file, in case the error happens again
    [ "$RUN_IN_LOOP" ] && export VERBOSE="enabled-by-error"
  fi
}

# Source the configuration file for this script
. /config/setup

PERIOD="${PERIOD:-86400}"
[ ! "$REMOTE" ] && logger -s -p 3 "$0 No REMOTE specified.  Quitting" && exit 1

if [ "$RUN_IN_LOOP" ]
then
  logger -s "$0 Starting in loop"
  while sleep "$PERIOD"
  do
    logger -s "$0 Start of run"
    . /config/setup
    do_run
    logger -s "$0 End of run"
  done
else
  logger -s "$0 Starting one off"
  do_run "$( date -d "-$(( PERIOD + 60 ))secs" +%s )"
fi
