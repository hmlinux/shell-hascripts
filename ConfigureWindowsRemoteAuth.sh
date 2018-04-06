#!/bin/bash
#Windows ansible remote authentication script
#10.17.87.64 ansible_ssh_user="Administrator" ansible_ssh_pass="zteict!123" ansible_ssh_port=5985 ansible_connection="winrm" ansible_winrm_server_cert_validation=ignore

if [ "$1" == "-h" -o "$1" == "-help" -o "x$1" == "x" ];then
    echo -e "Usage: ./ConfigureWindowsRemoteAuth.sh Username/Password/IP"
    echo -e "\nExample:\n./ConfigureWindowsRemoteAuth.sh Administrator/123456/10.17.81.100\n"
fi

remote_host=$1
user=`echo $remote_host | awk -F"[/]" '{print $1}'`
pass=`echo $remote_host | awk -F"[/]" '{print $2}'`
host=`echo $remote_host | awk -F"[/]" '{print $NF}'`

test_ping() {
    ping -c2 -w2 $host &>/dev/null
    if [ $? -ne 0 ];then
        echo "Authentication Failure!"
        exit 1
    fi
}
test_ping

ConfigAnsible() {
    sed -i "/$host ansible_/d" /etc/ansible/hosts
    sed -i "/^\[windows\]/a$host ansible_ssh_user="$user" ansible_ssh_pass="$pass" ansible_ssh_port=5985 ansible_connection="winrm" ansible_winrm_server_cert_validation=ignore" /etc/ansible/hosts
}
ConfigAnsible &>/dev/null

Test_Connect() {
    result=`ansible $host -m win_shell -a "hostname" | grep -Eio "SUCCESS"`
    if [ "$result" == "SUCCESS" ];then
        echo "Authentication Success!"
    else
        echo "Authentication Failure!"
        sed -i "/$host ansible_/d" /etc/ansible/hosts
        exit 1
    fi
}
Test_Connect
