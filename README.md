# 开始之前
要遵循本指南，你需要：

- 一台或多台运行兼容 deb/rpm 的 Linux 操作系统的计算机；例如：Ubuntu 或 CentOS。
- 每台机器 2 GB 以上的内存，内存不足时应用会受限制。
- 用作控制平面节点的计算机上至少有2个 CPU。
- 集群中所有计算机之间具有完全的网络连接。你可以使用公共网络或专用网络。
# 端口开放
- 如果你是用虚拟机部署，确保系统防火墙关闭即可
- 如果你是云服务器部署，请在你的服务器的安全组策略中，开放以下端口
## k8s中需要开放的端口
[参考kubernetes官方文档](https://kubernetes.io/zh/docs/reference/ports-and-protocols/)
控制面 
| 协议	| 方向	| 端口范围	        | 目的	        |使用者|
|  ----  | ----  | ----  | ----  |  ----  |
|TCP |入站	|6443	    |Kubernetes API server	|所有|
|TCP |入站	|2379-2380	|etcd server client API	        |kube-apiserver, etcd|
|TCP |入站	|10250	    |Kubelet API	            |自身, 控制面|
|TCP |入站	|10259	    |kube-scheduler	        |自身|
|TCP |入站	|10257	    |kube-controller-manager	|自身|

尽管 etcd 的端口也列举在控制面的部分，但你也可以在外部自己托管 etcd 集群或者自定义端口。

工作节点 

|  协议   |  方向  |  端口范围  | 目的  |  使用者  |
|  ----   |  ----  |  ----  |  ----  |  ----  |
|TCP |入站	|10250	    |Kubelet API	        |自身, 控制面|
|TCP |入站	|30000-32767	|NodePort Services†	    |所有|

## calico网络插件需要开放的端口
[参考calico官方文档](https://projectcalico.docs.tigera.io/getting-started/kubernetes/requirements)
网络要求
确保您的主机和防火墙根据您的配置允许必要的流量。
|  配置   | 主持人  | 连接类型  | 端口/协议  |
|  ----  | ----  | ----  | ----  |
| BGP  | 全部 | 双向  | TCP 179 |



# 所有服务器都要做的操作
## 1. 升级系统内核
    cat /etc/hosts
    uname -r

### CentOS 7
    rpm -Uvh https://www.elrepo.org/elrepo-release-7.el7.elrepo.noarch.rpm
    yum --enablerepo=elrepo-kernel install -y kernel-lt
    grub2-set-default 0 
    reboot
### CentOS 8
    rpm -Uvh http://www.elrepo.org/elrepo-release-8.el8.elrepo.noarch.rpm
    yum --enablerepo=elrepo-kernel install -y kernel-lt
    grub2-set-default 0 
    reboot
## 2. 修改hosts文件
    cat >> /etc/hosts << EOF
    127.0.0.1   $(hostname)
    10.0.xx.x   master
    10.0.x.xx   node2
    10.0.x.xx   node1
    43.138.xxx.xx   master
    43.138.xxx.xxx   node2
    43.138.xxx.xxx   node1
    EOF

# 根据不同节点各自操作
下载好服务器对应版本的脚本文件到用户目录下。比如/root
## 3. master
    hostnamectl set-hostname master
    touch master.sh
    chmod +x master.sh
    vim master.sh
    ./master.sh

## 4. node1
    hostnamectl set-hostname node1
    touch node.sh
    chmod +x node.sh
    vim node.sh
    ./node.sh

## 5. node2
    hostnamectl set-hostname node2
    touch node.sh
    chmod node.sh
    vim node.sh
    ./node.sh
## 6. 将工作节点加入到k8s集群
You can now join any number of machines by running the following on each node
as root:

  kubeadm join <control-plane-host>:<control-plane-port> --token <token> --discovery-token-ca-cert-hash sha256:<hash>

## 7. 安装calico网络插件
    vi calico.yaml
    利用/CALICO_IPV4POOL_CIDR快速查找位置，更改为你的pod网段
    - name: CALICO_IPV4POOL_CIDR
      value: 10.244.0.0/16
    
    利用/k8s，bgp快速查找位置，等号后面更改为你的网卡名，比如ens33,eth0
    – name: IP_AUTODETECTION_METHOD
    value: “interface=eth0”
保存之后就可以应用配置了

    kubectl apply -f calico.yaml

然后等所有的pod都running完毕，自然状态就是ready了

    watch kubectl get po -A 

都ready好啦之后，现在可以查看nodes状态，所有的节点都已经ready了

    kubectl get nodes -o wide
