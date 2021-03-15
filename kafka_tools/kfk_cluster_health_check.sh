#!/bin/bash

KFK_BIN_PATH="/srv/kafka/current/kafka_2.11-2.4.1/bin"
JMX_PORT=9999
NUM_OF_BROKERS=3
ZK_PATH=""
ZK_PORT=2181

print_usage(){
        echo
        echo 'Usage:'
        echo -e "\t$(basename $0) [--help|-h] [--brokers|-b node1,node2,node3,...] [--jmx-port|-p $JMX_PORT] [--zk-path|-d /kafka] [--kafka-path|-k $KFK_BIN_PATH] [--verbose|-v]\n"
        printf "\t\t%-20s \t %-4s \t %-50s \n" "--help" "-h"  "display this help and exit"
        printf "\t\t%-20s \t %-4s \t %-50s \n" "--verbose" "-v"  "display more messages and details"
        printf "\t\t%-20s \t %-4s \t %-50s \n" "--brokers" "-b"  "list of Kafka nodes, separated with comma: node1,node2,node3,..."
        printf "\t\t%-20s \t %-4s \t %-50s \n" "--jmx-port" "-p"  "JMX port, default is $JMX_PORT"
	printf "\t\t%-20s \t %-4s \t %-50s \n" "--zk-path" "-d"  "Zookeeper path, default is none '$ZK_PATH'"
        printf "\t\t%-20s \t %-4s \t %-50s \n" "--kafka-path" "-k"  "Path to Kafka binary, default is $KFK_BIN_PATH"
        echo
        echo "Script will return node name of the controller in the cluster."
        echo "There should be only one node listed, if more then cluster is unhealty"
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
    "--zk-path")   set -- "$@" "-d" ;;
    "--kafka-path")   set -- "$@" "-k" ;;
    *)        set -- "$@" "$arg"
  esac
done

# Default behavior
bflag=true

# Parse short options
OPTIND=1
while getopts "hvb:p:d:k:" opt
do
  case "$opt" in
    "h") print_usage; exit 0 ;;
    "v") v=true ;;
    "b") bflag=false; b=$OPTARG ;;
    "p") p=$OPTARG ;;
    "d") d=$OPTARG ;;
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

brokers=$b
zk=$b
IFS=',' read -r -a BROKERS <<< "${b}"
JMX_PORT=${p:-$JMX_PORT}
KFK_BIN_PATH=${k:-"$KFK_BIN_PATH"}
NUM_OF_BROKERS=${n:-$NUM_OF_BROKERS}
ZK_PATH=${d:-$ZK_PATH}
ZK_PORT=${p:-$ZK_PORT}
ZK_CMD="ls $ZK_PATH/brokers/ids"
VERBOSE=${v:-false}

HEALTH_STAT=0

echo "Checking Cluster Kafka Cluster Health"
echo "Checking number of registred nodes in ZK"
zk_nodes_count=$(./zk_listed_ids_check.sh -z $zk -p $ZK_PORT -d $ZK_PATH -n $NUM_OF_BROKERS -k $KFK_BIN_PATH)
if [[ $? -eq 0 && $zk_nodes_count -eq 0 ]]
then
	echo "All Kafka nodes are listed in ZK"
else
	echo "Kafka cluster its missing nodes"
	HEALTH_STAT=$(expr $HEALTH_STAT + 1)
fi
echo "Controller Node check"
controller=$(./kfk_controller_check.sh -b $brokers -p $JMX_PORT)
if [[ $? -eq 0 ]]
then
	echo "Controller Node is [$controller]"
else
	echo "Controller Node check failed"
	HEALTH_STAT=$(expr $HEALTH_STAT + 1)
fi
echo "UnderReplicatedPartitions Cluster Check"
under_replica=$(./kfk_under_replica_partitions_check.sh -b $brokers -p $JMX_PORT -k $KFK_BIN_PATH)
if [[ $? -eq 0 && $under_replica -eq 0 ]]
then
	echo "UnderReplicatedPartitions looks good [$under_replica]"
elif [[ $? -eq 0 && $under_replica -ne 0 ]]
then
	echo "UnderReplicatedPartitions unsynced, number of partitions in bad state [$under_replica]"
	HEALTH_STAT=$(expr $HEALTH_STAT + 1)
else
	echo "UnderReplicatedPartitions check failed"
	HEALTH_STAT=$(expr $HEALTH_STAT + 1)
fi

if [[ $HEALTH_STAT -eq 0 ]]
then
	echo "Cluster its healthy"
	echo "Patching sequence should be: "
        seq_patch=$(./kfk_count_leader_partitions.sh -b $brokers -p $JMX_PORT -c $controller)
	var=$(echo "${seq_patch}"|tr '\n' ',')

	IFS=',' read -r -a patch <<< "${var}"
	echo ${patch[@]} | tr ' ' '\n' |nl
	read -p "Please choose the number or exit the script [Ctrl-C]: " node
	node=$( expr $node - 1 )
	echo "Putting Kafka instance down on node [${patch[$node]}]"
	ssh -qt ${patch[$node]} "initctl stop kafka"
	count=0
	while [ $count -lt 600 ]
	do

		count=$(expr $count + 1)
		echo "Check Round [$count]"
		echo
		controller=$(./kfk_controller_check.sh -b $brokers -p $JMX_PORT)

		if [[ $? -eq 0 ]]
		then
        		echo "Controller Node is [$controller]"
			CTLL=0
		else
        		echo "Controller Node check failed"
        		CTLL=1
		fi

		zk_nodes_count=$(./zk_listed_ids_check.sh -z $zk -p $ZK_PORT -d $ZK_PATH -n $NUM_OF_BROKERS -k $KFK_BIN_PATH)

		if [[ $? -eq 0 && $zk_nodes_count -eq 0 ]]
		then
        		echo "All Kafka nodes are listed in ZK"
			ZK=0
		else
        		echo "Kafka cluster its missing nodes"
			ZK=1
		fi

		if [[ $ZK -eq 0 ]]
		then
			under_replica=$(./kfk_under_replica_partitions_check.sh -b $brokers -p $JMX_PORT -k $KFK_BIN_PATH)
		else
			under_replica=$(./kfk_under_replica_partitions_check.sh -b $brokers -p $JMX_PORT -k $KFK_BIN_PATH -s ${patch[$node]})
		fi

		if [[ $under_replica -eq 0 ]]
		then
        		echo "UnderReplicatedPartitions looks good [$under_replica]"
			URP=0
		elif [[ $under_replica -ne 0 ]]
		then
        		echo "UnderReplicatedPartitions unsynced, number of partitions in bad state [$under_replica]"
			URP=1
		else
        		echo "UnderReplicatedPartitions check failed"
			URP=1
		fi

		echo
		sleep 60s
		if [[ $count -eq 3 ]]
		then
			ssh -qt ${patch[$node]} "initctl start kafka"
		fi


		if [[ $URP -eq 0 && $ZK -eq 0 && $CTLL -eq 0 ]]
		then
			echo "Patch finished, all done"
			break
		fi
		echo
	done
	exit 0
else
	echo "Please stop patching and contact OPS to troubleshoot the cluster [$brokers]"
	echo "Cluster is unhealthy"
	exit 1
fi
