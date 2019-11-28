#V2的Docker化使用（ws+tls+web）

***仅出于学习目的，勿做他用***

**涉及目录的地方一概使用绝对目录，而不是相对目录，否则会有错误**



使用方式：下载脚本动态按需生成配置即可：

`dockerwall wget -N --no-check-certificate https://raw.githubusercontent.com/vizshrc/docker-v2-ws-tls-web/master/shconfig.sh && chmod +x shconfig.sh && bash shconfig.sh`

-------

##~~1.0版废弃（手动配置繁琐）~~

## ~~0.准备工作~~

```
cd ~
git clone https://github.com/vizshrc/Full-WebDAV-Nginx-Docker.git 
cd docker-v2-ws-tls-web/dockerwall
```

~~按需修改config.json~~

~~按需修改v2ray.conf~~



## ~~1.创建nginx与v2的网桥~~

```
docker network create v2-net
```



## ~~2.创建并启动v2~~
~~**vizshrc/v2s是我的个人镜像，官方是v2ray/official**~~

~~(使用nginx转发不需要映射端口，启动命令不要有点经验就想当然地写，记错了还浑然不知，说得就是我)~~  

```
docker run --name v2s --net v2-net -v ~/docker-v2-ws-tls-web/ dockerwall/config.json:/etc/v2ray/config.json -d vizshrc/v2s v2ray -config=/etc/v2ray/config.json
```

~~如果配置没问题的话这个时候v2服务应该起来了~~



##~~3.创建并启动Nginx~~

~~(-v参数表示挂载目录，按需挂载,自行调整)~~

```
docker run --name nginx -p 443:443 --net v2-net -v /root/docker-v2-ws-tls-web/dockerwall/conf.d:/etc/nginx/conf.d:ro -v /var/www:/var/www:ro -v /root:/root/:ro vizshrc/nginx
```



~~「~~

		说明：多挂载的/root目录，是因为/root是我webdav的目录（同时ssl证书也在/root下，如果不挂整				个/root，也别忘了挂载证书目录），我这个docker nginx只用来做v2+webdav，与宿主机的nginx分离				开，避免在不同的nginx下因完整的webdav功能的分歧而发生错误。配置调来调去调烦了。按需调整即				可。
	
		选看：有webdav请将.htpasswd同样放置在*/dockerwall/conf.d*目录下，配置中也写明同样的位置，否则							webdav服务起不  来。

~~」~~



~~到这里，V2和webdav的容器化已经实现。连接一下打开网页看看吧！~~



----



~~补充几个命令：~~

- ~~查看现有的网桥~~

  ~~`docker network ls`~~

- ~~查看bridge的具体信息，有哪些container连接了之类~~

  ~~`docker network inspect bridge`~~

- ~~将v2s加入v2-net~~

  ~~`docker network connect v2-net v2s	`~~

- ~~将v2s断开v2-net~~

  ~~`docker network disconnect v2-net v2s`~~



-----



~~docker nginx可以选择占用宿主机的443端口，也可以另选端口。但是既然是为了掩饰，可以让宿主机的    		nginx做端口转发到docker nginx上，这样就还是443。下面是宿主机nginx转发yourdomain.com的流量到本机的4443端口，这也是docker nginx的443端口。~~
~~端口转发样例：~~

```
#使用请修改yourdomain.com和转发端口以及path
server {
  listen 443 ssl;
  ssl_certificate       /root/.acme.sh/yourdomain.com_ecc/yourdomain.com.cer;
  ssl_certificate_key   /root/.acme.sh/yourdomain.com_ecc/fyourdomain.com.key;
  ssl_protocols         TLSv1 TLSv1.1 TLSv1.2;
  ssl_ciphers           HIGH:!aNULL:!MD5;
  server_name           yourdomain.com;

  root   /var/www/yourdomain.com;
  index  index.php index.html index.htm;


        location /ray { # 与 V2Ray 配置中的 path 保持一致
        proxy_redirect off;

        proxy_pass https://127.0.0.1:4443;
        proxy_http_version 1.1;
        proxy_set_header Upgrade $http_upgrade;
        proxy_set_header Connection "upgrade";
        proxy_set_header Host $http_host;
    
        # Show realip in v2ray access.log
        proxy_set_header X-Real-IP $remote_addr;
        # proxy_set_header Host $host;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        }

}
```



~~样例2：docker中webdav的转发处理~~

    #修改yourdomain.com和转发端口
    server {
      listen 443 ssl;
      ssl_certificate       /root/.acme.sh/yourdomain.com_ecc/yourdomain.com.cer;
      ssl_certificate_key   /root/.acme.sh/yourdomain.com_ecc/fyourdomain.com.key;
      ssl_protocols         TLSv1 TLSv1.1 TLSv1.2;
      ssl_ciphers           HIGH:!aNULL:!MD5;
      server_name           yourdomain.com;


​    
​    ~~~~
    #下面是webdav
            location / { 
            proxy_redirect off;
            proxy_pass https://127.0.0.1:4443;
            proxy_http_version 1.1;
            proxy_set_header Upgrade $http_upgrade;
            proxy_set_header Connection "upgrade";
            proxy_set_header Host $http_host;
            # Show realip in v2ray access.log
            proxy_set_header X-Real-IP $remote_addr;
            # proxy_set_header Host $host;
            proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
            }
    }
