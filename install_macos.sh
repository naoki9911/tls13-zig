#!/bin/bash

cd `dirname $0`

brew install jq
brew install curl

./install_zig.sh