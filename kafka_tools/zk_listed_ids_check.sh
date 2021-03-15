#!/bin/bash

NUM_OF_BROKERS=3
ZK_PATH=""
ZK_PORT=2181
KFK_BIN_PATH="/srv/kafka/current/kafka_2.11-2.4.1/bin"
ZK_SHELL='zookeeper-shell.sh'


print_usage(){
        echo
        echo 'Usage:'
        echo -e "\t$(basename $0) [--help|-h] [--zookeepers|-z node1,node2,node3,...] [--zk-port|-p $ZK_PORT] [--zk-path|-d /kafka] [--num-of-nodes|-n $NUM_OF_BROKERS] [--kafka-path|-k $KFK_BIN_PATH] [--verbose|-v]\n"
        printf "\t\t%-20s \t %-4s \t %-50s \n" "--help" "-h"  "display this help and exit"
        printf "\t\t%-20s \t %-4s \t %-50s \n" "--verbose" "-v"  "display more messages and details"
        printf "\t\t%-20s \t %-4s \t %-50s \n" "--zookeepers" "-z"  "list of Zookeeper nodes, separated with comma: node1,node2,node3,..."
        printf "\t\t%-20s \t %-4s \t %-50s \n" "--zk-port" "-p"  "Zookeeper port, default is $ZK_PORT"
        printf "\t\t%-20s \t %-4s \t %-50s \n" "--zk-path" "-d"  "Zookeeper path, default is none '$ZK_PATH'"
        printf "\t\t%-20s \t %-4s \t %-50s \n" "--num-of-nodes" "-n"  "number of Kafka brokers in the cluster, default is $NUM_OF_BROKERS"
        printf "\t\t%-20s \t %-4s \t %-50s \n" "--kafka-path" "-k"  "Path to Kafka binary, default is $KFK_BIN_PATH"
        echo
        echo "Script will return [0] or [1]"
        echo "  - 0 - all brokers id are listed in zookeeper"
        echo "  - 1 - all brokers id are not listed in zookeeper"
        echo
}

for arg in "$@"; do
  shift
  case "$arg" in
    "--help") set -- "$@" "-h" ;;
    "--verbose")   set -- "$@" "-v" ;;
    "--zookeepers") set -- "$@" "-z" ;;
    "--zk-port")   set -- "$@" "-p" ;;
    "--zk-path")   set -- "$@" "-d" ;;
    "--num-of-nodes")   set -- "$@" "-n" ;;
    "--kafka-path")   set -- "$@" "-k" ;;
    *)        set -- "$@" "$arg"
  esac
done

# Default behavior
zflag=true

# Parse short options
OPTIND=1
while getopts "hvz:p:k:d:n:" opt
do
  case "$opt" in
    "h") print_usage; exit 0 ;;
    "v") v=true ;;
    "z") zflag=false; z=$OPTARG ;;
    "d") d=$OPTARG ;;
    "n") n=$OPTARG ;;
    "p") p=$OPTARG ;;
    "k") k=$OPTARG ;;
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

NUM_OF_BROKERS=${n:-$NUM_OF_BROKERS}
ZK_PATH=${d:-$ZK_PATH}
ZK_PORT=${p:-$ZK_PORT}
KFK_BIN_PATH=${k:-$KFK_BIN_PATH}
ZK_CMD="ls $ZK_PATH/brokers/ids"
VERBOSE=${v:-false}

IFS=',' read -r -a ZK_HOSTS <<< "${z}"
length=$( expr ${#ZK_HOSTS[@]} - 1 )
random_index=$((0 + $RANDOM % $length))
ZK_HOST="${ZK_HOSTS[$random_index]}:$ZK_PORT"

if [[ ! $(nc -z -w2 ${ZK_HOSTS[$random_index]} $ZK_PORT 2>/dev/null) ]]
then
	if $VERBOSE
	then
        	echo "Zookeeper Port [$ZK_PORT] on node [${ZK_HOSTS[$random_index]}] is closed."
	fi
        exit 1
fi

IDS=( $($KFK_BIN_PATH/$ZK_SHELL $ZK_HOST $ZK_CMD 2> /dev/null | grep -E "^\[.*\]$" | sed 's|[][,]||g') )

if [[ $VERBOSE = true && ${#IDS[@]} -ne $NUM_OF_BROKERS ]]
then
	echo "Missing brokers ID's in Zookeeper: [${IDS[@]}] : [$NUM_OF_BROKERS] : Number of Missing Brokers: [$( expr $NUM_OF_BROKERS - ${#IDS[@]} )]"
elif [[ $VERBOSE = true && ${#IDS[@]} -eq $NUM_OF_BROKERS ]]
then
	echo "All brokers ID's are listed in Zookeeper: [${IDS[@]}] : [$NUM_OF_BROKERS] : Number of Missing Brokers: [$( expr $NUM_OF_BROKERS - ${#IDS[@]} )]"
else
	if [[ ${#IDS[@]} -eq $NUM_OF_BROKERS ]]
	then
	# all the ids are listed in zk
		echo 0
	else
	# misssing id 
		echo 1
	fi
fi
