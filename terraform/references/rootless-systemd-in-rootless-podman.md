# Rootless Systemd in Rootless Podman

February 14, 2023

·

Chris Evich

by Chris Evich

Let’s say you’re test-driving a service that needs to interact with a rootless Podman socket. The service is potentially destructive to containers, volumes, or images, so you don’t want to risk your host installation. How can you do this all from inside a rootless container? The answer is somewhat complicated, but in this article, I’ll try to walk you through each of the challenges step-by-step.

[Nested Podman inside Podman isn’t a new thing](https://www.redhat.com/sysadmin/podman-inside-container). On the host side, we’ve got to run `--privileged` and provide the container storage from the host (`-v container-storage:/home/<name>/.local/share/containers:Z`).  This is necessary to avoid an ugly overlay-in-overlay situation. In any case, this is fairly simple and unsurprising as the following **Containerfile** demonstrates:

FROM registry.fedoraproject.org/fedora:latest
RUN dnf upgrade -y && \\
    dnf install -y podman && \\
    rpm --setcaps shadow-utils 2>/dev/null && \\
    dnf clean all
RUN groupadd -g 1000 fred && \\
    useradd -u 1000 -g 1000 fred && \\
    echo -e "fred:1:999\\nfred:1001:64535" | \\
        tee /etc/subuid > /etc/subgid
VOLUME /home/fred/.local/share/containers

The base-image package upgrade and installation shouldn’t be surprising. The **`--setcaps`** on **shadow-utils** is a fedora-specific workaround for a long-standing bug. Next, we add our user and set up the nested subuid/subgid mapping.  This is needed so nested containers don’t grab IDs that overlap with the namespaced **`UID 0`** (the root user) and **`UID 1000`** (Fred). Were that to happen, users in the nested-containers could have unintended access to files/directories of the outer container. So this `subuid/gid` setup is important.

Since Fred is our only nested user and group namespace, we can simply clobber the default contents in the `/etc/sub{uid,gid}` files. If there were other users with known IDs, they should similarly be excluded from Fred’s namespace ranges to avoid unintentional clashes.  Finally, the image requests a volume from the host to provide the above-mentioned container storage.

Running a nested container inside this container image is straightforward and unsurprising:

$ podman build -t piptest .
...cut...
$ podman run -it --rm --privileged --user fred --hostname outer piptest
\[fred@outer /\]$ podman run -it --rm --privileged --hostname inner fedora:latest
...cut...
Writing manifest to image destination
Storing signatures
\[root@inner /\]# echo "no magic here"
no magic here
\[root@inner /\]# exit
exit
\[fred@outer /\]$ exit
exit

Next comes the tricky part. Since Podman doesn’t have a daemon, a running Podman process is needed to service API socket requests. While we could run **`podman system service -t0`** as the container’s command, this won’t allow us to use the socket at the same time from an app. With containers, any time you’re contemplating needing multiple high-level processes, unless they’re entirely trivial (which these aren’t), you’ll want an init-system like Systemd.

[Running Systemd inside a container](https://developers.redhat.com/blog/2019/04/24/how-to-run-systemd-in-a-container#) complicates things – Primarily due to the additional services and their non-trivial configuration.  However; it’s necessary in this use-case because we want the container to do multiple things. Specifically, Systemd is needed to properly handle a (potentially) large number of Podman child-process popping in and out of existence, along with signal-handling up/down their sub-trees. I haven’t even mentioned the app which will be using the Podman socket, it will inevitably need systemd handling as well.

In other words, without a **PID 1** process manager, our container will quickly end up an uncoordinated miss-mash, constantly testing its own imminent collapse.

![Leaning tower of Jenga](Rootless%20Systemd%20in%20Rootless%20Podman_files/unnamed.jpg)

_Leaning tower of Jenga_

Back in the `Containerfile`**,** updating the **`dnf install`** line to include **`systemd`** is easy enough. Though some additional magic is needed to coax life into a Podman socket service and keep operations observable when the container starts. Assuming your host is system-based, and has podman installed, the podman systemd files can simply be copied into the container build context, for example:

$ cp /lib/systemd/system/podman.s\* ./

The first thing that needs changing is a minor update to the **`podman.service`** file – so it logs to the console at the warn level (default on Fedora is the **`info`** level):

\[Unit\]
Description=Podman API Service
Requires=podman.socket
After=podman.socket
Documentation=man:podman-system-service(1)
StartLimitIntervalSec=0

\[Service\]
Delegate=true
Type=exec
KillMode=process

Environment=LOGGING="--log-level=_warn_"
ExecStart=/usr/bin/podman $LOGGING system service
_StandardOutput=journal+console
StandardError=inherit_

\[Install\]
WantedBy=default.target

Secondly, let’s have systemd manage the listening **`podman.sock`** file in Fred’s home directory where it’s easier to interact with, and saves a bit of typing:

\[Unit\]
Description=Podman API Socket
Documentation=man:podman-system-service(1)

\[Socket\]
ListenStream=_%h/podman.sock_
SocketMode=0660

\[Install\]
WantedBy=sockets.target

Installing the socket, service, and setting up a systemd-slice for Fred, happens in the **`Containerfile`**, which to this point looks like this:

FROM registry.fedoraproject.org/fedora:latest
RUN dnf upgrade -y && \\
    dnf install -y podman _systemd_ && \\
    rpm --setcaps shadow-utils 2>/dev/null && \\
    dnf clean all
RUN useradd -u 1000 fred && \\
    echo -e "fred:1:999\\npodman:1001:64535" | tee /etc/subuid > /etc/subgid
VOLUME /home/fred/.local/share/containers

_ADD /podman.service /podman.socket /home/fred/.config/systemd/user/
RUN cd /home/fred/.config/systemd/user/ && \\
    mkdir sockets.target.wants && \\
    ln -s ../podman.socket ./sockets.target.wants/ && \\
    mkdir -p /var/lib/systemd/linger && \\
    touch /var/lib/systemd/linger/fred && \\
    chown -R 1000:1000 /home/fred
ENTRYPOINT /sbin/init_

The key to having the user-slice services start with the container, is creating the file **`/var/lib/systemd/linger/fred`** which is the equivalent to running: **`loginctl enable-linger fred`**. However, neither systemd nor dbus are available in a container-image build environment, so the file is simply touched into existence.

  
The final **`Containerfile`** steps fix Fred’s file ownership and indicate that the container should start init (systemd) as **`PID 1`**. However, since the container will now startup as the (namespaced) root user, we need to pre-create the container-storage volume as follows; otherwise, the ownership will be incorrect – undoubtedly generating a ton of _permission-denied_ errors.:

$ podman volume create -o o=uid=1000,gid=1000 freds-containers

Should you want to view or manipulate the contents of that volume, be sure to prefix your commands with **`podman unshare`** to enter your user-namespace.  Otherwise, that’s it, all the technical bits uncovered, and magic unobscured. All that’s left is to start the container and prove the nested, remote, rootless Podman connection is functional:

$ podman build -t piptest .
...cut...
$ podman run -dt --rm --privileged --hostname outer \\
    -v freds-containers:/home/fred/.local/share/containers \\
    --systemd true piptest
0af2a31de3467d0ddb2b540072c0864f7738d5de5745aa5b3596d70f4a5f7a04
$ podman exec -itl bash
\[root@outer /\]# ls -la /home/fred/podman.sock
srw-rw----. 1 fred fred 0 Feb  9 17:06 /home/fred/podman.sock
\[root@outer /\]# export CONTAINER\_HOST=unix:///home/fred/podman.sock
\[root@outer /\]# podman --remote info --format={{.Store.GraphRoot}}
/home/fred/.local/share/containers/storage
\[root@outer /\]# podman --remote run -it --rm --hostname inner fedora:latest
...cut...
Writing manifest to image destination
Storing signatures
\[root@inner /\]# echo "Hello from $HOSTNAME"
Hello from inner
\[root@inner /\]# exit
exit
\[fred@outer /\]$ exit
exit
$ podman stop -l
0af2a31de3467d0ddb2b540072c0864f7738d5de5745aa5b3596d70f4a5f7a04

Here you can see the container is built and then run in **`--privileged`** mode (required for nested rootless containers) with the pre-created container-storage volume. Then exec’d into as the namespaced root user, where we connect to Fred’s Podman socket and print out the container storage location. Though the use of root is merely a convenience, you can connect to the socket as any configured/namespaced user with appropriate permissions. As demonstrated above, the location and permissions are configurable in the **`podman.socket`** file.

![Robotic Jenga Stacking](Rootless%20Systemd%20in%20Rootless%20Podman_files/unnamed.gif)

_Robotic Jenga Stacking_

At this point, development of any service which connects to a Podman socket is possible and will be isolated from the host’s Podman setup.  Adding more users, systemd-slices, and making them linger should be fairly trivial.  Though you’ll need to remember to exclude other namespaced **`UID/GID`** from the podman-user’s range within the nested **`/etc/sub{uid,gid}`** to prevent clashes.

Despite needing to run the top-level container in **`--privileged`** mode, the containerized systemd-slices provide some additional level of isolation.  This setup is certainly not as secure as without systemd or the additional privileges.  However; the privileged option isn’t nearly as bad as if the container were run as root.  In this case, the extra enabled capabilities are of limited effect, due to the rootless user namespace.  So it’s a perfectly fine arrangement for testing, development, or non-critical purposes.

Overall these containers succeed in isolating their software, dependencies, and runtime environments from the host operating system. Further, since they’re already systemd-enabled, it should be easy to add additional apps and service files – directing them toward the nested Podman socket location. However, since this article is already a bit long, these are all left as exercises for the reader.

podman run --rm \
  --uidmap 0:100000:1000 \
  --uidmap 1000:1000:1 \
  --uidmap 1001:101000:64536 \ 
  --gidmap 0:100000:1000 \
  --gidmap 1000:1000:1 \
  --gidmap 1001:101000:64536 \
  alpine echo ok
  
podman run --rm --uidmap 0:100000:1000 --uidmap 1000:1000:1 --uidmap 1001:101000:64536 --gidmap 0:100000:1000 --gidmap 1000:1000:1 --gidmap 1001:101000:64536 alpine echo ok
