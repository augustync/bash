#!/bin/bash

KFK_BIN_PATH="/srv/kafka/current/kafka_2.11-2.4.1/bin"
KFK_JMX_CMD="kafka-run-class.sh kafka.tools.JmxTool"
QUERY='kafka.server:type=ReplicaManager,name=UnderReplicatedPartitions'
JMX_PORT=9999

print_usage(){
        echo
        echo 'Usage:'
        echo -e "\t$(basename $0) [--help|-h] [--brokers|-b node1,node2,node3,...] [--jmx-port|-p $JMX_PORT] [--skip-broker|-s node1] [--kafka-path|-k $KFK_BIN_PATH] [--verbose|-v]\n"
        printf "\t\t%-20s \t %-4s \t %-50s \n" "--help" "-h"  "display this help and exit"
        printf "\t\t%-20s \t %-4s \t %-50s \n" "--verbose" "-v"  "display more messages and details"
        printf "\t\t%-20s \t %-4s \t %-50s \n" "--brokers" "-b"  "list of Kafka nodes, separated with comma: node1,node2,node3,..."
        printf "\t\t%-20s \t %-4s \t %-50s \n" "--jmx-port" "-p"  "JMX port, default is $JMX_PORT"
        printf "\t\t%-20s \t %-4s \t %-50s \n" "--skip-broker" "-s"  "broker hostname which is out of cluster ex. node1"
        printf "\t\t%-20s \t %-4s \t %-50s \n" "--kafka-path" "-k"  "Path to Kafka binary, default is $KFK_BIN_PATH"
        echo
        echo "Script will return a number of UnderReplicatedPartitions, (| ISR | < | current replicas |). "
	echo "Replicas that are added as part of a reassignment will not count toward this value. "
	echo "Alert if value is greater than 0."
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
    "--skip-broker")   set -- "$@" "-s" ;;
    "--kafka-path")   set -- "$@" "-k" ;;
    *)        set -- "$@" "$arg"
  esac
done

# Default behavior
bflag=true

# Parse short options
OPTIND=1
while getopts "hvb:p:s:k:" opt
do
  case "$opt" in
    "h") print_usage; exit 0 ;;
    "v") v=true ;;
    "b") bflag=false; b=$OPTARG ;;
    "p") p=$OPTARG ;;
    "s") s=$OPTARG ;;
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

IFS=',' read -r -a BROKERS <<< "${b}"
JMX_PORT=${p:-$JMX_PORT}
KFK_BIN_PATH=${k:-"$KFK_BIN_PATH"}
VERBOSE=${v:-false}
PATCHED_NODE=${s:-''}
for index in ${!BROKERS[@]}
do
	if [[ ${BROKERS[$index]} != $PATCHED_NODE ]]
	then
		NEW_BROKERS+=( ${BROKERS[$index]} )
	fi
done
BROKERS=( ${NEW_BROKERS[@]} )
unset NEW_BROKERS

sum_values=0

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
	sum_values=$( expr $sum_values + $value )
done



if $VERBOSE
then 
	printf "%-30s: %-10s\n" "UnderReplicatedPartitions" $sum_value
	if [[ $sum_values -eq 0 ]]
	then
		echo "Cluster healthy, all replica in sync"
	else
		echo "Cluster unhealthy, partitions under replication count $sum_value"
	fi
else
	echo $sum_values
fi
