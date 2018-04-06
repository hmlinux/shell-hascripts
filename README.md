HA服务一键切换
  
  管理HA双机或HA集群的系统服务、应用服务(启动/停止、运行状态检查)
  
  支持CentOS、Red Hat、SUSE Linux、Ubuntu以及Windows
  
  支持Linux和Windows主机混合组(即双机组里面可以同时存在Linux和Windows主机的服务)

ConfigureSSHAuthentication.sh  配置Linux平台Ansible的SSH密钥认证

ConfigureWindowsRemoteAuth.sh  配置Windows平台的ansible身份验证

HASwitch.sh  实现基于Ansible自动化管理的HA服务一键切换脚本



Ansible配置
/etc/ansible/hosts   #添加Linux组(hosts)和Windows组

[hosts]

10.10.20.100

[windows]

10.10.20.200
