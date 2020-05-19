#!/bin/bash
# copy to /usr/local/bin

# TODO bigger/smaller, number bonds

#exec 49>/tmp/timestables.log
#BASH_XTRACEFD=49
#set -x

logfile=${logfile:-~/.timestables.txt}

# clear any pending input
function flush () {
    local x
    while read -t 0 x ; do
        #[[ "$x" != "" ]] || break
        # TODO how to handle race with read -N not resetting terminal
        # and this loop spinning?
        # can't just check for empty since that won't catch empty lines
        :
    done
}

# put cursor back to saved location then
# move cursor right number of characters in $1 plus $2
function moveright () {
    local n=${2:-0}
    ((n+=${#1}))
    tput rc
    while [[ $((n--)) -gt 0 ]] ; do
        tput cuf1
    done
}

# try to restore screen to previous
function tidy_up () {
    tput setb 0
    tput setf 7
    tput clear
    tput cvvis
    tput reset
}

# first arg is operation (add,subtract,times,divide)
op=mixed

# default to opening new window
newwin=1

# range of multiplier (12 if not set)
size=12

# font size
fontsize=20

# keep asking until correct, or just give one attempt?
mode=oneshot

# pattern for removing escape sequences
escseq=$'\x1b\[+([0-9])?(m)'
shopt -s extglob

while getopts "rf:ls:o:" o ; do
    case "$o" in
        l)  # display in local console not new window
            newwin=
            ;;
        s)  # number of multipliers for each table
            size=$OPTARG
            ;;
        o)  # type of table
            op=$OPTARG
            ;;
        f)  # font size
            fontsize=$OPTARG
            ;;
        r)  # font size
            mode=repeattilcorrect
            ;;
        *)  # uh?
            echo "Do not recognise '$o' as a valid argument" >&2
            exit 1
    esac
done

# see if we have to run in a new window
[[ -n $newwin && -n $XAUTHORITY ]] && exec xterm -fullscreen -geometry 100% -fa default -fs $fontsize -xrm waitForMap=true -wf -e $0 -l "$@"
#[[ -n $newwin ]] && exec lxterm -fullscreen -geometry 100% -fa default -fs 20 -xrm waitForMap=true -wf -e $0 -l "$@"

# ensure that the local shell has the correct idea of geometry
sleep 0.25

# ditch arguments leaving just tables to test on
shift $((OPTIND-1))

# list of sums yet to be answered
declare -a sums

# prepare the times tables q&a
function prep_times () {
    while [[ $size -gt 0 ]] ; do
        allsums+=( "$table x $size = ?:$((table * size))" )
        ((--size))
    done
}

# prepare the times tables q&a
function prep_divide () {
    while [[ $size -gt 0 ]] ; do
        allsums+=( "$((table * size)) ÷ $size = ?:$table" )
        ((--size))
    done
}

# prepare addition
function prep_add () {
    local n
    local d
    case $table in
        2|3|4)
            n=10
            d=10
            ;;
        5|6|7|8)
            n=100
            d=10
            ;;
        *)  n=1000
            d=100
            ;;
    esac
    
    while [[ $size -gt 0 ]] ; do
        local b=$(( 1+(RANDOM % n) ))
        local c=$(( 1+(RANDOM % d) ))
        allsums+=( "$b + $c = ?:$((b+c))" )
        ((--size))
    done
}

# prepare subtraction
function prep_subtract () {
    local n
    local d
    case $table in
        2|3|4)
            n=10
            d=10
            ;;
        5|6|7|8)
            n=100
            d=10
            ;;
        *)  n=1000
            d=100
            ;;
    esac
    
    while [[ $size -gt 0 ]] ; do
        local b=$(( 1+(RANDOM % n) ))
        local c=$(( 1+(RANDOM % d) ))
        allsums+=( "$b - $c = ?:$((b-c))" )
        ((--size))
    done
}

# prep mix of:
# a * b = 
# a * ? = b
# a / b =
# a / ? = b
function prep_mixed () {
    while [[ $size -gt 0 ]] ; do
        local m=$((size * table))
        case $((RANDOM % 6)) in
            0)  allsums+=( "$size x $table = ?:$m" ) ;;
            1)  allsums+=( "$table x ? = $m:$size" ) ;;
            2)  allsums+=( "$m ÷ $table = ?:$size" ) ;;
            3)  allsums+=( "$m ÷ ? = $table:$size" ) ;;
            4)  allsums+=( "$table x $size = ?:$m" ) ;;
            5)  allsums+=( "? x $table = $m:$size" ) ;;
        esac
        ((--size))
    done
}

# prep rounding
# 2-4 = round to 10
# 5-8 = round to 100
# 9-12 = round to 1000
function prep_rounding () {
    local roundto
    case $table in
        2|3|4)
            roundto=10
            ;;
        5|6|7|8)
            roundto=100
            ;;
        *)  roundto=1000
            ;;
    esac
    
    while [[ $size -gt 0 ]] ; do
        #local base=$(((RANDOM % 10) * roundto))
        local base=$((size * roundto))
        local delta=$((RANDOM % (roundto/2)))
        if [[ $((size % 2)) = 0 ]] ; then
            [[ $delta = $((roundto/2)) ]] && ((--delta))
            : $base $delta $((base-delta))
            allsums+=( "$((base+delta)) rounded to nearest $roundto = ?:$base" )
        else
            : $base $delta $((base-delta))
            allsums+=( "$((base-delta)) rounded to nearest $roundto = ?:$base" )
        fi
        ((--size))
    done
}

function init_table () {
    local table=$1
    local size=$2
    case $op in
        divide) prep_divide ;;
        times) prep_times ;;
        add) prep_add ;;
        subtract) prep_subtract ;;
        mixed) prep_mixed ;;
        rounding) prep_rounding ;;
        *) echo "operation must be divide/times/add/subtract/rounding - don't recognise $op" >&2 ; exit 1
    esac
}

declare -a tables
# initialise the tables
if [[ -z $* ]] ; then
    tables=( $((2+RANDOM%11)) )
    init_table ${tables} $size
else
    for t in "$@" ; do
        tables+=( $t )
        init_table $t $size
    done
fi

SECONDS=0
n_correct=0
n_wrong=0
declare -a answers

# black blue green cyan red magenta yellow white
# bg:fg:correct:wrong
colours=( 0:7:2:4 1:7:2:4 2:0:0:4 3:0:0:4 4:7:2:0 5:7:2:4 6:0:2:4 7:0:2:4 )

# initialise remaining sums list
w=0
while [[ $w -lt ${#allsums[@]} ]] ; do
    sums[$w]=$w
    ((++w))
done

trap tidy_up EXIT

# get the terminal siz
cols=$(tput cols)
lines=$(tput lines)
linenum=$((lines / 2))

starttime=$(date)

# while there are more to go
while [ ${#sums[@]} -gt 0 ] ; do
    # number of remaining questions
    n=${#sums[@]}
    # select one of the remaining questions
    w=$((RANDOM % n))
    # get the question number
    question=${sums[$w]}
    # and the question
    sum="${allsums[$question]}"
    # cache the q & a
    ans="${sum##*:}"
    sum="${sum%:*}"
    # attempt counter
    a=-1
    # pick a colour set
    bg=${colours[$((RANDOM % 8))]}
    wrong=${bg##*:}
    bg=${bg%:*}
    correct=${bg##*:}
    bg=${bg%:*}
    fg=${bg##*:}
    bg=${bg%:*}

    #while [[ $a -ne $ans ]] ; do
    while [[ $a -ne $ans ]] ; do
        # set the background
        tput setb $bg
	tput setf $fg
        tput clear
        qs1="${sum%%\?*}"
        qs2="${sum##*\?}"
        colnum=$(( (cols-${#sum}-2) / 2 ))
        tput cup $linenum $colnum
        echo -n "${qs1}"

        # save cursor position at ?
	tput sc

        # remainder of question
        echo -n " ?${qs2}"

        # make cursor visible and in the correct place
        tput rc
	tput cvvis
        # read answer
	flush
        a=""
        while true ; do
            # get a character
            read -N 1 -s c
            # not sure what can cause this...
            [[ $? -eq 0 ]] || exit
            # see what it is
            case "$c" in
                [0-9-])
                    # digit or -
                    a="$a$c"
                    ;;
                "")
                    # enter gives empty string
                    [[ -n "$a" ]] && break
                    ;;
                [Zz])
                    # quit
                    exit
                    ;;
                $'\x7F')
                    # delete last character
                    [[ -n $a ]] && a="${a:0:${#a}-1}"
                    ;;
                *)
                    # anything else is ignored
            esac
            tput rc
            echo -n "${a} ?${qs2} "
            moveright "$a"
        done

        # move to correct place to print tick or cross
        # (over the top of the ?)
        tput rc
        echo -n "${a} ?${qs2}"
	moveright "${a}" 1
	tput civis
	tput bold
        # if the answer was correct
	if [[ $a -ge 0 && $a -eq $ans ]] ; then
	    tput setf $correct
	    echo -n "✓"
	    tput oc
	    sleep 0.5
	    aa="$(tput setf 2)✓"
	    ((++n_correct))
	else
            # else it was wrong
	    tput setf $wrong
	    echo -n "X"
	    sleep 0.5
	    aa="$(tput setf 4)X"
	    ((++n_wrong))
	fi
	tput sgr0
        # remember the answers given to this question
        answers[$question]="${answers[$question]:+${answers[$question]}/}$(tput setf 7)$(printf "%3d" $a) $aa"

        # break out if necessary (or keep asking same question)
	[[ $mode == oneshot ]] && break
    done
    # record that this sum is done
    unset sums[$w]
    sums=( "${sums[@]}" )
done

tidy_up

echo -e "You took $SECONDS seconds and your results are:\n"

[[ -n $logfile ]] && {
    cat >>$logfile <<HERE
===============================================================
Start time:     $starttime
Finish time:    $(date)
Elapsed time:   $SECONDS
Test selection: $op
Table:          $tables
Table size:     $size
Number wrong:   $n_wrong
Mode:           $mode

HERE
}

w=${#allsums[@]}
w=${#allsums[@]}
while [[ $((--w)) -ge 0 ]] ; do
    tput setf 7
    s="${allsums[$w]}"
    x="${s##*:}"
    s="${s%:*}"
    read a b c d e <<<$s
    if [[ $a = \? ]] ; then
        a="$(tput setf 6)  $a$(tput setf 7)"
        aa="  ?"
    else
        a=$(printf "%3s" "$a")
        aa="$a"
    fi
    if [[ $c = \? ]] ; then
        c="$(tput setf 6)  $c$(tput setf 7)"
        cc="  ?"
    else
        c=$(printf "%3s" "$c")
        cc="$c"
    fi
    if [[ $e = \? ]] ; then
        e="$(tput setf 6)  $e$(tput setf 7)"
        ee="  ?"
    else
        e=$(printf "%3s" "$e")
        ee="$e"
    fi
    y=
    [[ "${answers[$w]}" = *X ]] && y="$(tput setf 7) : $(tput setf 3)Answer is $x$(tput setf 7)"
    printf "\t%s %s %s %s %s : %s%s\n" "$a" "$b" "$c" "$d" "$e" "${answers[$w]}" "$y"
    [[ -n $logfile ]] && {
	echo "$aa $b $cc $d $ee    ${answers[$w]//${escseq}/}"
    } >>$logfile
done

echo
[[ -n $logfile ]] && echo "" >>$logfile

if [[ $n_wrong -eq 0 ]] ; then
    tput setf 2
    echo "Congratulations, you got them all correct ☺"
else
    tput setf 4
    echo "Sorry, you got $n_wrong wrong ☹"
fi
tput setf 7
echo
tput civis
echo -n "Press enter to continue..."
flush
read x

