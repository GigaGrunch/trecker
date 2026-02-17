result=0
trap "result=1" ERR
odin build "trecker_cli" -vet -strict-style
odin build "trecker_gui" -vet -strict-style
exit "$result"
