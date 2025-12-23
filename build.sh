result=0
trap "result=1" ERR
odin build "trecker_cli"
odin build "trecker_gui"
exit "$result"
