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
        echo "  - 0 - if the leader exist"
        echo "  - 1 - if the leader do not exist"
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
length=${#ZK_HOSTS[@]}
FOLLOWERS=$(expr $length - 1)
LEADERS=1

STATE_FOLLOWER=0
STATE_DOWN=0
STATE_LEADER=0
declare -A NODES
VERBOSE=${v:-false}

get_nodeby_status(){
	nodes=()
#	echo "[DF] ${!NODES[@]}"
	for x in "${!NODES[@]}"
	do
		#echo "[DF] $x == ${NODES[$x]}"
		if [[ $1 = ${NODES[$x]} ]]
		then
			nodes+=($x)
		fi
	done
	echo ${nodes[@]}
}

for node in ${ZK_HOSTS[@]}
do

	if [[ $VERBOSE = true && ! $(nc -z -w2 ${node} $ZK_PORT 2> /dev/null ) ]]
	then
	        echo "Zookeeper Port [$ZK_PORT] on node [${node}] is closed."
	fi
	if [[ $(echo "stats" | nc ${node} $ZK_PORT 2> /dev/null | awk '/Mode:/ {print $2}') = 'follower' ]]
	then
		NODES+=([$node]='follower')		
		STATE_FOLLOWER=$( expr $STATE_FOLLOWER + 1 )
	elif [[ $(echo "stats" | nc ${node} $ZK_PORT 2> /dev/null | awk '/Mode:/ {print $2}') = 'leader' ]]
	then
		NODES+=([$node]='leader')		
		STATE_LEADER=$( expr $STATE_LEADER + 1 )
	else
		NODES+=([$node]='down')
		STATE_DOWN=$( expr $STATE_DOWN + 1 )
	fi
done

#echo "[D] ${!NODES[@]}"
#echo "[D] $(get_nodeby_status 'follower')"

if [[ $VERBOSE = true && $FOLLOWERS -ne $STATE_FOLLOWER ]]
then
	echo "NOT OK"
	echo "NODE $(get_nodeby_status 'down') is down or not responding."
elif [[ $VERBOSE = true && $FOLLOWERS -eq $STATE_FOLLOWER && $LEADERS -eq $STATE_LEADER ]]
then
	echo "OK"
	echo "Zookeeper Cluster has 2 followers: [$(get_nodeby_status 'follower')]"
	echo "Zookeeper Cluster has 1 leader: [$(get_nodeby_status 'leader')]"
elif [[ $VERBOSE = true && $LEADERS -ne $STATE_LEADER ]]
then
	echo "NOT OK"
	echo "Zookeeper Cluster has too many leaders: [$(get_nodeby_status 'leader')] should have 1"
else

	if [[ $FOLLOWERS -eq $STATE_FOLLOWER && $LEADERS -eq $STATE_LEADER ]]
	then
		echo 0
	elif [[ $FOLLOWERS -ne $STATE_FOLLOWER ]]
	then
		echo 1
	elif [[ $LEADERS -ne $STATE_LEADER ]]
	then 
		echo 1
	else
		echo 1
	fi
fi

