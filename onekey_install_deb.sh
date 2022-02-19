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
    green "========================="
    yellow "请输入绑定到本VPS的域名"
    yellow "   安装时请关闭CDN"
    green "========================="
    read your_domain
    real_addr=`ping ${your_domain} -c 1 | sed '1{s/[^(]*(//;s/).*//;q}'`
    local_addr=`curl ip.sb`
    if [ $real_addr == $local_addr ] ; then
        green "============================="
        green "域名解析正常，开始安装爬虫"
        green "============================="
        sleep 1s
        red "是否需要关闭防火墙? y/n "
        read firewall_choice
        if [ $firewall_choice == y ] ; then
          firewall_config
        fi
        download_pc
        install_socat
        install_nginx
        config_ssl
    else
        red "================================="
        red "域名解析地址与本VPS IP地址不一致"
        red "本次安装失败，请确保域名解析正常"
        red "================================="
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
    green " Installing SoCat"
    green "==================="
    apt-get install -y socat
}

install_nginx(){
    echo
    echo
    green "==============="
    green "  2.安装nginx"
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

    curl https://get.acme.sh | sh -s email=daycat@mail.io
    ~/.acme.sh/acme.sh  --set-default-ca --server letsencrypt
    ~/.acme.sh/acme.sh  --issue  -d $your_domain  --standalone
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
    green " 3.验证ssl证书"
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
  
}


download_pc(){
    echo
    green "==============="
    green "  1.安装爬虫"
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
        echo Architecture not supported by this script. Please submit issue of PR on github.
        exit 1
        ;;
    esac

    wget https://raw.githubusercontent.com/lanhebe/proxypool/master/config.yaml
    wget https://raw.githubusercontent.com/lanhebe/proxypool/master/source.yaml
   
    cat > ./config.yaml <<-EOF
    domain: $your_domain
    port:                 # default 12580
    # source list file
    source-files:
      # use local file
      - ./source.yaml
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
   
    nohup ./proxypool -c config.yaml >/dev/null 2>/dev/null &
    
}



uninstall_pc(){
    red "============================================="
    red "你的pc数据将全部丢失！！你确定要卸载吗？"
    read -s -n1 -p "按回车键开始卸载，按ctrl+c取消"
    apt remove -y nginx
    pkill proxypool
    rm -rf ~/proxypool
    rm -rf ~/config.yaml
    rm -rf ~/source.yaml
    green "=========="
    green " 卸载完成"
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
    yellow " You are using a DEV version. Shit will not work!!!"
    green "====================================================="
    green "1. 一键安装免费节点爬虫"
    red "2. 卸载爬虫"
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
