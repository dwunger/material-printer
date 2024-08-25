# This will build the index file which contains files which need
# to be looked up on Github for updates. utils has a function
# to convert paths to the their respective URIs for curling

using module '.\utils.psm1'

rm '.\INDEX'

Walk-Path -Path "." >> '.\INDEX'