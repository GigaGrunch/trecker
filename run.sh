set -e

exe="trecker_$1"
if [[ `uname` == "WindowsNT" ]] || [[ `uname` == MINGW64_NT-* ]]
then
	exe="$exe.exe"
else
	exe="$exe.bin"
fi

shift 1

./"build.sh"
./"$exe" $@
