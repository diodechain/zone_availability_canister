#!/bin/bash
unameOut="$(uname -s)"
case "${unameOut}" in
    Linux*)     machine=Linux;;
    Darwin*)    machine=Mac;;
    *)          machine="UNKNOWN:${unameOut}"
esac

release=$(curl --silent "https://api.github.com/repos/dfinity/candid/releases/latest" | grep -e '"tag_name"' | cut -c 16-25)

if [ ${machine} = "Mac" ]
then
  echo "Downloading didc for Mac to ~/bin/didc"
  curl -fsSL https://github.com/dfinity/candid/releases/download/${release}/didc-macos > ~/bin/didc
elif [ ${machine} = "Linux" ]
then
  echo "Downloading didc for Linux to ~/bin/didc"
  curl -fsSL https://github.com/dfinity/candid/releases/download/${release}/didc-linux64 > ~/bin/didc
else
  echo "Could not detect a supported operating system. Please note that didc is currently only supported for Mac and Linux"
fi

date
