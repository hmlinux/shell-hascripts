#!/bin/bash
#ha switch script for ansible

HA_GROUP_NAME="""$1"""
STATE=""
LOGFILE=`pwd`/haswitch.log
HA_STATE=$2

#MySQL connect information
HOST="10.18.224.42"
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
MASTER_CHECK=("")
BACKUP_CHECK=("")

info_log() {
    printf "$(date '+%Y-%m-%d %T') - $1"
}

connect_db() {
    CONN="mysql -u$USER -p$PASSWD -h$HOST --connect-timeout 6"
    SQL0="SELECT EQUIPMEMT_IP,EQUIPMEMT_NAME,SITE_TYPR,SERVICE_COMMAND FROM HA_EQUIPMENT WHERE EQUIPMEMT_GROUP = '${HA_GROUP_NAME}' AND SITE_TYPR = '0' ORDER BY PRIORITY_LEVEL;"
    SQL1="SELECT EQUIPMEMT_IP,EQUIPMEMT_NAME,SITE_TYPR,SERVICE_COMMAND FROM HA_EQUIPMENT WHERE EQUIPMEMT_GROUP = '${HA_GROUP_NAME}' AND SITE_TYPR = '1' ORDER BY PRIORITY_LEVEL;"
    SQL3="SELECT EQUIPMEMT_IP,EQUIPMEMT_NAME,SITE_TYPR,SERVICE_COMMAND FROM HA_EQUIPMENT WHERE EQUIPMEMT_GROUP = '${HA_GROUP_NAME}' ORDER BY SITE_TYPR DESC,PRIORITY_LEVEL;"
    
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
        SERVICES_LINE=("`cat $TMPFILE3 | grep "\b${HOSTS[$i]}\b" | awk '{$1="";$2="";$3="";print $0}' | sed 's/^[ \t]*//g'`")
        IFS=$'\n'
        for SERVICES in $SERVICES_LINE;do
            IFS=','
            for service in $SERVICES;do
                Hostname=`cat $TMPFILE3 | grep "\b${HOSTS[$i]}\b" | awk '/'''$service'''/{print $2}'`
                CHECK_OS=`cat /etc/ansible/hosts | grep ${HOSTS[$i]} | grep -Eio "\bwinrm\b"`
                if [ "$CHECK_OS" == "winrm" ];then
                    printf "checking-$Hostname-${HOSTS[$i]}-$service-failed;\n"
                else
                    STATUS=`ansible ${HOSTS[$i]} -m shell -a "/etc/init.d/$service status" 2>$ERROR_LOG | head -1 | grep -Eio "SUCCESS"`
                    if [ "$STATUS" == "SUCCESS" ];then
                        printf "checking-$Hostname-${HOSTS[$i]}-$service-running;\n"
                    else
                        printf "checking-$Hostname-${HOSTS[$i]}-$service-stopped;\n"
                    fi
                fi
            done
        done
    done
    IFS="$OLD_IFS"
}

check_ping() {
    falt1=0
    HOSTS=(`cat $TMPFILE1 | awk '{print $1}' | sort | uniq`)
    INDEX=${#HOSTS[@]}
    for (( i=0;i<$INDEX;i++ ));do
        ping -c2 -w2 ${HOSTS[$i]} &>/dev/null
        if [ $? -eq 0 ];then
            info_log "The server ${HOSTS[$i]} Already connected\n"
            info_log "The service on the server ${HOSTS[$i]} is normal\n"
        else
            info_log "The server ${HOSTS[$i]} connect fail!\n"
            info_log "The service on the server ${HOSTS[$i]} is abnormal.\n"
            falt1=$(($falt1 + 1))
        fi
    done

    falt2=0
    HOSTS=(`cat $TMPFILE2 | awk '{print $1}' | sort | uniq`)
    INDEX=${#HOSTS[@]}
    for (( i=0;i<$INDEX;i++ ));do
        ping -c2 -w2 ${HOSTS[$i]} &>/dev/null
        if [ $? -eq 0 ];then
            info_log "The server ${HOSTS[$i]} Already connected\n"
            info_log "The service on the server ${HOSTS[$i]} is normal\n"
        else
            info_log "The server ${HOSTS[$i]} connect fail!\n"
            info_log "The service on the server ${HOSTS[$i]} is abnormal.\n"
            falt2=$(($falt2 + 1))
        fi
    done

    if [ $falt1 -ne 0 ];then
        MASTER_CHECK=("1")
    else
        MASTER_CHECK=("0")
    fi

    if [ $falt2 -ne 0 ];then
        BACKUP_CHECK=("1")
    else
        BACKUP_CHECK=("0")
    fi
}

stop_master() {
    master=(`tac $TMPFILE1 | awk '{print $1}'`)
    length=${#master[@]}
    OLD_IFS="$IFS"
    IFS=","
    for (( i=0;i<$length;i++ ));do
        SERVICE_LINE=("`cat $TMPFILE1 | grep "\b${master[$i]}\b" | grep "\b0\b" | awk '{$1="";$2="";$3="";print $0}' | sed 's/^[ \t]*//g' | awk -F',' '{for(i=NF;i>0;i--) printf("%s,",$i);printf "\n"}' | sed 's/,$//g'`")
        service_sum=${#SERVICE_LINE[@]}
        IFS=$'\n'
        for (( j=0;j<$service_sum;j++ ));do
            IFS=','
            for service in ${SERVICE_LINE[$j]};do
                Hostname=`cat $TMPFILE1 | grep "\b${master[$i]}\b" | awk '/'''$service'''/{print $2}'`
                info_log "[Stopping] stop $service service by $Hostname ... "
                CHECK_OS=`cat /etc/ansible/hosts | grep ${master[$i]} | grep -Eio "\bwinrm\b"`
                if [ "$CHECK_OS" == "winrm" ];then
                    #STOP=`ansible ${master[$i]} -m win_shell -a """net stop ${service[$j]}""" | head -1 | grep -Eio "SUCCESS"`
                    STOP=`ansible ${master[$i]} -m win_shell -a """net stop $service""" | sed -n '2p' | awk -F"[. ]" '{print $(NF-1)}'`
                    if [ "$STOP" == "stopping" ];then
                        printf "success\n"
                    elif [ "$STOP" == "started" ];then
                        printf "stopped\n"
                    else
                        STOP_M=("FAILED")
                        printf "failed\n"
                    fi
                else
                    STOP=`ansible ${master[$i]} -m shell -a "/etc/init.d/$service stop" 2>$ERROR_LOG | head -1 | grep -Eio "SUCCESS"`
                    if [ "$STOP" == "SUCCESS" ];then
                        printf "success\n"
                    else
                        STOP_M=("FAILED")
                        printf "failed\n"
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
    for (( i=0;i<$length;i++ ));do
        #service=(`cat $TMPFILE1 | grep "\b${master[$i]}\b" | awk '{print $3}' | sed 's#,# #g'`)
        service_line=("`cat $TMPFILE1 | grep "\b${master[$i]}\b" | grep "\b0\b" | awk '{$1="";$2="";$3="";print $0}' | sed 's/^[ \t]*//g' | awk -F',' '{for(i=NF;i>0;i--) printf("%s,",$i);printf "\n"}' | sed 's/,$//g'`")
        service_sum=${#service_line[@]}
        IFS=$'\n'
        for (( j=0;j<$service_sum;j++ ));do
            IFS=','
            for service in ${service_line[$j]};do
                Hostname=`cat $TMPFILE1 | grep "\b${master[$i]}\b" | awk '/'''$service'''/{print $2}'`
                info_log "[Starting] start $service service by $Hostname ... "
                CHECK_OS=`cat /etc/ansible/hosts | grep ${master[$i]} | grep -Eio "\bwinrm\b"`
                if [ "$CHECK_OS" == "winrm" ];then
                    #START=`ansible ${master[$i]} -m win_shell -a """net start ${service[$j]}""" | head -1 | grep -Eio "SUCCESS"`
                    START=`ansible ${master[$i]} -m win_shell -a """net start $service""" | sed -n '2p' | awk -F"[. ]" '{print $(NF-1)}'`
                    if [ "$START" == "starting" ];then
                        printf "success\n"
                    elif [ "$START" == "started" ];then
                        printf "started\n"
                    else
                        START_M=("FAILED")
                        printf "failed\n"
                        break
                    fi
                else
                    STATUS=`ansible ${master[$i]} -m shell -a "/etc/init.d/$service status" 2>$ERROR_LOG | head -1 | grep -Eio "SUCCESS"`
                    if [ "$STATUS" != "SUCCESS" ];then
                        START=`ansible ${master[$i]} -m shell -a "/etc/init.d/$service start" 2>$ERROR_LOG | head -1 | grep -Eio "SUCCESS"`
                        if [ "$START" == "SUCCESS" ];then
                            printf "success\n"
                        else
                            START_M=("FAILED")
                            printf "failed\n"
                            break
                        fi
                    else
                        printf "started\n"
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
    for (( i=0;i<$length;i++ ));do
        #service=(`cat $TMPFILE2 | grep "\b${slave[$i]}\b" | awk '{print $3}' | sed 's#,# #g'`)
        service_line=("`cat $TMPFILE2 | grep "\b${slave[$i]}\b" | grep "\b1\b" | awk '{$1="";$2="";$3="";print $0}' | sed 's/^[ \t]*//g' | awk -F',' '{for(i=NF;i>0;i--) printf("%s,",$i);printf "\n"}' | sed 's/,$//g'`")
        service_sum=${#service_line[@]}
        IFS=$'\n'
        for (( j=0;j<$service_sum;j++ ));do
            IFS=','
            for service in ${service_line[$j]};do
                Hostname=`cat $TMPFILE2 | grep "\b${slave[$i]}\b" | awk '/'''$service'''/{print $2}'`
                info_log "[Stopping] stop $service service by $Hostname ... "
                CHECK_OS=`cat /etc/ansible/hosts | grep ${slave[$i]} | grep -Eio "\bwinrm\b"`
                if [ "$CHECK_OS" == "winrm" ];then
                    #STOP=`ansible ${slave[$i]} -m win_shell -a """net stop ${service[$j]}""" | head -1 | grep -Eio "SUCCESS"`
                    STOP=`ansible ${slave[$i]} -m win_shell -a """net stop $service""" | sed -n '2p' | awk -F"[. ]" '{print $(NF-1)}'`
                    if [ "$STOP" == "stopping" ];then
                        printf "success\n"
                    elif [ "$STOP" == "started" ];then
                        printf "stopped\n"
                    else
                        STOP_S=("FAILED")
                        printf "failed\n"
                    fi
                else
                    STOP=`ansible ${slave[$i]} -m shell -a "/etc/init.d/$service stop" 2>$ERROR_LOG | head -1 | grep -Eio "SUCCESS"`
                    if [ "$STOP" == "SUCCESS" ];then
                        printf "success\n"
                    else
                        STOP_S=("FAILED")
                        printf "failed\n"
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
    for (( i=0;i<$length;i++ ));do
        #service=(`cat $TMPFILE2 | grep "\b${slave[$i]}\b" | awk '{print $3}' | sed 's#,# #g'`)
        service_line=("`cat $TMPFILE2 | grep "\b${slave[$i]}\b" | grep "\b1\b" | awk '{$1="";$2="";$3="";print $0}' | sed 's/^[ \t]*//g' | awk -F',' '{for(i=NF;i>0;i--) printf("%s,",$i);printf "\n"}' | sed 's/,$//g'`")
        service_sum=${#service_line[@]}
        IFS=$'\n'
        for (( j=0;j<$service_sum;j++ ));do
            IFS=','
            for service in ${service_line[$j]};do
                Hostname=`cat $TMPFILE2 | grep "\b${slave[$i]}\b" | awk '/'''$service'''/{print $2}'`          
                info_log "[Starting] start $service service by $Hostname ... "
                CHECK_OS=`cat /etc/ansible/hosts | grep ${slave[$i]} | grep -Eio "\bwinrm\b"`
                if [ "$CHECK_OS" == "winrm" ];then
                    #START=`ansible ${slave[$i]} -m win_shell -a """net start ${service[$j]}""" | head -1 | grep -Eio "SUCCESS"`
                    START=`ansible ${slave[$i]} -m win_shell -a """net start $service""" | sed -n '2p' | awk -F"[. ]" '{print $(NF-1)}'`
                    if [ "$START" == "starting" ];then
                        printf "success\n"
                    elif [ "$START" == "started" ];then
                        printf "started\n"
                    else
                        START_S=("FAILED")
                        printf "failed\n"
                        break
                    fi
                else
                    STATUS=`ansible ${slave[$i]} -m shell -a "/etc/init.d/$service status" 2>$ERROR_LOG | head -1 | grep -Eio "SUCCESS"`
                    if [ "$STATUS" != "SUCCESS" ];then
                        START=`ansible ${slave[$i]} -m shell -a "/etc/init.d/$service start" 2>$ERROR_LOG | head -1 | grep -Eio "SUCCESS"`
                        if [ "$START" == "SUCCESS" ];then
                            printf "success\n"
                        else
                            START_S=("FAILED")
                            printf "failed\n"
                            break
                        fi
                    else
                        printf "started\n"
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
        SERVICES_LINE=("`cat $TMPFILE3 | grep "\b${HOSTS[$i]}\b" | awk '{$1="";$2="";$3="";print $0}' | sed 's/^[ \t]*//g'`")
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
        SERVICES_LINE=("`cat $TMPFILE3 | grep "\b${HOSTS[$i]}\b" | awk '{$1="";$2="";$3="";print $0}' | sed 's/^[ \t]*//g' | awk -F',' '{for(i=NF;i>0;i--) printf("%s,",$i);printf "\n"}' | sed 's/,$//g'`")
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
    echo -e "[HASwitchover $HA_GROUP_NAME] Start All Services:"
    connect_db
    start_server_group_services
    rm -f $TMPFILE1; rm -f $TMPFILE2
}

all_stop_main() {
    echo -e "[HASwitchover $HA_GROUP_NAME] Stop All Services:"
    connect_db
    stop_server_group_services
    rm -f $TMPFILE1; rm -f $TMPFILE2
}


switch_to_backup() {
    connect_db
    info_log "[Checking]:\n"
    check_ping
    if [ "${BACKUP_CHECK[@]}" == "1" ];then
        exit 1
    fi

    info_log "[Start Switch]: \n"
    stop_master
    start_slave
    if [ "${START_S[@]}" == "FAILED" ];then
        info_log "Backup switchover to master failed!\n"
        info_log "roll-back to master.\n"
        stop_slave
        start_master
        SWITCH_RESULT=("0")
        info_log "roll-back to master done!"
    else
        info_log "Backup switchover to master successfully.\n"
        SWITCH_RESULT=("1")
    fi
    echo "${SWITCH_RESULT[0]}"
    rm -f $TMPFILE1; rm -f $TMPFILE2
}

switch_to_master() {
    connect_db
    info_log "[Checking]:\n"
    check_ping
    if [ "${MASTER_CHECK[@]}" == "1" ];then
        exit 1
    fi

    info_log "[Start Switch]:\n"
    stop_slave
    start_master
    if [ "${START_M[@]}" == "FAILED" ];then
        info_log "Master switchover to master failed!\n"
        info "roll-back to backup.\n"
        stop_master
        start_slave
        SWITCH_RESULT=("0")
        info_log "roll-back to backup done!"
    else
        info_log "Master switchover to backup successfully.\n"
        SWITCH_RESULT=("1")
    fi
    echo "${SWITCH_RESULT[0]}"
    rm -f $TMPFILE1; rm -f $TMPFILE2
}

starting() {
    if [ "$HA_GROUP_NAME" != "" ];then
        all_start_main > $LOGFILE && cat $LOGFILE
    else
        echo "ERROR: GROUP_NAME not null!"
        exit 2
    fi
}

stopping() {
    if [ "$HA_GROUP_NAME" != "" ];then
        all_stop_main >  $LOGFILE && cat $LOGFILE
    else
        echo "ERROR: GROUP_NAME not null!"
        exit 2
    fi
}

case $HA_STATE in
    master)
        switch_to_master > $LOGFILE && cat $LOGFILE
    ;;
    backup)
        switch_to_backup > $LOGFILE && cat $LOGFILE
    ;;
    start)
        starting
    ;;
    stop)
        stopping
    ;;
    status)
        service_status
    ;;
    *)
        echo -e "USAGE: $0 [GROUP_NAME] [master|backup|start|stop|status]"
        exit 3
esac
