#!/bin/bash

JMX_PORT=9999
QUERY='kafka.server:type=ReplicaManager,name=LeaderCount'
KFK_BIN_PATH="/srv/kafka/current/kafka_2.11-2.4.1/bin"
KFK_JMX_CMD="kafka-run-class.sh kafka.tools.JmxTool"

print_usage(){
        echo
        echo 'Usage:'
        echo -e "\t$(basename $0) [--help|-h] [--brokers|-b node1,node2,node3,...] [--jmx-port|-p $JMX_PORT] [--controller|-c node1] [--kafka-path|-k $KFK_BIN_PATH] [--verbose|-v]\n"
        printf "\t\t%-20s \t %-4s \t %-50s \n" "--help" "-h"  "display this help and exit"
        printf "\t\t%-20s \t %-4s \t %-50s \n" "--verbose" "-v"  "display more messages and details"
        printf "\t\t%-20s \t %-4s \t %-50s \n" "--brokers" "-b"  "list of Kafka nodes, separated with comma: node1,node2,node3,..."
        printf "\t\t%-20s \t %-4s \t %-50s \n" "--jmx-port" "-p"  "JMX port, default is $JMX_PORT"
        printf "\t\t%-20s \t %-4s \t %-50s \n" "--controller" "-c"  "controller hostname ex: node1"
        printf "\t\t%-20s \t %-4s \t %-50s \n" "--kafka-path" "-k"  "path to Kafka binary, default is $KFK_BIN_PATH"
        echo
        echo "Script will return the sequence of nodes to patch"
        echo
        exit 1
}

for arg in "$@"; do
  shift
  case "$arg" in
    "--help") set -- "$@" "-h" ;;
    "--verbose")   set -- "$@" "-v" ;;
    "--brokers") set -- "$@" "-b" ;;
    "--jmx-port")   set -- "$@" "-p" ;;
    "--controller")   set -- "$@" "-c" ;;
    "--kafka-path")   set -- "$@" "-k" ;;
    *)        set -- "$@" "$arg"
  esac
done

# Default behavior
bflag=true
cflag=true

# Parse short options
OPTIND=1
while getopts "hvb:p:c:k:" opt
do
  case "$opt" in
    "h") print_usage; exit 0 ;;
    "v") v=true ;;
    "b") bflag=false; b=$OPTARG ;;
    "p") p=$OPTARG ;;
    "c") cflag=false; c=$OPTARG ;;
    "k") k=$OPTARG ;;
    "?") print_usage >&2; exit 1 ;;
  esac
done
if ((OPTIND == 1))
then
    print_usage;
fi

shift $(expr $OPTIND - 1)

if $bflag
then
        echo "Option --brokers|-b need to be specifaied."
        print_usage;
fi

if $cflag
then
        echo "Option --controller|-c need to be specifaied."
        print_usage;
fi

IFS=',' read -r -a BROKERS <<< "${b}"
declare -A LEADERS  

CONTROLLER=${c:-''}
JMX_PORT=${p:-$JMX_PORT}
KFK_BIN_PATH=${k:-"$KFK_BIN_PATH"}
VERBOSE=${v:-false}

for broker in "${BROKERS[@]}"
do

        if [[ ! $(nc -z -w2 $broker $JMX_PORT 2>/dev/null) ]]
        then
                if $VERBOSE
                then
                        echo "JMX Port [$JMX_PORT] on node [$broker] is closed."
                fi
                continue
        fi

	JMX_HOST=$broker
	JMX_URI="service:jmx:rmi:///jndi/rmi://$JMX_HOST:$JMX_PORT/jmxrmi"
	KFK_JMX_CMD_ARGS="--object-name $QUERY --one-time true --report-format properties --jmx-url $JMX_URI"
	val_str=$($KFK_BIN_PATH/$KFK_JMX_CMD $KFK_JMX_CMD_ARGS 2> /dev/null | grep -oE 'Value=.*')
	value=${val_str:6}
	LEADERS+=([$broker]=$value)
done

if $VERBOSE
then
	echo "Leader Partitions Count per node"
	printf "%-20s: %-10s\n" "Node" "Count"
	for broker in "${!LEADERS[@]}"
	do
	        printf "%-20s: %-10s\n" "$broker" "${LEADERS[$broker]}"
	done | sort -nr -k3
	echo 
	echo "Restart Sequence"
fi

for broker in "${!LEADERS[@]}"
do
	echo "$broker : ${LEADERS[$broker]}"
done | sort -n -k3 | awk "!/$CONTROLLER/ {print \$1}" 
echo $CONTROLLER
