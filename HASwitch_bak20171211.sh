#!/bin/bash
#ha switch script for ansible

HA_GROUP_NAME=$1
STATE=""
LOGFILE=`pwd`/haswitch.log
HA_MODE=$2

#MySQL connect information
HOST="10.18.224.42"
USER="root"
PASSWD="123456"
DB="ha"

TMPFILE1=/tmp/.${HA_GROUP_NAME}0.tmp
TMPFILE2=/tmp/.${HA_GROUP_NAME}1.tmp
MASTER_SERVERS=("")
SLAVE_SERVERS=("")
START_M=("")
START_S=("")
STOP_M=("")
STOP_S=("")
SWITCH_RESULT=("")

connect_db() {
    CONN="mysql -u$USER -p$PASSWD -h$HOST"
    SQL0="SELECT EQUIPMEMT_IP,SITE_TYPR,SERVICE_COMMAND FROM HA_EQUIPMENT WHERE EQUIPMEMT_GROUP = '${HA_GROUP_NAME}' AND SITE_TYPR = '0';"
    SQL1="SELECT EQUIPMEMT_IP,SITE_TYPR,SERVICE_COMMAND FROM HA_EQUIPMENT WHERE EQUIPMEMT_GROUP = '${HA_GROUP_NAME}' AND SITE_TYPR = '1';"
    
    $CONN 2>/dev/null $DB -e "$SQL0" > $TMPFILE1
    $CONN 2>/dev/null $DB -e "$SQL1" > $TMPFILE2

    readlines1=`cat $TMPFILE1`
    readlines2=`cat $TMPFILE2`
    if [ "$readline1" == "" -a "$readlines2" == "" ];then
        printf "No found the $HA_GROUP_NAME HA group or service.\n\n"
        rm -f $TMPFILE1; rm -f $TMPFILE2
        exit 1
    fi
}

service_status() {
    master=(`cat $TMPFILE1 | sed '1d' | awk '{print $1}'`)
    slave=(`cat $TMPFILE2  | sed '1d' | awk '{print $1}'`)
    length1=${#master[@]}
    length2=${#slave[@]}

    echo -e "`date "+%Y-%m-%d %H:%M:%S"` Check the master service"
    total=0
    for (( i=0;i<$length1;i++ ));do
        servers=(`cat $TMPFILE1 | grep "\b${master[$i]}\b" | awk '{print $3}' | sed 's#,# #g'`)
        servers_sum=${#servers[@]}
        for (( j=0;j<$servers_sum;j++ ));do
            printf "`date "+%Y-%m-%d %H:%M:%S"` [Checking] ${servers[$j]} server status on ${master[$i]}... "
            STATUS=`ansible ${master[$i]} -m shell -a "/etc/init.d/${servers[$j]} status" | head -1 | awk -F"[| ]+" '{print $2}'`
            if [ "$STATUS" == "FAILED" ];then
                printf "FAILED\n"
                total=$(( $total + 1 ))
            elif [ "$STATUS" == "SUCCESS" ];then
                printf "SUCCESS\n"
            else
                exit 2
            fi
        done
    done
    if [ $total == 0 ];then
        MASTER_SERVERS=("running")
    else
        MASTER_SERVERS=("stopped")
    fi
    echo -e "Master node [$HA_GROUP_NAME] is ${MASTER_SERVERS[@]}."
}

stop_master() {
    master=(`cat $TMPFILE1 | sed '1d' | awk '{print $1}'`)
    length=${#master[@]}

    echo -e "`date "+%Y-%m-%d %H:%M:%S"` Stop the master service"
    for (( i=0;i<$length;i++ ));do
        service=(`cat $TMPFILE1 | grep "\b${master[$i]}\b" | awk '{print $3}' | sed 's#,# #g'`)
        service_sum=${#service[@]}
        for (( j=0;j<$service_sum;j++ ));do
            printf "`date "+%Y-%m-%d %H:%M:%S"` [Stopping] ${service[$j]} server on ${master[$i]}... "
            STOP=`ansible ${master[$i]} -m shell -a "/etc/init.d/${service[$j]} stop" | head -1 | grep -Eio "SUCCESS"`
            if [ "$STOP" != "SUCCESS" ];then
                STOP_M=("FAILED")
                printf "FAILED\n"
                break
            else
                printf "SUCCESS\n"
            fi
        done
    done  
}

start_master() {
    master=(`cat $TMPFILE1 | sed '1d' | awk '{print $1}'`)
    length=${#master[@]}

    echo -e "`date "+%Y-%m-%d %H:%M:%S"` Start the master service"
    for (( i=0;i<$length;i++ ));do
        service=(`cat $TMPFILE1 | grep "\b${master[$i]}\b" | awk '{print $3}' | sed 's#,# #g'`)
        service_sum=${#service[@]}
        for (( j=0;j<$service_sum;j++ ));do
            printf "`date "+%Y-%m-%d %H:%M:%S"` [Starting] ${service[$j]} server on ${master[$i]}... "
            STATUS=`ansible ${master[$i]} -m shell -a "/etc/init.d/${service[$j]} status" | head -1 | grep -Eio "SUCCESS"`
            if [ "$STATUS" != "SUCCESS" ];then           
                START=`ansible ${master[$i]} -m shell -a "/etc/init.d/${service[$j]} start" | head -1 | grep -Eio "SUCCESS"`
                if [ "$START" != "SUCCESS" ];then
                    START_M=("FAILED")
                    printf "FAILED\n"
                    break
                else
                    printf "SUCCESS\n"
                fi
            else
                printf "${service[$j]} is already start.\n"
            fi
        done
    done   
}

stop_slave() {
    slave=(`cat $TMPFILE2 | sed '1d' | awk '{print $1}'`)
    length=${#slave[@]}

    echo -e "`date "+%Y-%m-%d %H:%M:%S"` Stop the slave service"
    for (( i=0;i<$length;i++ ));do
        service=(`cat $TMPFILE2 | grep "\b${slave[$i]}\b" | awk '{print $3}' | sed 's#,# #g'`)
        service_sum=${#service[@]}
        for (( j=0;j<$service_sum;j++ ));do
            printf "`date "+%Y-%m-%d %H:%M:%S"` [Stopping] ${service[$j]} server on ${slave[$i]}... "
            STOP=`ansible ${slave[$i]} -m shell -a "/etc/init.d/${service[$j]} stop" | head -1 | grep -Eio "SUCCESS"`
            if [ "$STOP" != "SUCCESS" ];then
                STOP_S=("FAILED")
                printf "FAILED\n"
                break
            else
                printf "SUCCESS\n"
            fi
        done
    done
}

start_slave() {
    slave=(`cat $TMPFILE2 | sed '1d' | awk '{print $1}'`)
    length=${#slave[@]}

    echo -e "`date "+%Y-%m-%d %H:%M:%S"` Start the slave service"
    for (( i=0;i<$length;i++ ));do
        service=(`cat $TMPFILE2 | grep "\b${slave[$i]}\b" | awk '{print $3}' | sed 's#,# #g'`)
        service_sum=${#service[@]}
        for (( j=0;j<$service_sum;j++ ));do
            printf "`date "+%Y-%m-%d %H:%M:%S"` [Starting] ${service[$j]} server on ${slave[$i]}... "
            STATUS=`ansible ${slave[$i]} -m shell -a "/etc/init.d/${service[$j]} status" | head -1 | grep -Eio "SUCCESS"`
            if [ "$STATUS" != "SUCCESS" ];then
                START=`ansible ${slave[$i]} -m shell -a "/etc/init.d/${service[$j]} start" | head -1 | grep -Eio "SUCCESS"`
                if [ "$START" != "SUCCESS" ];then
                    START_S=("FAILED")
                    printf "FAILED\n"
                    break
                else
                    printf "SUCCESS\n"
                fi
            else
                printf "${service[$j]} is already start.\n"
            fi
        done
    done
}

###start all services



switch_to_slave() {
    printf "[MASTER TO SLAVE] ----------------------------------------------------\n"
    printf "`date "+%Y-%m-%d %H:%M:%S"` Close the master nodes service and start the slave service.\n"
    stop_master
    start_slave
    if [ "${START_S[@]}" == "FAILED" ];then
        echo "Slave services startup failed!"
        echo "roll-back to master."
        stop_slave
        start_master
        SWITCH_RESULT=("0")
        echo "roll-back to master done!"
    else
        echo "switch success!"
        SWITCH_RESULT=("1")
    fi

}

switch_to_master() {
    printf "[SLAVE TO MASTER] ----------------------------------------------------\n"
    printf "`date "+%Y-%m-%d %H:%M:%S"` Close the slave nodes service and start the master service.\n"
    stop_slave
    start_master
    if [ "${START_M[@]}" == "FAILED" ];then
        echo "Master services startup failed!"
        echo "roll-back to slave."
        stop_master
        start_slave
        SWITCH_RESULT=("0")
        echo "roll-back to slave done!"
    else
        echo "switch success!"
        SWITCH_RESULT=("1")
    fi

}

all_start() {
    printf "[START MASTER] ----------------------------------------------------\n"
    start_master
    if [ "${START_M[@]}" == "FAILED" ];then
        echo "Master services startup failed!"
    else
        echo "Master services started successfully."
    fi
    printf "[START SLAVE] ----------------------------------------------------\n"
    start_slave
    if [ "${START_S[@]}" == "FAILED" ];then
        echo "Slave services startup failed!"
    else
        echo "Slave services started successfully."
    fi
    if [ "${START_M[@]}" != "FAILED" -a "${START_S[@]}" != "FAILED" ];then
        SWITCH_RESULT=("1")
    else
        SWITCH_RESULT=("0")
    fi
}

all_stop() {
    printf "[STOP MASTER] ----------------------------------------------------\n"
    stop_master
    if [ "${STOP_M[@]}" == "FAILED" ];then
        echo "Master services stop failed!"
    else
        echo "Master services stop successfully."
    fi
    printf "[STOP SLAVE] ----------------------------------------------------\n"
    stop_slave
    if [ "${STOP_S[@]}" == "FAILED" ];then
        echo "Slave services stop failed!"
    else
        echo "Slave services stop successfully."
    fi
    if [ "${STOP_M[@]}" != "FAILED" -a "${STOP_S[@]}" != "FAILED" ];then
        SWITCH_RESULT=("1")
    else
        SWITCH_RESULT=("0")
    fi
}

all_start_main() {
    echo -e "[HASwitch - $HA_GROUP_NAME] -------------------------------------------------------------- [HASwitch - $HA_GROUP_NAME]"
    connect_db
    #service_status
    all_start
    echo "${SWITCH_RESULT[0]}"
    rm -f $TMPFILE1; rm -f $TMPFILE2
}

all_stop_main() {
    echo -e "[HASwitch - $HA_GROUP_NAME] -------------------------------------------------------------- [HASwitch - $HA_GROUP_NAME]"
    connect_db
    #service_status
    all_stop
    echo "${SWITCH_RESULT[0]}"
    rm -f $TMPFILE1; rm -f $TMPFILE2
}


switch_main() {
    echo -e "[HASwitch - $HA_GROUP_NAME] -------------------------------------------------------------- [HASwitch - $HA_GROUP_NAME]"
    connect_db
    service_status
    if [ "${MASTER_SERVERS[@]}" == "running" ];then
        switch_to_slave
    elif [ "${MASTER_SERVERS[@]}" == "stopped" ];then
        switch_to_master
    else
        switch_to_master
    fi
    echo "${SWITCH_RESULT[0]}"
    rm -f $TMPFILE1; rm -f $TMPFILE2
}

switch() {
    if [ "$HA_GROUP_NAME" != "" ];then
        switch_main | tee $LOGFILE
    else
        echo "ERROR: GROUP_NAME not null!"
    fi
}

startting() {
    if [ "$HA_GROUP_NAME" != "" ];then
        all_start_main | tee $LOGFILE
    else
        echo "ERROR: GROUP_NAME not null!"
    fi
}

stopping() {
    if [ "$HA_GROUP_NAME" != "" ];then
        all_stop_main | tee $LOGFILE
    else
        echo "ERROR: GROUP_NAME not null!"
    fi
}

case $HA_MODE in
    switch)
        switch
    ;;
    start)
        startting
    ;;
    stop)
        stopping
    ;;
    *)
        echo -e "USAGE: $0 [GROUP_NAME] [switch|start|stop]"
        exit 3
esac
