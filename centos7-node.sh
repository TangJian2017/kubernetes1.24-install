#!/bin/bash

startTime=`date +%Y%m%d_%H:%M:%S`
startTime_s=`date +%s`

ping -c2 master
ping -c2 node1
ping -c2 node2

#yum -y install ntp
#systemctl start ntpd && systemctl enable ntpd && systemctl status ntpd
systemctl stop firewalld && systemctl disable firewalld && systemctl status firewalld
setenforce 0
sed -i 's/SELINUX=enforcing/SELINUX=disabled/g' /etc/selinux/config
swapoff -a
sed -i 's/.*swap.*/#&/g' /etc/fstab

mv /etc/yum.repos.d/CentOS-Base.repo /etc/yum.repos.d/CentOS-Base.repo.backup
# centos7
wget -O /etc/yum.repos.d/CentOS-Base.repo https://mirrors.aliyun.com/repo/Centos-7.repo
# centos8（centos8官方源已下线，建议切换centos-vault源）
#wget -O /etc/yum.repos.d/CentOS-Base.repo https://mirrors.aliyun.com/repo/Centos-vault-8.5.2111.repo
yum clean all
yum makecache
yum install wget net-tools telnet tree nmap sysstat lrzsz dos2unix bind-utils -y

# 每小时做一次时间同步 追加到root的定时任务 并重启定时服务
cat << EOF >> /var/spool/cron/root
* */1 * * * /usr/sbin/ntpdate time1.tencentyun.com > /dev/null 2>&1
EOF
systemctl restart crond

# 允许 iptables 检查桥接流量
# 不修改这个，紧接着的下一步会报错
cat <<EOF | sudo tee /etc/modules-load.d/k8s.conf
br_netfilter
EOF
# 这是临时修改
#modprobe br_netfilter 
# ip_forward是数据包转发
cat <<EOF | sudo tee /etc/sysctl.d/k8s.conf
net.bridge.bridge-nf-call-ip6tables = 1
net.bridge.bridge-nf-call-iptables = 1
net.ipv4.ip_forward = 1
EOF
#sudo sysctl --system
sysctl -p /etc/sysctl.d/k8s.conf

# 传输层负载均衡
# 比iptables吊，适合大集群，高可扩和性能，更复杂的LB算法，支持健康检查和连接重试
yum -y install ipset ipvsadm

cat > /etc/sysconfig/modules/ipvs.modules <<EOF
modprobe -- ip_vs
modprobe -- ip_vs_rr
modprobe -- ip_vs_wrr
modprobe -- ip_vs_sh
EOF

kernel_version=$(uname -r | cut -d- -f1)
echo $kernel_version

if [ `expr $kernel_version \> 4.19` -eq 1 ]
    then
        modprobe -- nf_conntrack
    else
        modprobe -- nf_conntrack_ipv4
fi

chmod 755 /etc/sysconfig/modules/ipvs.modules && bash /etc/sysconfig/modules/ipvs.modules && lsmod | grep -e ip_vs -e nf_conntrack



cat > /etc/yum.repos.d/kubernetes.repo <<EOF
[kubernetes]
name=Kubernetes
baseurl=https://mirrors.aliyun.com/kubernetes/yum/repos/kubernetes-el7-x86_64
enabled=1
gpgcheck=0
repo_gpgcheck=0
gpgkey=http://mirrors.aliyun.com/kubernetes/yum/doc/yum-key.gpg http://mirrors.aliyun.com/kubernetes/yum/doc/rpm-package-key.gpg

EOF

wget https://mirrors.aliyun.com/docker-ce/linux/centos/docker-ce.repo -O /etc/yum.repos.d/docker-ce.repo
yum install -y containerd.io
cat << EOF | sudo tee /etc/modules-load.d/containerd.conf
overlay
br_netfilter
EOF

sudo modprobe overlay
sudo modprobe br_netfilter
# 配置 sysctl 参数，这些配置在重启之后仍然起作用

cat <<EOF | sudo tee /etc/sysctl.d/99-sysctl.conf
net.bridge.bridge-nf-call-iptables  = 1
net.bridge.bridge-nf-call-ip6tables = 1
net.ipv4.ip_forward = 1
EOF

cat << EOF >> /etc/crictl.yaml
runtime-endpoint: unix:///var/run/containerd/containerd.sock
image-endpoint: unix:///var/run/containerd/containerd.sock
timeout: 10
debug: false
EOF
#sudo sysctl --system
systemctl daemon-reload
systemctl enable containerd --now
systemctl restart containerd

mkdir -p /etc/containerd
containerd config default | sudo tee /etc/containerd/config.toml
sed -ri 's#SystemdCgroup = false#SystemdCgroup = true#' /etc/containerd/config.toml
sed -ri 's#k8s.gcr.io\/pause:3.6#registry.aliyuncs.com\/google_containers\/pause:3.7#' /etc/containerd/config.toml
sed -ri 's#https:\/\/registry-1.docker.io#https:\/\/registry.aliyuncs.com#' /etc/containerd/config.toml
sed -ri 's#net.ipv4.ip_forward = 0#net.ipv4.ip_forward = 1#' /etc/sysctl.d/99-sysctl.conf
systemctl daemon-reload
systemctl enable containerd --now 
systemctl restart containerd

#yum list kubeadm --showduplicates | sort -r
yum -y install kubeadm-1.24.0-0 kubelet-1.24.0-0 kubectl-1.24.0-0 --disableexcludes=kubernetes
#yum -y install kubeadm kubelet kubectl --disableexcludes=kubernetes
systemctl enable --now kubelet


crictl pull registry.cn-hangzhou.aliyuncs.com/google_containers/kube-proxy:v1.24.0
crictl pull registry.cn-hangzhou.aliyuncs.com/google_containers/pause:3.7

ctr -n k8s.io i tag registry.cn-hangzhou.aliyuncs.com/google_containers/kube-proxy:v1.24.0 k8s.gcr.io/kube-proxy:v1.24.0
ctr -n k8s.io i tag registry.cn-hangzhou.aliyuncs.com/google_containers/pause:3.7 k8s.gcr.io/pause:3.7

ctr -n k8s.io i ls -q
crictl images
crictl ps -a


endTime=`date +%Y%m%d_%H:%M:%S`
endTime_s=`date +%s`
sumTime=$[ $endTime_s - $startTime_s]

echo "$startTime ---> $endTime" "Total:$sumTime seconds"