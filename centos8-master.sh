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
#wget -O /etc/yum.repos.d/CentOS-Base.repo https://mirrors.aliyun.com/repo/Centos-7.repo
# centos8（centos8官方源已下线，建议切换centos-vault源）
wget -O /etc/yum.repos.d/CentOS-Base.repo https://mirrors.aliyun.com/repo/Centos-vault-8.5.2111.repo
yum clean all
yum makecache
yum install wget net-tools telnet tree nmap sysstat lrzsz dos2unix bind-utils -y

# 允许 iptables 检查桥接流量
cat <<EOF | sudo tee /etc/modules-load.d/k8s.conf
br_netfilter
EOF
cat <<EOF | sudo tee /etc/sysctl.d/k8s.conf
net.bridge.bridge-nf-call-ip6tables = 1
net.bridge.bridge-nf-call-iptables = 1
net.ipv4.ip_forward = 1
EOF
sudo sysctl --system

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

wget https://mirrors.aliyun.com/docker-ce/linux/centos/docker-ce.repo -O /etc/yum.repos.d/docker-ce.repo
yum install -y containerd.io
cat << EOF | sudo tee /etc/modules-load.d/containerd.conf
overlay
br_netfilter
EOF

sudo modprobe overlay
sudo modprobe br_netfilter
# 配置 sysctl 参数，这些配置在重启之后仍然起作用
cat <<EOF | sudo tee /etc/sysctl.d/99-kubernetes-cri.conf
net.bridge.bridge-nf-call-iptables  = 1
net.ipv4.ip_forward                 = 1
net.bridge.bridge-nf-call-ip6tables = 1
EOF

cat << EOF >> /etc/crictl.yaml
runtime-endpoint: unix:///var/run/containerd/containerd.sock
image-endpoint: unix:///var/run/containerd/containerd.sock
timeout: 10
debug: false
EOF
sudo sysctl --system
systemctl daemon-reload
systemctl enable containerd --now
systemctl restart containerd
#systemctl status containerd

cat > /etc/yum.repos.d/kubernetes.repo <<EOF
[kubernetes]
name=Kubernetes
baseurl=https://mirrors.aliyun.com/kubernetes/yum/repos/kubernetes-el7-x86_64
enabled=1
gpgcheck=0
repo_gpgcheck=0
gpgkey=http://mirrors.aliyun.com/kubernetes/yum/doc/yum-key.gpg http://mirrors.aliyun.com/kubernetes/yum/doc/rpm-package-key.gpg

EOF

mkdir -p /etc/containerd
containerd config default | sudo tee /etc/containerd/config.toml
sed -ri 's#SystemdCgroup = false#SystemdCgroup = true#' /etc/containerd/config.toml
sed -ri 's#k8s.gcr.io\/pause:3.6#registry.aliyuncs.com\/google_containers\/pause:3.7#' /etc/containerd/config.toml
sed -ri 's#https:\/\/registry-1.docker.io#https:\/\/registry.aliyuncs.com#' /etc/containerd/config.toml
sed -ri 's#net.ipv4.ip_forward = 0#net.ipv4.ip_forward = 1#' /etc/sysctl.d/99-sysctl.conf
sudo sysctl --system
systemctl daemon-reload
sudo systemctl enable containerd && systemctl restart containerd
#sudo systemctl restart containerd

echo 1 > /proc/sys/net/ipv4/ip_forward

yum -y install kubeadm kubelet kubectl --disableexcludes=kubernetes
systemctl enable --now kubelet && systemctl start kubelet
#systemctl enable --now kubelet 
#systemctl status kubelet
kubeadm config images list

#kubeadm config images list --config kubeadm-init.yaml
#kubeadm config images pull --config kubeadm-init.yaml
crictl pull registry.cn-hangzhou.aliyuncs.com/google_containers/kube-apiserver:v1.24.0
crictl pull registry.cn-hangzhou.aliyuncs.com/google_containers/kube-controller-manager:v1.24.0
crictl pull registry.cn-hangzhou.aliyuncs.com/google_containers/kube-scheduler:v1.24.0
crictl pull registry.cn-hangzhou.aliyuncs.com/google_containers/kube-proxy:v1.24.0
crictl pull registry.cn-hangzhou.aliyuncs.com/google_containers/pause:3.7
crictl pull registry.cn-hangzhou.aliyuncs.com/google_containers/etcd:3.5.3-0
crictl pull registry.cn-hangzhou.aliyuncs.com/google_containers/coredns:v1.8.6 


ctr -n k8s.io i tag registry.cn-hangzhou.aliyuncs.com/google_containers/kube-apiserver:v1.24.0 k8s.gcr.io/kube-apiserver:v1.24.0
ctr -n k8s.io i tag registry.cn-hangzhou.aliyuncs.com/google_containers/kube-controller-manager:v1.24.0 k8s.gcr.io/kube-controller-manager:v1.24.0
ctr -n k8s.io i tag registry.cn-hangzhou.aliyuncs.com/google_containers/kube-scheduler:v1.24.0 k8s.gcr.io/kube-scheduler:v1.24.0
ctr -n k8s.io i tag registry.cn-hangzhou.aliyuncs.com/google_containers/kube-proxy:v1.24.0 k8s.gcr.io/kube-proxy:v1.24.0
ctr -n k8s.io i tag registry.cn-hangzhou.aliyuncs.com/google_containers/pause:3.7 k8s.gcr.io/pause:3.7
ctr -n k8s.io i tag registry.cn-hangzhou.aliyuncs.com/google_containers/etcd:3.5.3-0 k8s.gcr.io/etcd:3.5.3-0
ctr -n k8s.io i tag registry.cn-hangzhou.aliyuncs.com/google_containers/coredns:v1.8.6 k8s.gcr.io/coredns/coredns:v1.8.6 

ctr -n k8s.io i ls -q
crictl images
crictl ps -a

kubeadm config print init-defaults > default-init.yaml

local_ip=$(ip addr | awk '/^[0-9]+: / {}; /inet.*global.*eth/ {print gensub(/(.*)\/(.*)/, "\\1", "g", $2)}')
#echo $local_ip

cat <<EOF | sudo tee /root/init.conf
apiVersion: kubeadm.k8s.io/v1beta3
bootstrapTokens:
- groups:
  - system:bootstrappers:kubeadm:default-node-token
  token: abcdef.0123456789abcdef
  ttl: 24h0m0s
  usages:
  - signing
  - authentication
kind: InitConfiguration
localAPIEndpoint:
  advertiseAddress: $local_ip
  bindPort: 6443
nodeRegistration:
  kubeletExtraArgs:
    volume-plugin-dir: "/opt/libexec/kubernetes/kubelet-plugins/volume/exec/"
  criSocket: unix:///var/run/containerd/containerd.sock
  imagePullPolicy: IfNotPresent
  name: master
  taints:
  - effect: "NoSchedule"
    key: "node-role.kubernetes.io/master"
---
apiServer:
  timeoutForControlPlane: 4m0s
apiVersion: kubeadm.k8s.io/v1beta3
certificatesDir: /etc/kubernetes/pki
clusterName: kubernetes
controllerManager: {}
dns: {}
etcd:
  local:
    dataDir: /var/lib/etcd
imageRepository: registry.cn-hangzhou.aliyuncs.com/google_containers
kind: ClusterConfiguration
kubernetesVersion: 1.24.0
networking:
  dnsDomain: cluster.local
  serviceSubnet: 10.96.0.0/12
  podSubnet: 10.244.0.0/16
scheduler: {}
EOF

kubeadm init --config init.conf | tee kubeadm-init.log

rm -rf $HOME/.kube
mkdir -p $HOME/.kube
sudo cp -i /etc/kubernetes/admin.conf $HOME/.kube/config
sudo chown $(id -u):$(id -g) $HOME/.kube/config

#echo "export KUBECONFIG=/etc/kubernetes/admin.conf" >> /etc/profile
#source /etc/profile

curl https://docs.projectcalico.org/manifests/calico.yaml -O
kubectl apply -f calico.yaml

kubectl get node -owide
endTime=`date +%Y%m%d_%H:%M:%S`
endTime_s=`date +%s`
sumTime=$[ $endTime_s - $startTime_s]

echo "$startTime ---> $endTime" "Total:$sumTime seconds"