#!/usr/bin/env bash

WORKDIR=$(pwd)

_lua() {
  PID=$(pgrep -f 'lua init.lua')

  if [[ -n "$PID" ]]; then
    echo "killing lua process"
    kill "$PID"
  fi

  lua init.lua &
}

_scss() {
  sass "$WORKDIR"/scss/style.scss /tmp/style.css
  _lua
}

_lua

inotifywait --quiet --monitor --event create,modify,delete --recursive $WORKDIR | while read DIRECTORY EVENT FILE; do
  file_extension=${FILE##*.}
  case $file_extension in
  lua)
    echo "reload lua..."
    _lua
    ;;
  scss)
    echo "reload scss..."
    _scss
    ;;
  esac
done
