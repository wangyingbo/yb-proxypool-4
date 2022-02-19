#!/bin/bash
 
blue(){
    echo -e "\033[34m\033[01m$1\033[0m"
}
green(){
    echo -e "\033[32m\033[01m$1\033[0m"
}
red(){
    echo -e "\033[31m\033[01m$1\033[0m"
}
yellow(){
    echo -e "\033[33m\033[01m$1\033[0m"
}

check_domain(){
    green "================================="
    green "  我们需要你的邮箱用于ssl证书申请"
    yellow "  请输入你的邮箱："
    green "================================="
    read your_email
    green "================================="
    yellow " 请输入绑定到本VPS的域名"
    green "================================="
    read your_domain
    real_addr=`ping ${your_domain} -c 1 | sed '1{s/[^(]*(//;s/).*//;q}'`
    local_addr=`curl ip.sb`
    if [ $real_addr == $local_addr ] ; then
        green "================================="
        green "  域名解析正常，开始安装爬虫"
        green "================================="
        sleep 1s
        yellow "是否需要关闭防火墙? （如果不确认请选择y）y/n "
        read firewall_choice
        if [ $firewall_choice == y ] ; then
          firewall_config
        fi
        download_pc
        install_socat
        install_nginx
        config_ssl
    else
        red "====================================="
        red "    域名解析地址与本VPS IP地址不一致"
        yellow "  如果你开启了CDN，请先关闭CDN重试"
        red "====================================="
        exit 1
    fi
}

firewall_config(){
    echo
    iptables -I INPUT -p tcp --dport 443 -j ACCEPT
    iptables -I INPUT -p tcp --dport 80 -j ACCEPT
    bash -c "iptables-save > /etc/iptables/rules.v4"
    yellow "iptables 已开放 443 & 80"
    echo
    ufw allow 443
    ufw allow 80
    yellow "ufw 已开放 443 & 80"
    echo
    echo
    green "如果没有其他的防火墙，那么应该已经全部开启"

}

install_socat(){
    echo
    echo
    green "==================="
    green "  1.安装 SoCat"
    green "==================="
    sleep 1
    apt-get install -y socat
}

install_nginx(){
    echo
    echo
    green "==============="
    green "  2.安装 Nginx"
    green "==============="
    sleep 1
    apt-get install -y nginx
    systemctl enable nginx.service
    systemctl stop nginx.service
    rm -f /etc/nginx/conf.d/default.conf
    rm -f /etc/nginx/nginx.conf
    mkdir /etc/nginx/ssl

cat > /etc/nginx/nginx.conf <<-EOF
user  root;
worker_processes  1;
error_log  /var/log/nginx/error.log warn;
pid        /var/run/nginx.pid;
events {
    worker_connections  1024;
}
http {
    include       /etc/nginx/mime.types;
    default_type  application/octet-stream;
    log_format  main  '\$remote_addr - \$remote_user [\$time_local] "\$request" '
                      '\$status \$body_bytes_sent "\$http_referer" '
                      '"\$http_user_agent" "\$http_x_forwarded_for"';
    access_log  /var/log/nginx/access.log  main;
    error_log /var/log/nginx/error.log error;
    sendfile        on;
    #tcp_nopush     on;
    keepalive_timeout  120;
    client_max_body_size 20m;
    #gzip  on;
    include /etc/nginx/conf.d/*.conf;
}
EOF
    green "==================="
    green "  2.1 安装 ACME"
    green "==================="
    sleep 1
    curl https://get.acme.sh | sh -s email=$your_email
    ~/.acme.sh/acme.sh  --set-default-ca --server letsencrypt
    green "==================="
    green "  2.2 申请 SSL 证书"
    green "==================="
    sleep 1
    ~/.acme.sh/acme.sh  --issue  -d $your_domain  --standalone
    green "==================="
    green "  2.1 安装 SSL 证书"
    green "==================="
    sleep 1
    ~/.acme.sh/acme.sh  --installcert  -d  $your_domain   \
        --key-file   /etc/nginx/ssl/$your_domain.key \
        --fullchain-file /etc/nginx/ssl/fullchain.cer

cat > /etc/nginx/conf.d/default.conf<<-EOF
server {
    listen 80 default_server;
    server_name _;
    return 404;  
}
server {
    listen 443 ssl default_server;
    server_name _;
    ssl_certificate /etc/nginx/ssl/fullchain.cer; 
    ssl_certificate_key /etc/nginx/ssl/$your_domain.key;
    return 404;
}
server { 
    listen       80;
    server_name  $your_domain;
    rewrite ^(.*)$  https://\$host\$1 permanent; 
}
server {
    listen 443 ssl http2;
    server_name $your_domain;
    root /usr/share/nginx/html;
    index index.php index.html;
    ssl_certificate /etc/nginx/ssl/fullchain.cer; 
    ssl_certificate_key /etc/nginx/ssl/$your_domain.key;
    ssl_stapling on;
    ssl_stapling_verify on;
    add_header Strict-Transport-Security "max-age=31536000";
    access_log /var/log/nginx/hostscube.log combined;
    location ~ \.php$ {
        fastcgi_pass 127.0.0.1:9000;
        fastcgi_param SCRIPT_FILENAME \$document_root\$fastcgi_script_name;
        include fastcgi_params;
    }
    location / {
       proxy_pass http://127.0.0.1:12580/;
    }
}
EOF

}


config_ssl(){

    echo
    green "===================="
    green " 3. 校验 SSL 证书"
    green "===================="
    echo
    echo
    sleep 1
    systemctl restart nginx.service
    ~/.acme.sh/acme.sh  --issue --force  -d $your_domain  --nginx
    ~/.acme.sh/acme.sh  --installcert  -d  $your_domain   \
        --key-file   /etc/nginx/ssl/$your_domain.key \
        --fullchain-file /etc/nginx/ssl/fullchain.cer \
        --reloadcmd  "systemctl restart nginx"	
    sleep 1
    echo
    green "===================="
    green " Nginx安装成功"
    green "===================="
    echo
    echo
    echo
    green "===================================================="
    green " 你的ProxyPool 已成功安装！"
    green " 请通过 https://$your_domain 访问 "
    green " ProxyPool 的默认配置文件在以下路径："
    green " $config_path"
    green " 如果需要更换配置文件源至网页配置文件，请修改以下文件："
    green " /etc/systemd/system/proxypool.service"
    green " 可以使用systemctl控制 proxypool!"
    green " 例如： systemctl restart proxypool"
    echo
    echo
    echo "    那么，如果我做的不错的话，考虑给我买杯咖啡？:D"
    echo "    谢谢各位的投喂！ 喵！"
    echo "    BTC: bc1qlj06ehffq33defvh4z84fm3mgle44e799gfg5p"
    echo "    USDT-TRC20：TBLAmCewbKw62vWLqWh1CthGC3TJbU9yPd"
    echo "    Blog: https://daycat.space"
    echo "    此外，非常感谢原作者以及所有fork作者！"
    green " 原作者：https://github.com/zu1k"
    green " fork: yourp112：https://github.com/yourp112"
    green " fork: Sansui233：https://github.com/Sansui233"
    green " fork: lanhebe：https://github.com/lanhebe"
    green " fork: daycat: https://github.com/daycat"
    green "===================================================="
}


download_pc(){
    echo
    green "==============="
    green "  0.下载爬虫"
    green "==============="
    sleep 1
    case $(uname -m) in
      "x86_64" ) wget https://github.com/daycat/proxypool/releases/download/latest/proxypool-linux-amd64
        mv proxypool-linux-amd64 proxypool
        chmod +x proxypool
        ;;
      "i686" ) wget https://github.com/daycat/proxypool/releases/download/latest/proxypool-linux-386
        mv proxypool-linux-386 proxypool
        chmod +x proxypool
        ;;
      "aarch64" ) wget https://github.com/daycat/proxypool/releases/download/latest/proxypool-linux-arm64
        mv proxypool-linux-arm64 proxypool
        chmod +x proxypool
        ;;
      "s390x" ) wget https://github.com/daycat/proxypool/releases/download/latest/proxypool-linux-s390x
        mv proxypool-linux-s390x proxypool
        chmod +x proxypool
        ;;
      "armv5l" ) wget https://github.com/daycat/proxypool/releases/download/latest/proxypool-linux-arm-5
        mv proxypool-linux-arm-5 proxypool
        chmod +x proxypool
        ;;
      "armv6l" ) wget https://github.com/daycat/proxypool/releases/download/latest/proxypool-linux-arm-6
        mv proxypool-linux-arm-6 proxypool
        chmod +x proxypool
        ;;
      "armv7l" ) wget https://github.com/daycat/proxypool/releases/download/latest/proxypool-linux-arm-7
        mv proxypool-linux-arm-7 proxypool
        chmod +x proxypool
        ;;
      *)
        red "@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@"
        red "  此脚本不支持你使用的系统架构，请使用手动安装"
        red "@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@"
        exit 1
        ;;
    esac

    wget https://raw.githubusercontent.com/daycat/proxypool/master/config.yaml
    wget https://raw.githubusercontent.com/daycat/proxypool/master/source.yaml
   
    cat > ./config.yaml <<-EOF
    domain: $your_domain
    port:                 # default 12580
    # source list file
    source-files:
      # use local file
      - #config_path/source.yaml
      # use web file
      # - https://example.com/config/source.yaml
    # ======= 可选项，留空使用default值  =======
    # postgresql database info
    database_url: ""
    # interval between each crawling
    crawl-interval:       # v0.5.x default 60 (minutes)
    crontime:             # v0.4.x default 60 (minutes). Deprecated in the newest version
    # speed test
    speedtest: false      # default false. Warning: this will consume large network resources.
    speedtest-interval:   # default 720 (min)
    connection:           # default 5. The number of speed test connections simultaneously
    timeout:              # default 10 (seconds).
    ## active proxy speed test
    active-interval:      # default 60 (min)
    active-frequency:     # default 100 (requests per interval)
    active-max-number:    # default 100. If more than this number of active proxies, the extra will be deprecated by speed
    # cloudflare api
    cf_email: ""
    cf_key: ""
EOF

    config_path=`pwd`
    cat > /etc/systemd/system/proxypool.service<<-EOF
    [Unit]
    Description=A Proxypool written in GoLang to crawl websites for V2ray & trojan proxies
    After=network.target
    StartLimitIntervalSec=10

    [Service]
    Type=simple
    Restart=always
    RestartSec=1
    User=root
    ExecStart=$config_path/proxypool -c $config_path/config.yaml
    Restart=on-failure

    [Install]
    WantedBy=multi-user.target
EOF
    systemctl start proxypool
}



uninstall_pc(){
    red "============================================="
    red " 你的proxypool数据将全部丢失！！你确定要卸载吗？"
    read -s -n1 -p "按回车键开始卸载，按ctrl+c取消"
    apt remove -y nginx
    systemctl stop proxypool
    rm -rf ~/proxypool
    rm -rf ~/config.yaml
    rm -rf ~/source.yaml
    rm -rf /etc/systemd/system/proxypool.service
    green "=========="
    green " 卸载完成 "
    green "=========="
}

start_menu(){
    clear
    green "====================================================="
    green " 适用于Debian | Ubuntu，一键安装节点爬虫"
    green " Original RHEL script made by Littleyu"
    green " Modified by dayCat for use with Debian based systems"
    green " This script is first published on:"
    green "     https://github.com/daycat/proxypool"
    green "====================================================="
    green "1. 一键安装节点爬虫"
    green "2. 卸载爬虫"
    yellow "0. 退出脚本"
    echo
    read -p "请输入数字:" num
    case "$num" in
    1)
    check_domain
    ;;
    2)
    uninstall_pc
    ;;
    0)
    exit 1
    ;;
    *)
    clear
    echo "请输入正确数字"
    sleep 2s
    start_menu
    ;;
    esac
}

start_menu
