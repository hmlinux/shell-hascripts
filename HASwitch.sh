#!/bin/bash
#ha switch script for ansible

HA_GROUP_NAME="""$1"""
STATE=""
LOGFILE=`pwd`/haswitch.log
HA_MODE=$2

#MySQL connect information
HOST="localhost"
USER="root"
PASSWD="123456"
DB="ha"

TMPFILE1=/tmp/.${HA_GROUP_NAME}0.tmp
TMPFILE2=/tmp/.${HA_GROUP_NAME}1.tmp
TMPFILE3=/tmp/.${HA_GROUP_NAME}2.tmp
START_M=("")
START_S=("")
STOP_M=("")
STOP_S=("")
SWITCH_RESULT=("")
ERROR_LOG=`pwd`/haswitch_error.log

connect_db() {
    CONN="mysql -u$USER -p$PASSWD -h$HOST --connect-timeout 6"
    SQL0="SELECT EQUIPMEMT_IP,IS_ACTIVE,SERVICE_COMMAND FROM HA_EQUIPMENT WHERE EQUIPMEMT_GROUP = '${HA_GROUP_NAME}' AND IS_ACTIVE = '0' ORDER BY PRIORITY_LEVEL;"
    SQL1="SELECT EQUIPMEMT_IP,IS_ACTIVE,SERVICE_COMMAND FROM HA_EQUIPMENT WHERE EQUIPMEMT_GROUP = '${HA_GROUP_NAME}' AND IS_ACTIVE = '1' ORDER BY PRIORITY_LEVEL;"
    SQL3="SELECT EQUIPMEMT_IP,IS_ACTIVE,SERVICE_COMMAND FROM HA_EQUIPMENT WHERE EQUIPMEMT_GROUP = '${HA_GROUP_NAME}' ORDER BY IS_ACTIVE DESC,PRIORITY_LEVEL;"
    
    $CONN 2>/dev/null $DB -e "$SQL0" | sed 1d > $TMPFILE1
    $CONN 2>/dev/null $DB -e "$SQL1" | sed 1d > $TMPFILE2
    $CONN 2>/dev/null $DB -e "$SQL3" | sed 1d > $TMPFILE3

    readlines1=`cat $TMPFILE1 2>/dev/null`
    readlines2=`cat $TMPFILE2 2>/dev/null`
    readlines3=`cat $TMPFILE3 2>/dev/null`
    if [ "$readline1" == "" -a "$readlines2" == "" -a "$readlines3" == "" ];then
        printf "No found the $HA_GROUP_NAME HA group or service.\n\n"
        rm -f $TMPFILE1; rm -f $TMPFILE2; rm -f $TMPFILE3
        exit 1
    fi
}

service_status() {
    connect_db
    echo -e "[HASwitch $HA_GROUP_NAME] Check All Services:"
    HOSTS=(`cat $TMPFILE3 | awk '{print $1}'`)
    INDEX=${#HOSTS[@]}
    OLD_IFS="$IFS"
    IFS=","
    for (( i=0;i<$INDEX;i++ ));do
        #SERVICES=("`cat $TMPFILE3 | grep "\b${HOSTS[$i]}\b" | awk '{print $3}'`")
        SERVICES_LINE=("`cat $TMPFILE3 | grep "\b${HOSTS[$i]}\b" | awk '{$1="";$2="";print $0}' | sed 's/^[ \t]*//g'`")
        IFS=$'\n'
        for SERVICES in $SERVICES_LINE;do
            IFS=','
            for service in $SERVICES;do
                CHECK_OS=`cat /etc/ansible/hosts | grep ${HOSTS[$i]} | grep -Eio "\bwinrm\b"`
                if [ "$CHECK_OS" == "winrm" ];then
                    printf "checking-${HOSTS[$i]}-$service-failed;\n"
                else
                    STATUS=`ansible ${HOSTS[$i]} -m shell -a "/etc/init.d/$service status" 2>$ERROR_LOG | head -1 | grep -Eio "SUCCESS"`
                    if [ "$STATUS" == "SUCCESS" ];then
                        printf "checking-${HOSTS[$i]}-$service-running;\n"
                    else
                        printf "checking-${HOSTS[$i]}-$service-stopped;\n"
                    fi
                fi
            done
        done
    done
    IFS="$OLD_IFS"
}

stop_master() {
    master=(`tac $TMPFILE1 | awk '{print $1}'`)
    length=${#master[@]}
    OLD_IFS="$IFS"
    IFS=","
    echo -e "`date "+%Y-%m-%d %H:%M:%S"` Stop the master service"
    for (( i=0;i<$length;i++ ));do
        #service=(`cat $TMPFILE1 | grep "\b${master[$i]}\b" | awk '{print $3}' | sed 's#,# #g'`)
        service=("`cat $TMPFILE1 | grep "\b${master[$i]}\b" | grep "\b0\b" | awk '{$1="";$2="";print $0}' | sed 's/^[ \t]*//g' | awk -F',' '{for(i=NF;i>0;i--) printf("%s,",$i);printf "\n"}' | sed 's/,$//g'`")
        service_sum=${#service[@]}
        IFS=$'\n'
        for (( j=0;j<$service_sum;j++ ));do
            IFS=','
            for service in ${service[$j]};do

                printf "`date "+%Y-%m-%d %H:%M:%S"` [Stopping] ${service[$j]} server on ${master[$i]}... "
                CHECK_OS=`cat /etc/ansible/hosts | grep ${master[$i]} | grep -Eio "\bwinrm\b"`
                if [ "$CHECK_OS" == "winrm" ];then
                    #STOP=`ansible ${master[$i]} -m win_shell -a """net stop ${service[$j]}""" | head -1 | grep -Eio "SUCCESS"`
                    STOP=`ansible ${master[$i]} -m win_shell -a """net stop ${service[$j]}""" | sed -n '2p' | awk -F"[. ]" '{print $(NF-1)}'`
                    if [ "$STOP" == "stopping" ];then
                        printf "SUCCESS\n"
                    elif [ "$STOP" == "started" ];then
                        printf "STOPPED\n"
                    else
                        STOP_M=("FAILED")
                        printf "FAILED\n"
                    fi
                else
                    STOP=`ansible ${master[$i]} -m shell -a "/etc/init.d/${service[$j]} stop" 2>$ERROR_LOG | head -1 | grep -Eio "SUCCESS"`
                    if [ "$STOP" == "SUCCESS" ];then
                        printf "SUCCESS\n"
                    else
                        STOP_M=("FAILED")
                        printf "FAILED\n"
                    fi
                fi
            done
        done
    done
    IFS="$OLD_IFS"
}

start_master() {
    master=(`cat $TMPFILE1 | awk '{print $1}'`)
    length=${#master[@]}
    OLD_IFS="$IFS"
    IFS=","
    echo -e "`date "+%Y-%m-%d %H:%M:%S"` Start the master service"
    for (( i=0;i<$length;i++ ));do
        #service=(`cat $TMPFILE1 | grep "\b${master[$i]}\b" | awk '{print $3}' | sed 's#,# #g'`)
        service=("`cat $TMPFILE1 | grep "\b${master[$i]}\b" | grep "\b0\b" | awk '{$1="";$2="";print $0}' | sed 's/^[ \t]*//g'`")
        service_sum=${#service[@]}
        IFS=$'\n'
        for (( j=0;j<$service_sum;j++ ));do
            IFS=','
            for service in ${service[$j]};do

                printf "`date "+%Y-%m-%d %H:%M:%S"` [Starting] ${service[$j]} server on ${master[$i]}... "
                CHECK_OS=`cat /etc/ansible/hosts | grep ${master[$i]} | grep -Eio "\bwinrm\b"`
                if [ "$CHECK_OS" == "winrm" ];then
                    #START=`ansible ${master[$i]} -m win_shell -a """net start ${service[$j]}""" | head -1 | grep -Eio "SUCCESS"`
                    START=`ansible ${master[$i]} -m win_shell -a """net start ${service[$j]}""" | sed -n '2p' | awk -F"[. ]" '{print $(NF-1)}'`
                    if [ "$START" == "starting" ];then
                        printf "SUCCESS\n"
                    elif [ "$START" == "started" ];then
                        printf "STARTED\n"
                    else
                        START_M=("FAILED")
                        printf "FAILED\n"
                        break
                    fi
                else
                    STATUS=`ansible ${master[$i]} -m shell -a "/etc/init.d/${service[$j]} status" 2>$ERROR_LOG | head -1 | grep -Eio "SUCCESS"`
                    if [ "$STATUS" != "SUCCESS" ];then
                        START=`ansible ${master[$i]} -m shell -a "/etc/init.d/${service[$j]} start" 2>$ERROR_LOG | head -1 | grep -Eio "SUCCESS"`
                        if [ "$START" == "SUCCESS" ];then
                            printf "SUCCESS\n"
                        else
                            START_M=("FAILED")
                            printf "FAILED\n"
                            break
                        fi
                    else
                        printf "${service[$j]} is already start.\n"
                    fi
                fi
            done
        done
    done
    IFS="$OLD_IFS"
}

stop_slave() {
    slave=(`tac $TMPFILE2 | awk '{print $1}'`)
    length=${#slave[@]}
    OLD_IFS="$IFS"
    IFS=","
    echo -e "`date "+%Y-%m-%d %H:%M:%S"` Stop the slave service"
    for (( i=0;i<$length;i++ ));do
        #service=(`cat $TMPFILE2 | grep "\b${slave[$i]}\b" | awk '{print $3}' | sed 's#,# #g'`)
        service=("`cat $TMPFILE2 | grep "\b${slave[$i]}\b" | grep "\b1\b" | awk '{$1="";$2="";print $0}' | sed 's/^[ \t]*//g' | awk -F',' '{for(i=NF;i>0;i--) printf("%s,",$i);printf "\n"}' | sed 's/,$//g'`")
        service_sum=${#service[@]}
        IFS=$'\n'
        for (( j=0;j<$service_sum;j++ ));do
            IFS=','
            for service in ${service[$j]};do

                printf "`date "+%Y-%m-%d %H:%M:%S"` [Stopping] ${service[$j]} server on ${slave[$i]}... "
                CHECK_OS=`cat /etc/ansible/hosts | grep ${slave[$i]} | grep -Eio "\bwinrm\b"`
                if [ "$CHECK_OS" == "winrm" ];then
                    #STOP=`ansible ${slave[$i]} -m win_shell -a """net stop ${service[$j]}""" | head -1 | grep -Eio "SUCCESS"`
                    STOP=`ansible ${slave[$i]} -m win_shell -a """net stop ${service[$j]}""" | sed -n '2p' | awk -F"[. ]" '{print $(NF-1)}'`
                    if [ "$STOP" == "stopping" ];then
                        printf "SUCCESS\n"
                    elif [ "$STOP" == "started" ];then
                        printf "STOPPED\n"
                    else
                        STOP_S=("FAILED")
                        printf "FAILED\n"
                    fi
                else
                    STOP=`ansible ${slave[$i]} -m shell -a "/etc/init.d/${service[$j]} stop" 2>$ERROR_LOG | head -1 | grep -Eio "SUCCESS"`
                    if [ "$STOP" == "SUCCESS" ];then
                        printf "SUCCESS\n"
                    else
                        STOP_S=("FAILED")
                        printf "FAILED\n"
                    fi
                fi
            done
        done
    done
    IFS="$OLD_IFS"
}

start_slave() {
    slave=(`cat $TMPFILE2 | awk '{print $1}'`)
    length=${#slave[@]}
    OLD_IFS="$IFS"
    IFS=","
    echo -e "`date "+%Y-%m-%d %H:%M:%S"` Start the slave service"
    for (( i=0;i<$length;i++ ));do
        #service=(`cat $TMPFILE2 | grep "\b${slave[$i]}\b" | awk '{print $3}' | sed 's#,# #g'`)
        service=("`cat $TMPFILE2 | grep "\b${slave[$i]}\b" | grep "\b1\b" | awk '{$1="";$2="";print $0}' | sed 's/^[ \t]*//g'`")
        service_sum=${#service[@]}
        IFS=$'\n'
        for (( j=0;j<$service_sum;j++ ));do
            IFS=','
            for service in ${service[$j]};do
           
                printf "`date "+%Y-%m-%d %H:%M:%S"` [Starting] ${service[$j]} server on ${slave[$i]}... "
                CHECK_OS=`cat /etc/ansible/hosts | grep ${slave[$i]} | grep -Eio "\bwinrm\b"`
                if [ "$CHECK_OS" == "winrm" ];then
                    #START=`ansible ${slave[$i]} -m win_shell -a """net start ${service[$j]}""" | head -1 | grep -Eio "SUCCESS"`
                    START=`ansible ${slave[$i]} -m win_shell -a """net start ${service[$j]}""" | sed -n '2p' | awk -F"[. ]" '{print $(NF-1)}'`
                    if [ "$START" == "starting" ];then
                        printf "SUCCESS\n"
                    elif [ "$START" == "started" ];then
                        printf "STARTED\n"
                    else
                        START_S=("FAILED")
                        printf "FAILED\n"
                        break
                    fi
                else
                    STATUS=`ansible ${slave[$i]} -m shell -a "/etc/init.d/${service[$j]} status" 2>$ERROR_LOG | head -1 | grep -Eio "SUCCESS"`
                    if [ "$STATUS" != "SUCCESS" ];then
                        START=`ansible ${slave[$i]} -m shell -a "/etc/init.d/${service[$j]} start" 2>$ERROR_LOG | head -1 | grep -Eio "SUCCESS"`
                        if [ "$START" == "SUCCESS" ];then
                            printf "SUCCESS\n"
                        else
                            START_S=("FAILED")
                            printf "FAILED\n"
                            break
                        fi
                    else
                        printf "${service[$j]} is already start.\n"
                    fi
                fi
            done
        done
    done
    IFS="$OLD_IFS"
}

###start all services
start_server_group_services() {
    HOSTS=(`cat $TMPFILE3 | awk '{print $1}'`)
    INDEX=${#HOSTS[@]}   
    OLD_IFS="$IFS"
    IFS=","
    for (( i=0;i<$INDEX;i++ ));do
        #SERVICES=("`cat $TMPFILE3 | grep "\b${HOSTS[$i]}\b" | awk '{print $3}'`")
        SERVICES_LINE=("`cat $TMPFILE3 | grep "\b${HOSTS[$i]}\b" | awk '{$1="";$2="";print $0}' | sed 's/^[ \t]*//g'`")
        IFS=$'\n'
        for SERVICES in $SERVICES_LINE;do
            IFS=","
            for service in $SERVICES;do
                CHECK_OS=`cat /etc/ansible/hosts | grep ${HOSTS[$i]} | grep -Eio "\bwinrm\b"`
                if [ "$CHECK_OS" == "winrm" ];then
                    #ansible ${HOSTS[$i]} -m win_shell -a """net start ${service}"""
                    #START=`ansible ${HOSTS[$i]} -m win_shell -a """net start ${service}""" | head -1 | grep -Eio "SUCCESS"`
                    START=`ansible ${HOSTS[$i]} -m win_shell -a """net start ${service}""" | sed -n '2p' | awk -F"[. ]" '{print $(NF-1)}'`
                    if [ "$START" == "starting" ];then
                        printf "starting-${HOSTS[$i]}-${service}-success;\n"
                    elif [ "$START" == "started" ];then
                        printf "starting-${HOSTS[$i]}-${service}-running;\n"
                    else
                        printf "starting-${HOSTS[$i]}-${service}-failed;\n"
                    fi
                else
                    STATUS=`ansible ${HOSTS[$i]} -m shell -a "/etc/init.d/$service status" 2>$ERROR_LOG | head -1 | grep -Eio "SUCCESS"`
                    if [ "$STATUS" != "SUCCESS" ];then
                        START=`ansible ${HOSTS[$i]} -m shell -a "/etc/init.d/$service start" 2>$ERROR_LOG | head -1 | grep -Eio "SUCCESS"`
                        if [ "$START" != "SUCCESS" ];then
                            printf "starting-${HOSTS[$i]}-$service-failed;\n"
                        else
                            printf "starting-${HOSTS[$i]}-$service-success;\n"
                        fi
                    else
                        printf "starting-${HOSTS[$i]}-$service-running;\n"
                    fi
                fi
            done
        done
    done
    IFS="$OLD_IFS"
}

###stop all services
stop_server_group_services() {
    HOSTS=(`tac $TMPFILE3 | awk '{print $1}'`)
    INDEX=${#HOSTS[@]}
    OLD_IFS="$IFS"
    IFS=","
    for (( i=0;i<$INDEX;i++ ));do
        #SERVICES=("`cat $TMPFILE3 | grep "\b${HOSTS[$i]}\b" | awk '{print $3}'`")
        SERVICES_LINE=("`cat $TMPFILE3 | grep "\b${HOSTS[$i]}\b" | awk '{$1="";$2="";print $0}' | sed 's/^[ \t]*//g' | awk -F',' '{for(i=NF;i>0;i--) printf("%s,",$i);printf "\n"}' | sed 's/,$//g'`")
        IFS=$'\n'
        for SERVICES in $SERVICES_LINE;do
            IFS=','
            for service in $SERVICES;do
                CHECK_OS=`cat /etc/ansible/hosts | grep ${HOSTS[$i]} | grep -Eio "\bwinrm\b"`
                if [ "$CHECK_OS" == "winrm" ];then
                    #STOP=`ansible ${HOSTS[$i]} -m win_shell -a """net stop ${service}""" | head -1 | grep -Eio "SUCCESS"`
                    STOP=`ansible ${HOSTS[$i]} -m win_shell -a """net stop ${service}""" | sed -n '2p' | awk -F"[. ]" '{print $(NF-1)}'`
                    if [ "$STOP" == "stopping" ];then
                        printf "stopping-${HOSTS[$i]}-$service-success;\n"
                    elif [ "$STOP" == "started" ];then
                        printf "stopping-${HOSTS[$i]}-$service-stopped;\n"
                    else
                        printf "stopping-${HOSTS[$i]}-$service-failed;\n"
                    fi
                else
                    STOP=`ansible ${HOSTS[$i]} -m shell -a "/etc/init.d/$service stop" 2>$ERROR_LOG | head -1 | grep -Eio "SUCCESS"`
                    if [ "$STOP" != "SUCCESS" ];then
                        printf "stopping-${HOSTS[$i]}-$service-failed;\n"
                    else
                        printf "stopping-${HOSTS[$i]}-$service-success;\n"
                    fi
                fi
            done
        done
    done
    IFS="$OLD_IFS"
}


all_start_main() {
    echo -e "[HASwitch $HA_GROUP_NAME] Start All Services:"
    connect_db
    start_server_group_services
    rm -f $TMPFILE1; rm -f $TMPFILE2
}

all_stop_main() {
    echo -e "[HASwitch $HA_GROUP_NAME] Stop All Services:"
    connect_db
    stop_server_group_services
    rm -f $TMPFILE1; rm -f $TMPFILE2
}


switch_main() {
    echo -e "[HASwitch - $HA_GROUP_NAME] -------------------------------------------------------------- [HASwitch - $HA_GROUP_NAME]"
    connect_db
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
    echo "${SWITCH_RESULT[0]}"
    rm -f $TMPFILE1; rm -f $TMPFILE2
}

switch() {
    if [ "$HA_GROUP_NAME" != "" ];then
        switch_main >> $LOGFILE
    else
        echo "ERROR: GROUP_NAME not null!"
    fi
}

startting() {
    if [ "$HA_GROUP_NAME" != "" ];then
        all_start_main >> $LOGFILE
    else
        echo "ERROR: GROUP_NAME not null!"
        exit 2
    fi
}

stopping() {
    if [ "$HA_GROUP_NAME" != "" ];then
        all_stop_main >> $LOGFILE
    else
        echo "ERROR: GROUP_NAME not null!"
        exit 2
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
    status)
        service_status
    ;;
    *)
        echo -e "USAGE: $0 [GROUP_NAME] [switch|start|stop|status]"
        exit 3
esac
