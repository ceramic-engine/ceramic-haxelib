#!/bin/bash
cd "${0%/*}"

mkdir .haxelib
haxelib dev akifox-asynchttp git/akifox-asynchttp
haxelib dev ceramic .
