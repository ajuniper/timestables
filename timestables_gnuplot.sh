#!/bin/bash
# p1=results file

# Start time:     Tue Jul 21 08:28:58 BST 2015
# Elapsed time:   91
# Table:          2
# Number wrong:   1
a='
BEGIN{
    FS=":[[:space:]]+"
}

/^Start time/ {
    #start=strftime("%s",$2)
    c=sprintf("date -d \"%s\" +%%s",$2)
    c | getline start;
    close(c)
}

/^Elapsed time/ {
    duration=$2
}

/^Table:/ {
    table=$2
}

/^Number wrong/ {
    wrong=$2
    tables[table]=tables[table] sprintf("%d %d %d %d\n",table,start,duration,wrong)
}
END {
    for(i=1;i<=12;++i) {
        if (tables[i] != "") {
	    printf "%s\"-\" using 2:3:(sqrt($4)) title \"%dx\" with linespoints lt 1 pt %d lc %d ps variable \\\n",comma,i,(i>10)?5:7,i
            comma=", "
        }
    }
    printf "\n"
    for(i=1;i<=12;++i) {
        if (tables[i] != "") {
	    printf "%sEOF\n",tables[i]
        }
    }
}
'

{
cat <<HERE

set terminal wxt size $(xrandr | awk '/\*/{sub(/x/,",");print $1; exit}')
set xdata time
#set timefmt "%a %b %d %H:%M:%S BST %Y"
set timefmt "%s"

plot \\
HERE

awk "$a" $1

cat <<HERE
pause mouse

HERE
} | gnuplot
