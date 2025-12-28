## Podman rootless in Podman rootless, the Debian way

Samuel FORESTIER — 17 September 2023 (last edited on 22 October 2024)

### Introduction

Podman is the new _de facto_ state-of-the-art to run containers on Linux. It comes by design with a very interesting feature : rootless container. In this mode, the container runtime itself runs without privileges. This means exploiting the container runtime could at most grant the attacker the permissions of the running user (kernel own attack surface is out-of-scope here).

Historically, sysadmins and CI/CD developers found themselves in situations where they have to run container in container (see Docker-in-Docker, a.k.a. _DinD_), or other things also dealing with cgroups/seccomp/namespacing running in a container (e.g. [systemd in unprivileged LXC](https://discuss.linuxcontainers.org/t/what-does-security-nesting-true/7156)). We call this “nesting”, and this may introduce some security benefits (as always depending on your threat model).

Nesting Podman in “containers” is supported and [actually](https://www.redhat.com/sysadmin/podman-inside-container) [documented](https://www.redhat.com/sysadmin/podman-inside-kubernetes), and the _combinational_ leads to these situations :

1.  Rootful in rootful (pretty bad from a security point of view)
    
2.  Rootless in rootful (already better !)
    
3.  Rootful in rootless (pretty handy, but consider your container compromised if the application runs as root and has flaws)
    
4.  Rootless in rootless (ideal from a security point of view !)
    

There is a hiccup between (at least) `4` and Debian image, and that’s why we’ll talk about here.

> In below commands, you’ll see I map `/dev/fuse` device in containers to provide OverlayFS support in unprivileged user namespaces for [Linux < 5.11](https://github.com/torvalds/linux/commit/459c7c565ac36ba09ffbf24231147f408fde4203).

### Podman rootless in Podman rootless

Podman is very well integrated in the Red Hat ecosystem ([mainly with systemd](https://www.redhat.com/sysadmin/improved-systemd-podman)), and the [official Podman container image](https://github.com/containers/podman/blob/main/contrib/podmanimage/stable/Containerfile) is built upon Fedora.

On a rather “recent” GNU/Linux distribution, you can safely run as a regular user :

```bash
podman run -q -it --rm \
    --user podman \
    --device /dev/fuse \
    quay.io/podman/stable:latest \
        podman run -q -it --rm \
            docker.io/library/alpine:latest \
            sh
/ # id
uid=0(root) gid=0(root) groups=1(bin),2(daemon),3(sys),4(adm),6(disk),10(wheel),11(floppy),20(dialout),26(tape),27(video),0(root)
```

This command pulls [the official Podman container image](https://quay.io/repository/podman/stable) and runs, as a regular user too (named `podman` in the first container), another Podman runtime which pulls the official Alpine image and spawns a shell in it.

If we focus on user namespaces, it gives :

*   the first `podman` runs as uid=1000 (host machine user session)
    
*   the second `podman` (in the first container) runs as uid=1000 (but shifted by 100000, default value defined in `/etc/subuid` on Debian)
    
*   eventually, `sh` runs as uid=0 (shifted by 101001, where 100000 comes from parent user namespace and 1001 from `/etc/subuid` packaged in `quay.io/podman/stable` image)
    

### Podman in Debian

[Podman is packaged in Debian](https://packages.debian.org/stable/podman) since Bullseye (11). A simple `apt install podman` (which pulls a lot of recommended dependencies, I’d confess) and you’re all set.

Since Debian 12 (this year !), the [specific-but-deprecated](https://www.debian.org/releases/bullseye/amd64/release-notes/ch-information#linux-user-namespaces) `kernel.unprivileged_userns_clone` sysctl parameter is even [enabled by default](https://salsa.debian.org/kernel-team/linux/-/commit/a381917851e762684ebe28e04c5ae0d8be7f42c7) so you don’t have to tweak your system anymore.

Unfortunately, if we attempt to build a Debian-based image to run “rootless in rootless” with such a `Containerfile` :

```dockerfile
FROM debian:bookworm

RUN apt-get update && \
    apt-get upgrade -y && \
    apt-get install -y --no-install-recommends podman fuse-overlayfs slirp4netns uidmap

RUN useradd podman -s /bin/bash && \
    echo "podman:1001:64535" > /etc/subuid && \
    echo "podman:1001:64535" > /etc/subgid

ARG _REPO_URL="https://raw.githubusercontent.com/containers/image_build/refs/heads/main/podman"
ADD $_REPO_URL/containers.conf /etc/containers/containers.conf
ADD $_REPO_URL/podman-containers.conf /home/podman/.config/containers/containers.conf

RUN mkdir -p /home/podman/.local/share/containers && \
    chown podman:podman -R /home/podman && \
    chmod 0644 /etc/containers/containers.conf

VOLUME /home/podman/.local/share/containers

ENV _CONTAINERS_USERNS_CONFIGURED=""

USER podman
WORKDIR /home/podman
```

… it hard fails with :

```bash
podman image build -q -t debian:podman -f Containerfile . && \
    podman run -q -it --rm \
    --device /dev/fuse \
    debian:podman \
        podman unshare bash
98ea1c8c9e32cff5c3dabc4925f55a87cfad77e32d5778785a4f025215124fab
ERRO[0000] running `/usr/bin/newuidmap 12 0 1000 1 1 1001 64535`: newuidmap: write to uid_map failed: Operation not permitted 
Error: cannot set up namespace using "/usr/bin/newuidmap": exit status 1
```

[@jam49](https://github.com/jam49) initially [experienced this error](https://github.com/containers/podman/issues/19906) while trying to run Podman rootless in [Jenkins official Docker image](https://registry.hub.docker.com/r/jenkins/jenkins), which is Debian-based.  
Granting `CAP_SYS_ADMIN` to parent user namespace (hence the first container) actually “fixes” this issue, but this is **highly discouraged** due to [the ~bloated~ range of system operations that it permits](https://book.hacktricks.xyz/linux-hardening/privilege-escalation/linux-capabilities#text-cap_sys_admin), which can easily leads to `root` privileges. Also, unless explicitly dropped, it will be inherited in child user namespaces as well (including the one running your application or service !).

So, why does this work flawlessly on Fedora, and not against Debian ? Let’s dive in user namespaces and capabilities magic world ![:smirk:](Podman%20rootless%20in%20Podman%20rootless,%20the%20Debian%20way%20_%20Samuel%20Forestier_files/1f60f.png ":smirk:")

### From `newuidmap`, to user namespaces and capabilities

`newuidmap` (respectively `newgidmap`) is a _privileged_ program maintained in `shadow-utils` project (see [upstream tree](https://github.com/shadow-maint/shadow), or [`shadow` on Debian](https://salsa.debian.org/debian/shadow/)) which allows unprivileged users to safely map their UID (GID) to parent user namespace, based on ids range defined in `/etc/subuid` (`/etc/subgid`) file.

Since Linux >= 3.9, [modifying namespace id mapping requires `CAP_SYS_ADMIN`](https://github.com/torvalds/linux/commit/41c21e351e79004dbb4efa4bc14a53a7e0af38c5#diff-5ed7c9c3a2bfc22c99debf409d123ff561727de5cf584817b0724df49aa628bdR593). As this capability is usually not granted in container contexts, `shadow-utils` maintainers [switched to file capabilities](https://github.com/shadow-maint/shadow/pull/136) (in a backward-compatible way for setuid setups (see [!132](https://github.com/shadow-maint/shadow/pull/132), fixed-up by [!138](https://github.com/shadow-maint/shadow/pull/138)).

Going through file capabilities is a good way to obtain them even if they are missing from your “Effective set” (they still need to be in your “Permitted set” though, see [this awesome diagram](https://blog.ploetzli.ch/wp-content/uploads/2014/12/capabilities.png), or even next section for a visual experience).

Debian (still) [installs uidmap binaries with setuid bit](https://salsa.debian.org/debian/shadow/-/blob/05a41bc4d536a1c379ec6d21323b51e29c5f9a62/debian/rules#L59-L61), whereas the packaged version fully-supports file capabilities ([\>= 4.7](https://github.com/shadow-maint/shadow/releases/tag/4.7)), since Bullseye (11).  
Theoretically, this shouldn’t be an issue as gaining `root` privileges through setuid bit implies the full set of capabilities by default.  
So, would `uidmap` be [compiled without capability support, and thus failing to retain `CAP_SETUID` (`CAP_SETGID`)](https://github.com/shadow-maint/shadow/blob/5178f8c5afb612f6ddf5363823547e080e7f546b/lib/idmapping.c#L152-L193) ? ![:thinking:](Podman%20rootless%20in%20Podman%20rootless,%20the%20Debian%20way%20_%20Samuel%20Forestier_files/1f914.png ":thinking:")

We can see in Debian `shadow` sources that :

*   [`config.h.in` undefines `HAVE_SYS_CAPABILITY_H`](https://salsa.debian.org/debian/shadow/-/blob/05a41bc4d536a1c379ec6d21323b51e29c5f9a62/config.h.in#L346-347) ;
    
*   [`configure` script checks for `sys/capability.h`](https://salsa.debian.org/debian/shadow/-/blob/05a41bc4d536a1c379ec6d21323b51e29c5f9a62/configure#L14470-L14475).
    

But what do build logs tell ?

```bash
apt install -y --no-install-recommends devscripts wget

# Download last `shadow` (packaging `uidmap` binaries) build logs
getbuildlog shadow "last" amd64

grep 'sys/capability.h' shadow_*_amd64.log 
checking for sys/capability.h... no
```

That’s it ! Due to Debian `shadow` compilation environment **and** packaging, `uidmap` binaries lack of both capabilities upstream patches.

### TL; DR : The workaround

As stated [here](https://github.com/containers/podman/discussions/19931#discussioncomment-6971261), dropping setuid bit and granting `CAP_SETUID` (`CAP_SETGID`) as file capability in our previous Debian-based image using `setcap` (`libcap2-bin` package on Debian) :

```diff
 FROM debian:bookworm
 
 RUN apt-get update && \
     apt-get upgrade -y && \
     apt-get install -y --no-install-recommends podman fuse-overlayfs slirp4netns uidmap
 
 RUN useradd podman -s /bin/bash && \
     echo "podman:1001:64535" > /etc/subuid && \
     echo "podman:1001:64535" > /etc/subgid
 
 ARG _REPO_URL="https://raw.githubusercontent.com/containers/image_build/refs/heads/main/podman"
 ADD $_REPO_URL/containers.conf /etc/containers/containers.conf
 ADD $_REPO_URL/podman-containers.conf /home/podman/.config/containers/containers.conf
 
 RUN mkdir -p /home/podman/.local/share/containers && \
     chown podman:podman -R /home/podman && \
     chmod 0644 /etc/containers/containers.conf
 
 VOLUME /home/podman/.local/share/containers
 
+ # Replace setuid bits by proper file capabilities for uidmap binaries.
+ # See <https://github.com/containers/podman/discussions/19931>.
+ RUN apt-get install -y libcap2-bin && \
+     chmod 0755 /usr/bin/newuidmap /usr/bin/newgidmap && \
+     setcap cap_setuid=ep /usr/bin/newuidmap && \
+     setcap cap_setgid=ep /usr/bin/newgidmap && \
+     apt-get autoremove --purge -y libcap2-bin
+ 
 ENV _CONTAINERS_USERNS_CONFIGURED=""
 
 USER podman
 WORKDIR /home/podman
```

… elegantly workarounds this issue :

```bash
podman image build -q -t debian:podman -f Containerfile . && \
    podman run -q -it --rm \
    --device /dev/fuse \
    debian:podman \
        podman unshare bash
6b0661ddedbf13459493720f992c171d912d33bfd79a48a0d162d3eb0335cc99
root@bbb7d3d08f5a:~# id
uid=0(root) gid=0(root) groups=0(root)
```

### But what if `CAP_SETUID` (`CAP_SETGID`) is explicitly forbidden in my context ?

Well, as you can imagine, it breaks again :

```bash
podman image build -q -t debian:podman -f Containerfile . && \
    podman run -q -it --rm \
    --device /dev/fuse \
    --cap-drop setuid,setgid \
    debian:podman \
        podman unshare bash
6b0661ddedbf13459493720f992c171d912d33bfd79a48a0d162d3eb0335cc99
ERRO[0000] running `/usr/bin/newuidmap 9 0 1000 1 1 1001 64535`:  
Error: cannot set up namespace using "/usr/bin/newuidmap": fork/exec /usr/bin/newuidmap: operation not permitted
```

Although, you’ll notice the error is slightly different : kernel prevents binary execution, instead of subsequent `/proc/self/uid_map` write operation as observed before.

### (bonus) Harden your “last level of nesting”

If your “last level of nesting” is not supposed to re-gain privileges, you can safely set the [“No New Privileges” flag](https://www.kernel.org/doc/html/latest/userspace-api/no_new_privs.html) through a Podman security option :

```bash
podman run -q -it --rm \
    --user podman \
    --device /dev/fuse \
    --security-opt=no-new-privileges \
    quay.io/podman/stable \
        podman run -q -it --rm \
            alpine:latest \
            sh
ERRO[0000] running `/usr/bin/newuidmap 9 0 1000 1 1 1 999 1000 1001 64535`: newuidmap: write to uid_map failed: Operation not permitted 
Error: cannot set up namespace using "/usr/bin/newuidmap": exit status 1
```

Here we can note that the flag actually breaks our first post example, as expected (gaining privileges from `newuidmap` program is denied by kernel).

The status of this flag can be retrieved using `capsh` :

```bash
podman run -q -it --rm \
    --user podman \
    --device /dev/fuse \
    --security-opt=no-new-privileges \
    quay.io/podman/stable \
        bash
[podman@5936edfb845d /]$ /sbin/capsh --print | grep no-new-privs
Securebits: 00/0x0/1'b0 (no-new-privs=1)
```

… or even directly through `/proc` :

```bash
grep NoNewPrivs /proc/self/status
NoNewPrivs:	1
```

### Conclusion

This has been a “funny” bug to investigate !

I’ve run a quick search on the Web and it doesn’t look like Debian plans to switch to file capabilities for uidmap binaries (yet), so it’s very likely that the shim above will be around for some time.

All rights reserved © — Samuel FORESTIER — 2013 - 2025
