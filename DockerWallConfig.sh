#!/bin/bash
#适用于debian系，如debian ubuntu
#测试通过环境 debian:buster  ROOT身份
#======================================================================
#检查环境，脚本是否适用，主要是linux包管理器不同，安装依赖时用apt yum不同

check_sys(){
	if [[ -f /etc/redhat-release ]]; then
		release="centos"

	elif [[ -f /etc/issue ]] && cat /etc/issue | grep -q -E -i "debian"; then
		release="debian"

	elif [[ -f /etc/issue ]] && cat /etc/issue\
   | grep -q -E -i "ubuntu"; then
		release="ubuntu"

	elif [[ -f /etc/issue ]] && cat /etc/issue\
   | grep -q -E -i "centos|red hat|redhat"; then
		release="centos"

	elif [[ -f /proc/version ]] && cat /proc/version\
   | grep -q -E -i "debian"; then
		release="debian"

	elif [[ -f /proc/version ]] && cat /proc/version\
   | grep -q -E -i "ubuntu"; then
		release="ubuntu"

	elif [[ -f /proc/version ]] && cat /proc/version\
   | grep -q -E -i "centos|red hat|redhat"; then
		release="centos"
    fi

	bit=`uname -m`

  #发行版本不符合处理（提示并退出）
    #两部分：生成配置（几乎不影响）
    #        +安装服务（看系统，不合适的话在询问安装服务时退出）
 

  #对适用发行版本的处理（定义包管理器）
     ##为了好看(习惯了debian)，所以包管理器的变量名就为apt,即${apt}
    case ${release} in
      "debian") apt=apt-get;;
      "ubuntu") apt=apt-get;;
      "centos") apt=yum;;  
    esac 
}


check_root(){
	[[ $EUID != 0 ]] && echo -e "
	当前没有ROOT权限，\
	。" && exit 1
}



#======================================================================

#全局：
  #1.设置工作目录dockerwall，不需要了删除目录即可
    #conf.d是docker nginx配置文件夹
    #其余文件默认放./dockerwall下面
cd_workdir(){

  mkdir  ./dockerwall&&cd ./dockerwall
  #$?不等于0说明前一条命令执行失败
  [[ $? -ne 0 ]]&&echo_YellowFont "文件夹已存在，是否要删除旧的然后新建【yes or no】"\
  &&read -e -p "(默认：yes删除):" dir_del\
  &&[[ -z "${dir_del}" ]]&& dir_del="yes"\

  [[ ${dir_del} == "yes" ]]&&rm -rf ./dockerwall&&mkdir dockerwall&&cd dockerwall
  #不删除文件夹，就先退出脚本
  [[ ${dir_del} == "no" ]]&&exit 1
  workdir=$(pwd)
  mkdir $(pwd)/conf.d
  echo "正在工作的目录$workdir"
}

  
  #2.优化shell脚本，设置Font_color,注意只能在使用echo时使用
echo_GreenFont(){
  #一般标志succeed
  echo -e "\033[32m$1\033[0m"
}
echo_RedFont(){
  #一般代表Error
  echo -e "\033[31m$1\033[0m"
}
echo_YellowFont(){
  #一般意味warn
  echo -e "\033[33m$1\033[0m"
}



#======================================================================

#0.安装生成配置可能的依赖
#sudo bash时，脚本内命令无需加sudo
#用变量定义不必要的软件，回头方便删除

config_depends(){
#如果是下列linux发行版就安装依赖软件
  if [[ ${release} == "debian" || ${release} == "ubuntu"\
   || ${release} == "centos" ]] ;then

    ${apt} update

    depend_soft="
      uuid-runtime
      apache2-utils
    "

    ${apt} install -y ${depend_soft}
  #非支持系统(如mac)，尝试只生成配置，不安装具体服务
  else
    uuidgen > uuidtest && rm uuidtest
    [[ $? -ne 0 ]] && echo_RedFont "请安装uuidgen对应的包" && exit 1
    #貌似重定向2>与&>没区别？？？
    htpasswd -bc ./htpasswd testuser 1234565 &> htpasswdtest && rm -rf ./htpasswd
    [[ $? -ne 0 ]] && echo_RedFont "请安装htpasswd对应的包" && exit 1
  fi
}

#======================================================================


#1.生成v2的启动配置 写成函数config_v2方便调用
#变量一览
#v2port v2的inbounds
#v2UUID 出于安全随机生成
#v2Path 即nginx分流（到v2）的标识
config_v2(){

#读入并检查端口合法性
check_port(){
read -e -p "请定义v2的inbound端口[1~65556]:" v2port\
&& [[ ${v2port} -lt 1 ]] || [[ ${v2port} -gt 65535 ]]\
&& echo_RedFont "端口错误请重新输入"&& check_port
};check_port
echo "========================"



echo -e "请定义v2通信的UUID(建议随机)"
		read -e -p "(默认:随机生成):" v2UUID
		[[ -z "${v2UUID}" ]] && v2UUID=$(uuidgen)


echo "========================"
echo -n "请定义path"
    read -e -p "(默认/ray):" v2path
    [[ -z "${v2path}" ]] && v2path="/ray"

echo "
{
  \"inbounds\": [
    {
      \"port\":${v2port},
      \"listen\":\"0.0.0.0\",//不能只监听 127.0.0.1本地，需要让别的容器探测到开放了端口
      \"protocol\": \"vmess\",
      \"settings\": {
        \"clients\": [
          {
            \"id\": \"${v2UUID}\",
            \"alterId\": 64
          }
        ]
      },
      \"streamSettings\": {
        \"network\": \"ws\",
        \"wsSettings\": {
        \"path\": \"${v2path}\"
        }
      }
    }
  ],
  \"outbounds\": [
    {
      \"protocol\": \"freedom\",
      \"settings\": {}
    }
  ]
}
"|sed '/^#/d;/^\s*$/d' > config.json
echo_GreenFont "已经生成v2ray的启动配置（config.json）"
}


#======================================================================

#2.函数config_nginx:生成docker nignx的转发配置
#ssl 默认是使用acme.sh申请的letsencrypt的证书的地址
#如果不是，则选择自定义ssl_certificate和ssl_certificate_key
#所以两个echo看情况生成配置
#######变量一览
#v2web 伪装的网页地址
#check_sslpath 向用户确认是否可以使用默认的ssl证书路径
#v2path 上面config_v2中已定义，这里跟随 
##选择自定ssl证书路径时，增加ssl_certificate、ssl_certificate_key
config_nginx(){
echo -n "输入你的v2伪装网址:";read v2web
#检查v2path是否有在config_v2中定义（如选择只生成nginx配置时，需本函数内生成）
[[ -z "${v2path}" ]] && read -e -p "（未定义path,请先定义）:" v2path

echo -e "ssl证书是否用acme.sh申请？且位于/root/.acme目录下？"
	read -e -p "(默认：yes):" check_sslpath
	[[ -z "${check_sslpath}" ]] && check_sslpath="yes"
if [[ ${check_sslpath} == "yes" ]] ; then


#必须检查证书是否存在
#那么你的证书路径是/root/.acme.sh/${v2web}_ecc/${v2web}.cer
  if [[ -f /root/.acme.sh/${v2web}_ecc/${v2web}.cer ]]\
    && [[ -f /root/.acme.sh/${v2web}_ecc/${v2web}.key ]] ; then
      echo "证书路径正确"
  else
    echo_RedFont "未找到证书，请检查证书路径是否有误并重新配置"&&exit 1
  fi

#证书没问题则生成配置
echo "
server {
  listen 0.0.0.0:443 ssl;
  ssl_certificate       /root/.acme.sh/${v2web}_ecc/${v2web}.cer;
  ssl_certificate_key   /root/.acme.sh/${v2web}_ecc/${v2web}.key;
  ssl_protocols         TLSv1 TLSv1.1 TLSv1.2 TLSv1.3;
  ssl_ciphers           HIGH:!aNULL:!MD5;
  server_name           ${v2web};

##
  root   /var/www/${v2web};
  index  index.php index.html index.htm;
##
        location ${v2path} { # 与 V2 配置中的 path 保持一致
        proxy_redirect off;
        proxy_pass http://v2s:${v2port};
        proxy_http_version 1.1;
        proxy_set_header Upgrade \$http_upgrade;
        proxy_set_header Connection "upgrade";
        proxy_set_header Host \$http_host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        }
}
"|sed '/^#/d;/^\s*$/d' > ${workdir}/conf.d/v2ray.conf


##如果ssl证书地址有变则自定义
else
	echo -e "请输入你的ssl_certificate路径"
	read -e -p "例如/root/.acme.sh/web.com_ecc/web.com.cer :" ssl_certificate
	echo
	echo -e "请输入你的ssl_certificate_key路径"
	read -e -p "例如/root/.acme.sh/web.com_ecc/web.com.key :" ssl_certificate_key
  #开始检查证书,不合法直接退出
    if [[ -f ${ssl_certificate} ]] && [[ -f ${ssl_certificate} ]] ; then
      echo "证书路径正确"
    else
      echo_RedFont "未找到证书，请检查证书路径是否有误并重新配置"&&exit 1
    fi

	echo "
server {
  listen 0.0.0.0:443 ssl;
  ssl_certificate       ${ssl_certificate};
  ssl_certificate_key   ${ssl_certificate_key};
  ssl_protocols         TLSv1 TLSv1.1 TLSv1.2 TLSv1.3;
  ssl_ciphers           HIGH:!aNULL:!MD5;
  server_name           ${v2web};

##这里说明网站地址
  root   /var/www/${v2web};
  index  index.php index.html index.htm;


#下面是v2ray
        location ${v2path} { # 与 V2Ray 配置中的 path 保持一致
        proxy_redirect off;
        
        proxy_pass http://v2s:${v2port};
        proxy_http_version 1.1;
        proxy_set_header Upgrade \$http_upgrade;
        proxy_set_header Connection "upgrade";
        proxy_set_header Host \$http_host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        }
}
"|sed '/^#/d;/^\s*$/d' > ${workdir}/conf.d/v2ray.conf
fi


echo_GreenFont "已经生成nginx关于v2ray的配置（v2ray.conf）"
}


#=============================================-=============================
#变量一览
#need_webdav 标记是否生成webdav配置 yes or no
#site_webdav webdav的访问网址
#content_webdav webdav展现的文件目录
##check_sslpath 来自config_v2，上面非默认则这里也自定义
##当check_sslpath未定义，将在conf_webdav内定义


config_webdav(){

	read -e -p "(输入webdav访问网址):" site_webdav
	read -e -p "(想要在网页展示的目录):" content_webdav
	read -e -p "(设置webdav服务的账号名):" user_webdav
	htpasswd -c ./conf.d/.htpasswd ${user_webdav}
#检查check_sslpath是否有在config_nginx中定义，如未自行定义
  [[ -z "${check_sslpath}" ]] && echo -e \
  "ssl证书是否用acme.sh申请？且位于/root/.acme目录下？"\
  &&read -e -p "(默认：yes):" check_sslpath\
  &&[[ -z "${check_sslpath}" ]] && check_sslpath="yes"

if [[ ${check_sslpath} == "yes" ]] ; then
#echo "你可能需要手动编辑稍后生成的配置里的ssl证书路径"
echo "那么你的证书路径是\
/root/.acme.sh/${site_webdav}_ecc/${site_webdav}.cer;错误的路径将导致配置失败"
echo "
server {
  listen 443 ssl;
  ssl_certificate       /root/.acme.sh/${site_webdav}_ecc/${site_webdav}.cer;
  ssl_certificate_key   /root/.acme.sh/${site_webdav}_ecc/${site_webdav}.key;
  ssl_protocols         TLSv1 TLSv1.1 TLSv1.2 TLSv1.3;
  ssl_ciphers           HIGH:!aNULL:!MD5;
  server_name           ${site_webdav};

    error_log /var/log/nginx/webdav.error.log error;
    access_log  /var/log/nginx/webdav.access.log combined;
    location / {
        root ${content_webdav};
        charset utf-8;
        autoindex on;
        dav_methods PUT DELETE MKCOL COPY MOVE;
        dav_ext_methods PROPFIND OPTIONS;
        create_full_put_path  on;
        dav_access user:rw group:r all:r;
        auth_basic \"Authorized Users Only\";
        auth_basic_user_file ${workdir}/conf.d/.htpasswd;
        client_max_body_size 100m;
    }
    error_page   500 502 503 504  /50x.html;
    location = /50x.html {
   root   /usr/share/nginx/html; 
   }
}
"|sed '/^#/d;/^\s*$/d' > ${workdir}/conf.d/davhttps.conf\
&&echo_GreenFont "webdav设置已经生成"


##若证书非默认路径，则生成自定义路径的webdav配置,
#生成两份配置实在麻烦，其实应该将ssl证书路径单独拎出来定义
else
  echo -e "请输入你的ssl_certificate路径"\
	&&read -e -p "例如/root/.acme.sh/web.com_ecc/web.com.cer :" ssl_certificate\
	&&echo\
	&&echo -e "请输入你的ssl_certificate_key路径"\
	&&read -e -p "例如/root/.acme.sh/web.com_ecc/web.com.key :" ssl_certificate_key\
	&&echo "
server {
  listen 443 ssl;
  ssl_certificate       ${ssl_certificate};
  ssl_certificate_key   ${ssl_certificate_key};
  ssl_protocols         TLSv1 TLSv1.1 TLSv1.2 TLSv1.3;
  ssl_ciphers           HIGH:!aNULL:!MD5;
  server_name           ${site_webdav};

    error_log /var/log/nginx/webdav.error.log error;
    access_log  /var/log/nginx/webdav.access.log combined;
    location / {
        root ${content_webdav};
        charset utf-8;
        autoindex on;
        dav_methods PUT DELETE MKCOL COPY MOVE;
        dav_ext_methods PROPFIND OPTIONS;
        create_full_put_path  on;
        dav_access user:rw group:r all:r;
        auth_basic \"Authorized Users Only\";
        auth_basic_user_file ${workdir}/conf.d/.htpasswd;
        client_max_body_size 100m;
    }
    error_page   500 502 503 504  /50x.html;
    location = /50x.html {
   root   /usr/share/nginx/html; 
   }
}
"|sed '/^#/d;/^\s*$/d' > ${workdir}/conf.d/davhttps.conf\
&&echo_GreenFont "webdav设置已经生成"
fi

}

#=============================================-=============================
#生成docker-compose.yml
  #不做过多变量处理，多了就失去意义，这个文件本来就是灵活的，
  #这里只是简单生成一个模板，按需修改即可
##变量一览
#image_nginx image_v2ray 镜像来源（仓库）
#port_host 占用的宿主机端口

config_docker(){
  read -e -p \
  "(可定义nginx的image，带webDAV请默认：vizshrc/nginx):" image_nginx
  [[ -z ${image_nginx} ]] && image_nginx=vizshrc/nginx
  echo
  read -e -p \
  "(可定义v2ray的image，默认官方：v2ray/official):" image_v2ray
  [[ -z ${image_v2ray} ]] && image_v2ray=v2ray/official
  echo
  echo "设置docker nginx（443）要映射（要占用）的宿主机的端口"
  
  #默认使用宿主机nginx转发docker nginx模式
  check_port_host(){
    read -e -p \
    "(不建议使用443 默认4443:" port_host
    [[ -z ${port_host} ]] && port_host=4443
    #检查端口是否别的程序被占用（宿主机）

    netstat -anp | grep ${port_host}
    if [[ $? -eq 0 ]] ; then
      echo_RedFont "该端口已被占用，请改用别的端口"&& check_port_host
    fi
  };check_port_host

#如果将docker nginx映射宿主机443，使用443：443
  #使用127.0.0.1：443：443会让流量到不了V2
  #使用前者将扩大攻击面即0.0.0.0，
  #因此这里将判断映射端口，决定使用0.0.0.0还是127.0.0.1
  #当非443，进行重定义
  [[ ${port_host} != "443" ]] && port_host=127.0.0.1:${port_host}

  echo "
#使用命令 docker-compose up -d
#就会拉取镜像再创建我们所需要的镜像
#然后启动nginx和v2ray容器

version: \"3\"

services:
  nginx:
    image: ${image_nginx}
    container_name: v2nginx
    ports:
#     - \"80:80\"
      - \"${port_host}:443\"

    volumes:
     - ${workdir}/conf.d:/etc/nginx/conf.d:ro
     - /var/www:/var/www:ro
     - /root:/root/:ro #webdav目录以及ssl目录/root/.acme 
    restart: always

  v2ray:
    depends_on:
      - nginx
    image: ${image_v2ray}
    container_name: v2s
    volumes:
       - ./config.json:/etc/v2ray/config.json
    restart: always  

"|sed '/^#/d;/^\s*$/d' > ${workdir}/docker-compose.yml
}

#=============================================-=============================

#该函数调用前提是检查映射的宿主机端口非443
#不是443则询问是否要生成中的.conf配置文件
 #让宿主机nginx（443识别流量后）转发到本地相应端口（即被docker nginx映射的端口）
#即流量走向：客户端-->宿主机nginx-->docker nginx-->docker v2
##变量一览
 #proxy_pass_docker 标记是否生成转发配置
 #check_sslpath 来自config_nginx 判断ssl证书路径是使用默认还是自定义
  #这将决定ssl配置



config_host_nginx(){
echo_YellowFont "docker nginx使用的宿主机端口非443！"
echo_YellowFont "是否生成宿主机nginx配置？并启动服务将流量转发到docker nginx中？"\
&&read -e -p '(默认生成：yes)' proxy_pass_docker\
&&[[ -z ${proxy_pass_docker} ]] && proxy_pass_docker=yes
if [[ ${proxy_pass_docker} == "yes" ]] ; then

  if [[ ${check_sslpath} == "yes" ]] ; then
    echo "
server {
  listen 443 ssl;
  ssl_certificate       /root/.acme.sh/${v2web}_ecc/${v2web}.cer;
  ssl_certificate_key   /root/.acme.sh/${v2web}_ecc/${v2web}.key;
  ssl_protocols         TLSv1 TLSv1.1 TLSv1.2 TLSv1.3;
  ssl_ciphers           HIGH:!aNULL:!MD5;
  server_name           ${v2web};

##
  root   /var/www/${v2web};
  index  index.php index.html index.htm;
##
        location ${v2path} { # 与 V2 配置中的 path 保持一致
        proxy_redirect off;
        proxy_pass https://127.0.0.1:${port_host}; #只有这需要https
        proxy_http_version 1.1;
        proxy_set_header Upgrade \$http_upgrade;
        proxy_set_header Connection "upgrade";
        proxy_set_header Host \$http_host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        }
}
"|sed '/^#/d;/^\s*$/d' > ${workdir}/v2-pass-docker.conf\
&&echo_GreenFont "生成v2-pass-docker"
#**********若使用webDAV，这里顺便生成的转发配置1**************
    [[ ${need_webdav} == "yes" ]]&&echo "
server {
  listen  443 ssl;
  ssl_certificate       /root/.acme.sh/${site_webdav}_ecc/${site_webdav}.cer;
  ssl_certificate_key   /root/.acme.sh/${site_webdav}_ecc/${site_webdav}.key;
  ssl_protocols         TLSv1 TLSv1.1 TLSv1.2 TLSv1.3;
  ssl_ciphers           HIGH:!aNULL:!MD5;
  server_name           ${site_webdav};

        location / { 
        proxy_redirect off;
        proxy_pass https://127.0.0.1:${port_host};
        proxy_http_version 1.1;
        proxy_set_header Upgrade \$http_upgrade;
        proxy_set_header Connection "upgrade";
        proxy_set_header Host \$http_host;

        # Show realip in v2ray access.log
        proxy_set_header X-Real-IP \$remote_addr;
        # proxy_set_header Host \$host;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        }
}
"|sed '/^#/d;/^\s*$/d' > ${workdir}/dav-pass-docker.conf\
&&echo_GreenFont "生成dav-pass-docker"
  #fi


  else
    echo "
server {
  listen 0.0.0.0:443 ssl;
  ssl_certificate       ${ssl_certificate};
  ssl_certificate_key   ${ssl_certificate_key};
  ssl_protocols         TLSv1 TLSv1.1 TLSv1.2 TLSv1.3;
  ssl_ciphers           HIGH:!aNULL:!MD5;
  server_name           ${v2web};

##
  root   /var/www/${v2web};
  index  index.php index.html index.htm;


#下面是v2ray
        location ${v2path} { # 与 V2Ray 配置中的 path 保持一致
        proxy_redirect off;       
        proxy_pass https://127.0.0.1:${port_host}; #只有这需要https
        proxy_http_version 1.1;
        proxy_set_header Upgrade \$http_upgrade;
        proxy_set_header Connection "upgrade";
        proxy_set_header Host \$http_host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        }
}
"|sed '/^#/d;/^\s*$/d' > ${workdir}/v2-pass-docker.conf\
&&echo_GreenFont "生成v2-pass-docker.conf"
  #***********也顺便生成webdav宿主机转发配置2*****************
  [[ ${need_webdav} == "yes" ]]&&echo "
server {
  listen  443 ssl;
  ssl_certificate       ${ssl_certificate};
  ssl_certificate_key   ${ssl_certificate_key};
  ssl_protocols         TLSv1 TLSv1.1 TLSv1.2 TLSv1.3;
  ssl_ciphers           HIGH:!aNULL:!MD5;
  server_name           ${site_webdav};

        location / { 
        proxy_redirect off;
        proxy_pass https://127.0.0.1:${port_host};
        proxy_http_version 1.1;
        proxy_set_header Upgrade \$http_upgrade;
        proxy_set_header Connection "upgrade";
        proxy_set_header Host \$http_host;

        # Show realip in v2ray access.log
        proxy_set_header X-Real-IP \$remote_addr;
        # proxy_set_header Host \$host;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        }
}
"|sed '/^#/d;/^\s*$/d' > ${workdir}/dav-pass-docker.conf\
&& echo_GreenFont "生成dav-pass-docker.conf"
  fi 
fi
}



#=============================================-=============================
#启动服务
start_service(){
  #安装前确认系统符合与否
  if [[ ${apt} != "apt-get" ]] && [[ ${apt} != "yum" ]] ; then 
    echo_RedFont "你的系统不是debian、ubuntu或centos,不能使用该脚本安装相应的服务(docker、compose、nginx)"\
    &&exit 1
  fi

#1.docker-compose up -d
#检查是否安装docker和compose,没有则询问安装
 check_install_docker(){
  dpkg -l | grep -i docker
  [[ $? -ne 0 ]] && read -e -p \
  "当前似乎未安装docker,是否现在安装？默认:yes)：" install_docker\
  &&[[ -z ${install_docker} ]] && install_docker="yes"
  #注意上面的逻辑，只有没安装才需要读入，没有&&连接将使这个读入失效
  if [[ ${install_docker} == "yes" ]];then
    curl -fsSL get.docker.com -o get-docker.sh\
    && chmod +x get-docker.sh && bash get-docker.sh
    docker run --rm hello-world
    [[ $? -ne 0 ]] && echo_RedFont "docker-ce（stable安装失败）" && exit 1
    #安装docker compose
    curl -L https://github.com/docker/compose/releases/download/1.24.1/\
    docker-compose-`uname -s`-`uname -m` -o /usr/local/bin/docker-compose\
    &&chmod +x /usr/local/bin/docker-compose
    [[ $? -ne 0 ]] && echo_RedFont "docker-compose（1.24.1安装失败）" && exit 1
  fi
 }


#2.是否需要宿主机nginx转发服务
#此时转发配置生成了，尚未移动到/etc/nginx/conf.d并重载宿主机nginx配置
 check_install_nginx(){
    if [[ ${proxy_pass_docker} == "yes" ]] ; then
      echo "配置完成，现在实现宿主机nginx转发"
      dpkg -l | grep -i nginx
      [[ $? -ne 0 ]] && ${apt} install -y nginx
      #把配置拉过去并重启nignx
      mv ${workdir}/*pass-docker.conf /etc/nginx/conf.d
      [[ $? -ne 0 ]] && echo_RedFont "移动配置到/etc/nginx/conf.d失败" && exit 1
      service nginx restart&&echo "nginx启动成功"
    fi 
  }



check_install_docker
check_install_nginx
docker-compose up -d\
 && echo_GreenFont "Everything is ok! Now try it!"\
 && rm ../$0
}
#=============================================-=============================

#输出必要信息一览表
view_info(){
  echo -e "==============================================="
  [[ ${need_v2} == "yes" ]] && echo_GreenFont "
  v2客户端连接信息
  类型：VMess
  地址：${v2web}
  端口：443
  UUID：${v2UUID}
  类型：ws
  路径(URL):${v2path}
  TLS:1（打开）
  "
  echo -e "==============================================="
  [[ ${need_webdav} == "yes" ]] \
  && echo_GreenFont "
  webDAV
  访问网址：${site_webdav} 
  用户名：${user_webdav}
  密码：天知地知 你知我不知
  "
  echo -e "==============================================="
}
#=============================================-=============================


#主程序 依序调用函数
echo
    check_sys
    check_root
    cd_workdir
    config_depends
echo
echo -e "======================================================"
echo_GreenFont "||所有选项均为yes or no,注意大小写，否则配置可能失败||"
echo -e "======================================================"
echo -e "生成v2的启动配置？"
    read -e -p '(默认：yes):' need_v2
#这是一个逻辑错误，这个句子这样不能连写，应该拆开。否则手动输入不调用
#    [[ -z "${need_v2}" ]] && need_v2="yes" && config_v2
    [[ -z "${need_v2}" ]] && need_v2="yes"
    [[ ${need_v2} == "yes" ]] && config_v2
echo
echo -e "生成nginx的分流配置？"
    read -e -p "默认yes:" need_nginx
    [[ -z "${need_nginx}" ]] && need_nginx="yes" 
    [[ ${need_nginx} == "yes" ]] && config_nginx
echo
echo -e "生成webDAV的访问配置?"
    read -e -p "默认yes:" need_webdav
    [[ -z "${need_webdav}" ]] && need_webdav="yes" 
    [[ ${need_webdav} == "yes" ]] && config_webdav
echo
echo -e "生成v2的docker-compose的配置?"
    read -e -p '(默认: yes):' need_docker
    [[ -z "${need_docker}" ]] && need_docker="yes" 
    [[ ${need_docker} == "yes" ]] && config_docker
echo
[[ ${port_host} != 443 ]] && config_host_nginx
echo
echo -e "现在启动服务？"
    read -e -p "(默认：yes):" need_service
    [[ -z ${need_service} ]] && need_service="yes"
    [[ ${need_service} == "yes" ]] && start_service
echo
    view_info
echo

#=============================================-=============================
#author:vizshrc
#脚本编写心得
  #守则：清晰简要
  #不做不必要的合法输入类的检查，只保证脚本完整执行，否则与方便配置的初衷背道而驰¬
