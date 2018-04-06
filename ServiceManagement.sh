#!/bin/bash
#Services Management script. 

SERVICES=("")
SERVICES_LIST=("$1")
ACTION=$2
START_RESULT=("1")
STOP_RESULT=("1")
STATUS_RESULT=("1")

HOSTNAME=`hostname`
IPADDRESS1=`ip addr|awk -F"[/ ]+" '(/inet /) && ($0 !~ /lo$/) && ($0 !~ /virbr0$/){print $3}' |awk 'NR==1{print $0}'`
IPADDRESS2=`ip addr|awk -F"[/ ]+" '(/inet /) && ($0 !~ /lo$/) && ($0 !~ /virbr0$/){print $3}' |awk 'NR==2{print $0}'`

s_stop() {
    #echo -e "ServiceManagement Stop Services:"
    #echo -e "`date "+%Y-%m-%d %H:%M:%S"` Stop the HA services on $HOSTNAME/$IPADDRESS1, $IPADDRESS2"
    OLD_IFS="$IFS"
    IFS=","
    total=0
    for servername in $SERVICES_LIST;do
        #printf "`date "+%Y-%m-%d %H:%M:%S"` [Stopping] $servername server... "
        /etc/init.d/$servername stop &>/dev/null
        if [ $? -eq 0 ];then
            printf "stopping-$servername-success\n"
        else
            printf "stopping-$servername-failed\n"
            total=$(( $total + 1 ))
        fi
    done
    IFS="$OLD_IFS"
    if [ $total == 0 ];then
        STOP_RESULT=("1")
    else
        STOP_RESULT=("0")
    fi
}

s_start() {
    #echo -e "ServiceManagement Start Services:"
    #echo -e "`date "+%Y-%m-%d %H:%M:%S"` Start the HA services on $HOSTNAME/$IPADDRESS1, $IPADDRESS2"
    OLD_IFS="$IFS"
    IFS=","
    for servername in $SERVICES_LIST;do
        #printf "`date "+%Y-%m-%d %H:%M:%S"` [Starting] $servername server... "
        /etc/init.d/$servername status &>/dev/null
        if [ $? -ne 0 ];then
            /etc/init.d/$servername start &>/dev/null
            if [ $? -eq 0 ];then
                printf "starting-$servername-success\n"
            else
                printf "starting-$servername-failed\n"
                START_RESULT=("0")
            fi
        else
            printf "starting-$servername-running\n"
        fi
    done
    IFS="$OLD_IFS"
}

s_status() {
    #echo -e "ServiceManagement Check Services:"
    #echo -e "`date "+%Y-%m-%d %H:%M:%S"` Check the HA services on $HOSTNAME/$IPADDRESS1, $IPADDRESS2"
    OLD_IFS="$IFS"
    IFS=","
    for servername in $SERVICES_LIST;do
        #printf "`date "+%Y-%m-%d %H:%M:%S"` [Checking] $servername server... "
        /etc/init.d/$servername status &>/dev/null
        if [ $? -eq 0 ];then
            printf "checking-$servername-success\n"
        else
            printf "checking-$servername-failed\n"
            STATUS_RESULT=("0")
        fi
    done
    IFS="$OLD_IFS"
}


case "$ACTION" in
    stop)
        s_stop
    ;;
    start)
        s_start
    ;;
    status)
        s_status
    ;;
    *)
        echo -e "Usage: $0 [ServiceName1,ServiceName2,...] [start|stop|status]"
        exit 2
esac
