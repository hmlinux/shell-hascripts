#!/bin/bash
#ConfigureSSHAuthentication script
#Ansible host SSH public key and sent to the nodes
#Usage: ./ConfigureSSHAuthentication.sh user/passwd/ip:port
#Example: ./ConfigureSSHAuthentication.sh root/123#\!abcDEF/10.17.81.100:22
#SSH认证脚本

. /etc/profile

if [ "$1" == "-h" -o "$1" == "-help" -o "x$1" == "x" ];then
    echo -e "Usage: ./ConfigureSSHAuthentication.sh Username/Password/IP:port"
    echo -e "\nExample:\n./ConfigureSSHAuthentication.sh root/123456/10.17.81.100:22\n"
fi

remote_host=$1
user=`echo $remote_host | awk -F"[/]" '{print $1}'`
pass=`echo $remote_host | awk -F"[/]" '{print $2}'`
host=`echo $remote_host | awk -F"[/]" '{print $NF}' | awk -F":" '{print $1}'`
port=`echo $remote_host | awk -F"[:]" '{print $NF}'`

test_ping() {
    ping -c2 -w2 $host &>/dev/null
    if [ $? -ne 0 ];then
        echo "Authentication Failure!"
        exit 1
    fi
}
test_ping

SendPublicKey() {
expect -c "
set timeout 4
spawn scp -r -P $port /root/.ssh/id_rsa.pub $user@$host:/home/authorized_keys
expect {
yes/no { send \"yes\r\"; exp_continue }
*assword* { send \"$pass\r\" }
};
expect exit;
"

expect -c "
set timeout 4
spawn ssh -t -p $port $user@$host \"mkdir /$user/.ssh ; cat /home/authorized_keys >> /$user/.ssh/authorized_keys && chmod 700 /$user/.ssh && chmod 400 /$user/.ssh/authorized_keys && rm -f /home/authorized_keys && ln -s /usr/bin/python3 /usr/bin/python\"
expect {
yes/no { send \"yes\r\"; exp_continue }
*assword* { send \"$pass\r\" }
};
expect exit;
"
}
SendPublicKey &>/dev/null

ConfigAnsible() {
    sed -i "/$host:$port/d" /etc/ansible/hosts
    sed -i "/^\[hosts\]/a$host:$port" /etc/ansible/hosts
}
ConfigAnsible &>/dev/null

Test_Connect() {
    result=`ansible $host -m ping | grep -Eio "SUCCESS"`
    if [ "$result" == "SUCCESS" ];then
        echo "Authentication Success!"
    else
        echo "Authentication Failure!"
        sed -i "/$host:$port/d" /etc/ansible/hosts
        exit 1
    fi
}
Test_Connect
