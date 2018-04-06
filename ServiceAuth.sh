#!/bin/bash

SERVICE_NAME=$1
if [ "X$SERVICE_NAME" != "X" ];then
    test -f /etc/init.d/$SERVICE_NAME
    if [ $? -ne 0 ];then
        echo 1060
    else
        echo 0
    fi
else
    echo -e "Usage: $0 [servicename]"
fi
