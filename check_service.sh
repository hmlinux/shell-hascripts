#!/bin/bash
#Check the service init shell script if have in the /etc/init.d directory
#添加设备时，检查填入的服务名是否存在

host=$1
port=$2
service=($@)
noservice=("")

if [ "$host" == "" -o "$port" == "" ];then
    echo -e "Usage: [ip] [port] [servicename1 servicename ...]"
    exit 1
fi

unset service[0]
unset service[1]
for i in ${service[@]}
do
    ssh $host -p $port "test -f /etc/init.d/$i" &>/dev/null
    if [ $? -ne 0 ];then
        result="No found the /etc/init.d/$i file"
        noservice=(${noservice[@]} $i)
    fi
done
echo -e "${noservice[@]}"
