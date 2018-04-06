#!/bin/bash
#This is check services status script. The server start|stop scripts is in /etc/init.d/ directory.
LOGFILE=`pwd`/servicechk.log
TEST_RESULT=("")
SERVICES=$@
HOSTNAME=`hostname`
IPADDRESS1=`ip addr|awk -F"[/ ]+" '(/inet /) && ($0 !~ /lo$/) && ($0 !~ /virbr0$/){print $3}' |awk 'NR==1{print $0}'`
IPADDRESS2=`ip addr|awk -F"[/ ]+" '(/inet /) && ($0 !~ /lo$/) && ($0 !~ /virbr0$/){print $3}' |awk 'NR==2{print $0}'`

service_status() {
    echo -e "`date "+%Y-%m-%d %H:%M:%S"` Check services status on $HOSTNAME/$IPADDRESS1, $IPADDRESS2"
    total=0
    nofound=0
    OLD_IFS="$IFS"
    IFS=","
    for servername in $SERVICES;do
        printf "`date "+%Y-%m-%d %H:%M:%S"` [Checking] $servername server status... "
        test -f /etc/init.d/$servername
        if [ $? -ne 0 ];then
            printf "ERROR\n"
            nofound=$(( $nofound + 1 ))
        else
            /etc/init.d/$servername status &>/dev/null
            if [ $? -ne 0 ];then
                printf "FAILED\n"
                total=$(( $total + 1 ))
            else
                printf "SUCCESS\n"
            fi
        fi
    done
    IFS="$OLD_IFS"
    if [ $total == 0 ];then
        TEST_RESULT=("1")
    else
        TEST_RESULT=("0")
    fi
    if [ $nofound != 0 ];then
        TEST_RESULT=("0")
    fi
#    echo "${TEST_RESULT[0]}"
}

main() {
    echo -e "[ServiceChk - Check]------------------------------------------------"
    service_status
}

if [ "X${SERVICES[@]}" != "X" ];then
    main &>/dev/null
    echo "${TEST_RESULT[0]}"
else
    echo "Usage: $0 [servername1,servername2,...]"
fi
