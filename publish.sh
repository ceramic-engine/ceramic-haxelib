#!/bin/bash
cd "${0%/*}"

rm -rf ./ceramic
rm -rf ./ceramic.zip
rm -rf ./ceramic-linux.zip
rm -rf ./ceramic-mac.zip
rm -rf ./ceramic-windows.zip

haxelib submit .
