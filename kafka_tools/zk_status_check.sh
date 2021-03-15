#!/bin/bash


ZK_PORT=2181

print_usage(){
        echo
        echo 'Usage:'
        echo -e "\t$(basename $0) [--help|-h] [--zookeepers|-z node1,node2,node3,...] [--zk-port|-p 2181] [--verbose|-v]\n"
        printf "\t\t%-20s \t %-4s \t %-50s \n" "--help" "-h"  "display this help and exit"
        printf "\t\t%-20s \t %-4s \t %-50s \n" "--verbose" "-v"  "display more messages and details"
        printf "\t\t%-20s \t %-4s \t %-50s \n" "--zookeepers" "-z"  "list of Zookeeper nodes, separated with comma: node1,node2,node3,..."
        printf "\t\t%-20s \t %-4s \t %-50s \n" "--zk-port" "-p"  "Zookeeper port, default is $ZK_PORT"
        echo
        echo "Script will return [0] or [1]"
        echo "  - 0 - all zookeeper nodes are OK"
        echo "  - 1 - all zookeeper nodes are NOT OK"
        echo
}

for arg in "$@"; do
  shift
  case "$arg" in
    "--help") set -- "$@" "-h" ;;
    "--zookeepers") set -- "$@" "-z" ;;
    "--zk-port")   set -- "$@" "-p" ;;
    "--verbose")   set -- "$@" "-v" ;;
    *)        set -- "$@" "$arg"
  esac
done

# Default behavior
zflag=true

# Parse short options
OPTIND=1
while getopts "hvz:p:" opt
do
  case "$opt" in
    "h") print_usage; exit 0 ;;
    "v") v=true ;;
    "z") zflag=false; z=$OPTARG ;;
    "p") p=$OPTARG ;;
    "?") print_usage >&2; exit 1 ;;
  esac
done
if ((OPTIND == 1))
then
    print_usage;
    exit 1
fi

shift $(expr $OPTIND - 1)

if $zflag
then
        echo "Option --zookeepers|-z need to be specifaied."
        print_usage;
	exit 1
fi

IFS=',' read -r -a ZK_HOSTS <<< "${z}"
ZK_PORT=${p:-$ZK_PORT}
length=$( expr ${#ZK_HOSTS[@]} )

ALL_OK=0
BAD_NODES=()
VERBOSE=${v:-false}

for node in ${ZK_HOSTS[@]}
do

	if [[ $VERBOSE = true && ! $(nc -z -w2 ${node} $ZK_PORT 2> /dev/null ) ]]
	then
	        echo "Zookeeper Port [$ZK_PORT] on node [${node}] is closed."
	fi
	if [[ $(echo "ruok" | nc ${node} $ZK_PORT 2> /dev/null) = "imok" ]]
	then
		ALL_OK=$( expr $ALL_OK + 1 )
	else
		BAD_NODES+=($node)
	fi
done

if [[ $VERBOSE = true && $length -ne $ALL_OK ]]
then
	echo "NOT OK"
	echo "${BAD_NODES[@]}"
elif [[ $VERBOSE = true && $length -eq $ALL_OK ]]
then
	echo "OK"
else

	if [[ $length -eq $ALL_OK ]]
	then
		echo 0
	else
		echo 1
	fi
fi

