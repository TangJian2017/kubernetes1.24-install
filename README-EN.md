# Before you begin
To follow this guide, you need:

- One or more machines running a deb/rpm-compatible Linux OS; for example: Ubuntu or CentOS.
- 2 GiB or more of RAM per machine--any less leaves little room for your apps.
- At least 2 CPUs on the machine that you use as a control-plane node.
- Full network connectivity among all machines in the cluster. You can use either a public or a private network.
# all machines operation 
## 1. update kernel
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
## 2. modify hosts file
    cat >> /etc/hosts << EOF
    127.0.0.1   $(hostname)
    10.0.xx.x   master
    10.0.x.xx   node2
    10.0.x.xx   node1
    43.138.xxx.xx   master
    43.138.xxx.xxx   node2
    43.138.xxx.xxx   node1
    EOF


# 3. master
    hostnamectl set-hostname master
    touch master.sh
    chmod +x master.sh
    vim master.sh
    ./master.sh

# 4. node1
    hostnamectl set-hostname node1
    touch node.sh
    chmod +x node.sh
    vim node.sh
    ./node.sh

# 5. node2
    hostnamectl set-hostname node2
    touch node.sh
    chmod node.sh
    vim node.sh
    ./node.sh
# 6. join work node into k8s cluster
You can now join any number of machines by running the following on each node
as root:

  kubeadm join <control-plane-host>:<control-plane-port> --token <token> --discovery-token-ca-cert-hash sha256:<hash>