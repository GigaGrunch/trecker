set -e

exe="trecker_$1.exe"
shift 1

./"build.sh"
./"$exe" $@
