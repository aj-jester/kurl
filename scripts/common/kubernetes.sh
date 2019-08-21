
function kubernetes_host() {
    kubernetes_load_ipvs_modules

    kubernetes_sysctl_config

    kubernetes_install_host_packages "$KUBERNETES_VERSION"

    load_images $DIR/packages/kubernetes/$KUBERNETES_VERSION/images
}

function kubernetes_load_ipvs_modules() {
    if [ "$IPVS" != "1" ]; then
        return
    fi
    if lsmod | grep -q ip_vs ; then
        return
    fi

    modprobe nf_conntrack_ipv4
    modprobe ip_vs
    modprobe ip_vs_rr
    modprobe ip_vs_wrr
    modprobe ip_vs_sh

    echo 'nf_conntrack_ipv4' > /etc/modules-load.d/replicated-ipvs.conf
    echo 'ip_vs' >> /etc/modules-load.d/replicated-ipvs.conf
    echo 'ip_vs_rr' >> /etc/modules-load.d/replicated-ipvs.conf
    echo 'ip_vs_wrr' >> /etc/modules-load.d/replicated-ipvs.conf
    echo 'ip_vs_sh' >> /etc/modules-load.d/replicated-ipvs.conf
}

function kubernetes_sysctl_config() {
    case "$LSB_DIST" in
        # TODO I've only seen these disabled on centos/rhel but should be safe for ubuntu
        centos|rhel)
            echo "net.bridge.bridge-nf-call-ip6tables = 1" > /etc/sysctl.d/k8s.conf
            echo "net.bridge.bridge-nf-call-iptables = 1" >> /etc/sysctl.d/k8s.conf
            echo "net.ipv4.conf.all.forwarding = 1" >> /etc/sysctl.d/k8s.conf

            sysctl --system
        ;;
    esac
}

# k8sVersion is an argument because this may be used to install step versions of K8s during an upgrade
# to the target version
function kubernetes_install_host_packages() {
    k8sVersion=$1

    logStep "Install kubelet, kubeadm, kubectl and cni host packages"

    if kubernetes_host_commands_ok; then
        logSuccess "Kubernetes host packages already installed"
        return
    fi

    if [ "$AIRGAP" != "1" ] && [ -n "$KURL_URL" ]; then
        kubernetes_get_host_packages_online "$k8sVersion"
    fi

    case "$LSB_DIST" in
        ubuntu)
            export DEBIAN_FRONTEND=noninteractive
            dpkg --install --force-depends-version $DIR/packages/kubernetes/${k8sVersion}/ubuntu-${DIST_VERSION}/*.deb
            ;;

        centos|rhel)
            rpm --upgrade --force --nodeps $DIR/packages/kubernetes/${k8sVersion}/rhel-7/*.rpm
            # TODO still required on 1.15+, and only CentOS/RHEL?
            service docker restart
            ;;
    esac

    if [ "$CLUSTER_DNS" != "$DEFAULT_CLUSTER_DNS" ]; then
        sed -i "s/$DEFAULT_CLUSTER_DNS/$CLUSTER_DNS/g" /etc/systemd/system/kubelet.service.d/10-kubeadm.conf
    fi

    systemctl enable kubelet && systemctl start kubelet

    logSuccess "Kubernetes host packages installed"
}

# This does not check versions
kubernetes_host_commands_ok() {
    if ! commandExists kubelet; then
        printf "kubelet command missing - will install host components\n"
        return 1
    fi
    if ! commandExists kubeadm; then
        printf "kubeadm command missing - will install host components\n"
        return 1
    fi
    if ! commandExists kubectl; then
        printf "kubectl command missing - will install host components\n"
        return 1
    fi

    return 0
}

function kubernetes_get_host_packages_online() {
    local k8sVersion="$1"

    if [ "$AIRGAP" != "1" ] && [ -n "$KURL_URL" ]; then
        curl -sSLO "$KURL_URL/dist/kubernetes-${k8sVersion}.tar.gz"
        tar xf kubernetes-${k8sVersion}.tar.gz
        rm kubernetes-${k8sVersion}.tar.gz
    fi
}