#/bin/bash

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

echo "Checking.."
#health=$(./kfk_cluster_health_check.sh -b $brokers -p $ZK_PORT -d $ZK_PATH -k $KFK_BIN_PATH)
echo $health

./kfk_cluster_health_check.sh -b $brokers -p $ZK_PORT -d $ZK_PATH -k $KFK_BIN_PATH
if [[ $? -eq 0 ]]
then
	echo "Patching sequence should be: "
	controller=$(./kfk_controller_check.sh -b $brokers -p $JMX_PORT)
	./kfk_count_leader_partitions.sh -b $brokers -p $JMX_PORT -c $controller | nl
else
	echo "Please stop patching and contact OPS to troubleshoot the cluster [$brokers]"
	exit 1
fi
