#Docker学习笔记：

##一些命令：

`docker run -it debian /bin/bash`

-- 新建并启动一个container,每次进入都是新的.t是为终端,i代表实时交互。

`docker run -it -v /Volumes/TimeMachine/Docker/debian:/root debian bash`       
-- 容器必须依赖（挂载）一个真实的宿主机目录才能保存文件?非也。-v只是挂载目录，方便文件的使用和存		  储，即使container消失，该目录的文件更改也是不丢失的。此时进入container。



- 列出所有的容器 ID
  `docker ps -aq`

- 停止所有的容器
  `docker stop $(docker ps -aq)`

- 删除所有的容器
  `docker rm $(docker ps -aq)`

- 删除所有的镜像
  `docker rmi $(docker images -q)`

暂时没用过的「
		复制文件
		docker cp mycontainer:/opt/file.txt /opt/local/
		docker cp /opt/local/file.txt mycontainer:/opt/
		docker有专门清理资源(container、image、网络)的命令。 docker 1.13 中增加了 docker system prune的命令，针对			container、image可以使用docker container prune、docker image prune命令。

		docker image prune --force --all或者docker image prune -f -a` : 删除所有不使用的镜像
		docker container prune -f: 删除所有停止的容器
」

- 创建容器并自定义名称(--name)
  `debian docker run -dit --name debian9 -v /Volumes/TimeMachine/Docker/debian:/root debian /bin/bash`

- 启动并进入容器,exec确保退出容器时保持后台运行。attach退出即关闭
  `debian docker start debian9 && docker exec -it debian9 /bin/bash`

  

----



`docker run -d --name v2ray -v /Volumes/TimeMachine/Docker/v2ray:/etc/v2ray -p 8888:1080 v2ray/official  v2ray -config=/etc/v2ray/config.json`



我们在这里使用了几个常见的标志：

-p （即主机0.0.0.0） 要求Docker将主机端口8000上传入的流量转发到容器的端口8080（容器具有自己的专用端口集，因此如果我们要从网络访问一个端口，则必须以这种方式将流量转发给它;否则，防火墙规则将阻止所有网络流量到达您的容器，这是默认的安全状态）。
-d 要求Docker在后台运行此容器。
--name让我们指定一个名称，在以后的命令中，我们可以使用该名称来引用我们的容器bb。
还要注意，我们没有指定我们要运行容器的进程。我们没有必要，因为我们CMD在构建Dockerfile时使用了指令。因此，Docker知道npm start在容器启动时会自动运行该过程。

在的浏览器中访问您的应用程序localhost:8000。现在是运行单元测试的时候了。(在mac的docker)

`docker run --publish 8888:1080 -d --name v2ray -v /Volumes/TimeMachine/Docker/v2ray:/etc/v2ray  v2ray/official  v2ray -config=/etc/v2ray/config.json`

//这里要特别注意，按我这条命令，config.json文件是在/Volumes/TimeMachine/Docker/v2ray目录下，这个客户端文件的监听地址一定要是0.0.0.0，而不是127.0.0.1,否则服务起来了，宿主机是无法访问docker的这项服务，你只是允许访问docker端口，而docker中这项服务是拒绝外部主机访问的。

//在不设置为系统代理的情况下，surge是能够发现docker中的前置代理的，但是设置系统代理后，估计是docker的网络受到影响（docker网络来自宿主机），无法正常工作。因此surge的前置代理sock也就相应失败，这有点搬起石头砸自己的脚的意思。这不是surge的问题，类似软件必定也是。这种上网方式意味着只有软件本身自带代理设置才能使用，系统或全局是矛盾的。
结论：使用docker中网络上网只适用于浏览器等带代理设置的应用。



##制作Image

Dockfile的优化
原来如下：

```dockerfile
FROM ubuntu:latest as builder

RUN apt-get update
RUN apt-get install curl -y
RUN curl -L -o /tmp/go.sh https://install.direct/go.sh
RUN chmod +x /tmp/go.sh
RUN /tmp/go.sh

FROM alpine:latest

LABEL maintainer "Darian Raymond <admin@v2ray.com>"

COPY --from=builder /usr/bin/v2ray/v2ray /usr/bin/v2ray/
COPY --from=builder /usr/bin/v2ray/v2ctl /usr/bin/v2ray/
COPY --from=builder /usr/bin/v2ray/geoip.dat /usr/bin/v2ray/
COPY --from=builder /usr/bin/v2ray/geosite.dat /usr/bin/v2ray/
COPY config.json /etc/v2ray/config.json

RUN set -ex && \
    apk --no-cache add ca-certificates && \
    mkdir /var/log/v2ray/ &&\
    chmod +x /usr/bin/v2ray/v2ctl && \
    chmod +x /usr/bin/v2ray/v2ray

ENV PATH /usr/bin/v2ray:$PATH

CMD ["v2ray", "-config=/etc/v2ray/config.json"]


优化一下：
FROM ubuntu:latest as builder

RUN buildDeps='curl unzip' \
    && apt-get update \
    && apt-get install -y $Misplaced &buildDeps \
    && curl -L -o /tmp/go.sh https://install.direct/go.sh \
    && chmod +x /tmp/go.sh \
    && /tmp/go.sh \
    && rm -rf /tmp/*
    && rm -rf /var/lib/apt/lists/* \
    && apt-get purge -y --auto-remove $buildDeps

FROM alpine:latest

LABEL maintainer "Darian Raymond <admin@v2ray.com>"

COPY --from=builder /usr/bin/v2ray/v2ray /usr/bin/v2ray/v2ctl /usr/bin/v2ray/geoip.dat /usr/bin/v2ray/geosite.dat /usr/bin/v2ray/
COPY config.json /etc/v2ray/config.json

RUN set -ex \
    && apk --no-cache add ca-certificates \
    && mkdir /var/log/v2ray/ \
    && chmod +x /usr/bin/v2ray/v2ctl \
    && chmod +x /usr/bin/v2ray/v2ray

ENV PATH /usr/bin/v2ray:$PATH
EXPOSE 1080
CMD ["v2ray", "-config=/etc/v2ray/config.json"]
```


这里简单的优化就是串联RUN，清除下载的垃圾（用不到了）。\是因为命令过长转义到下一下用的。



上传镜像值hub仓库。
`docker push vizhsrc/v2:latest`
可能你的镜像没有按上面的格式命名(比如我的直接叫v2)，所以命令没成功，上传的镜像不是你的dockerhub和镜像名：Docker ID/仓库名，就先用：docker tag 镜像ID Docker ID/仓库名:新的标签名(tag)

`sudo docker tag bd213262aa2c vizshrc/v2:latest`



`nginx docker run --name nnginx5 -p 80:80 -v /Volumes/TimeMachine/Docker/nginx:/var/www/html:ro -v /Volumes/TimeMachine/Docker/nginx/nginx.conf:/etc/nginx/nginx.conf:ro -d nnginx`
使用nginx成功。

学习时错误的认识「

~~这才是nginx1.17.5的正确打开方式,它的html目录是/etc/nginx/html~~

~~docker run --name v2nginx -p 80:80 -v /Volumes/TimeMachine/Docker/nginx/html:/etc/nginx/html:ro -v /Volumes/TimeMachine/Docker/nginx/nginx.conf:/etc/nginx/nginx.conf:ro -d vizshrc/v2nginx~~

- 错误--挂载目录文件不一定需要挂载的具体的某个文件，如果每个这样也太麻烦了。

docker run --name v2nginx -p 443:443 -v /var/www/html:/etc/nginx/html:ro -v /etc/nginx/nginx.conf:/etc/nginx/nginx.conf:ro -v /etc/nginx/conf.d:/etc/nginx/conf:ro -d vizshrc/v2nginx

- 错误--挂载不正确的目录会使服务起不来

docker run --name v2nginx -p 80:80 -v /var/www/html:/var/www/html:ro -v /etc/nginx/nginx.conf:/etc/nginx/nginx.conf:ro -v /etc/nginx/conf.d/80.conf:/etc/nginx/conf.d/80.conf:ro -v /root/.acme.sh/feeleg.com_ecc/feeleg.com.cer:/root/.acme.sh/feeleg.com_ecc/feeleg.com.cer:ro -v /root/.acme.sh/feeleg.com_ecc/feeleg.com.key:/root/.acme.sh/feeleg.com_ecc/feeleg.com.key:ro -d vizshrc/v2nginx

- 错误--在调试服务时强烈要求不要加-d,看不到启动日志，终端输出什么，服务没有正确配置，就是瞎折腾，浪费时间。
  」

*成功示范：*
`docker run --name nginx -p 80:80 -p 443:443 -v /etc/nginx/conf.d:/etc/nginx/conf.d:ro -v /var/www:/var/www:ro -v /root/.acme.sh:/root/.acme.sh:ro --net v2-net nginx`

**调试时不要加-d,这样可以看到nginx的消息反馈。同时ctrl+c会停止容器。也省你开了后台要去stop**





- 提示：挂载是一次性的，即容器也是一次成型的。如果被挂载的宿主机目录下文件消失，但容器已经在运行中

  ，他们相应的启动的配置文件当下不会丢失，因为服务已经启动。





