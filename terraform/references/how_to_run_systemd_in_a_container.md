# How to run systemd in a container {#developer-materials .article-info-title}

I have been talking about [systemd](https://github.com/systemd/systemd)
in a container for a long time. Way back in 2014, I wrote "[Running
systemd within a Docker
Container](https://developers.redhat.com/blog/2014/05/05/running-systemd-within-docker-container/)."
And, a couple of years later, I wrote another article, "[Running systemd
in a non-privileged
container](https://developers.redhat.com/blog/2016/09/13/running-systemd-in-a-non-privileged-container/),"
explaining how things hadn't gotten much better. In that article, I
stated, "Sadly, two years later if you google Docker systemd, this is
still the article people see---it's time for an update." I also linked
to a talk about [how upstream Docker and upstream systemd would not
compromise.](https://lwn.net/Articles/676831/) In this article, I\'ll
look at the progress that\'s been made and how Podman can help.

There are lots of reasons to run systemd inside a system, such as:

1.  **Multiservice containers**---Lots of people want to take existing
    multi-service applications out of VMs and run them inside of
    containers. We would prefer that they break apart these applications
    into microservices, but some people can't or don't have time yet.
     So running them as services launched out of unit files by systemd
    makes sense.
2.  **Systemd unit files**---Most applications that run inside of
    containers are built from code that was run in VMs or on host
    systems. These applications have a unit file that was written for
    the application and understands how to run the application. It can
    be better to launch the service via the supported method, rather
    than to hack up your own init service.
3.  **Systemd is a process manager**---It handles the management of
    services like reaping, restarting, and shutting down better than any
    other tool.

That being said, there are also lots of reasons not to run systemd in
containers. The main one is that systemd/journald controls the output of
containers, whereas tools like [Kubernetes](https://kubernetes.io/) and
[OpenShift](https://www.openshift.com/) expect the containers to log
directly to stdout and stderr. So, if you are going to manage your
containers via Orchestrator like these, then you should think twice
about using systemd-based containers. Additionally, the upstream
community of Docker and Moby were often hostile to the use of systemd in
a container.

[Enter Podman]{#enter_podman .rhd-c-has-toc-target}

## Enter Podman {#enter_podman-h2}

I am happy to say things have gotten better. My team, container
runtimes, at Red Hat decided to build [our own container
engine](https://podman.io/), called
[Podman](https://github.com/containers/libpod). Podman is a container
engine with the same command-line interface (CLI) as Docker. Pretty much
every command you can run from the Docker command line you can execute
with Podman. I often give a talk now about Replacing Docker with Podman,
where the first slide says `alias docker=podman`.

And lots of people had.

With Podman, however, we were not hostile to systemd-based containers.
Systemd is the most prevalent Linux init system on the planet, and not
allowing it to run properly within a container would ignore the way
thousands of users choose to run containers.

Podman understands what systemd needs to do to run in a container. It
requires things like tmpfs mounted at /run and /tmp. It likes to have
the "container" environment turned on, and it expects to be able to
write to its portion of the cgroup directory and to the
/var/log/journald directory.

When Podman starts a container that is running init or systemd as its
initial command, Podman automatically sets up the tmpfs and Cgroups for
systemd to start without a problem. If you want to block the systemd
behavior, you have to run `--systemd=false`. Note that the systemd
behavior only happens when Podman sees the command to be executed is
systemd or init.

Here is the man page description:

> man podman run
>
> ...
>
> \--systemd=true\|false
>
> Run container in systemd mode. The default is true.
>
> If the command you running inside of the container is systemd or init,
> podman will setup tmpfs mount points in the following directories:
>
> /run, /run/lock, /tmp, /sys/fs/cgroup/systemd, /var/lib/journal
>
> It will also set the default stop signal to SIGRTMIN+3.
>
> This allows systemd to run in a confined container without any
> modifications.
>
> Note: On SELinux systems, systemd attempts to write to the cgroup file
> system.  Containers writing to the cgroup file system are denied by
> default. The container_manage_cgroup boolean must be enabled for this
> to be allowed on an SELinux separated system.
>
> setsebool -P container_manage_cgroup true

Now let's look at a Dockerfile for running systemd in a container using
Podman:

    # cat Dockerfile

    FROM fedora

    RUN dnf -y install httpd; dnf clean all; systemctl enable httpd

    EXPOSE 80

    CMD [ "/sbin/init" ]

That's it.

Build the container

    # podman build -t systemd .

Tell SELinux it is ok to allow systemd to manipulate its Cgroups
configuration.

    # setsebool -P container_manage_cgroup true

You will forget to do this; I did while writing this blog. Luckily, you
do this once, and it will be set for the lifetime of the system.

Now just run the container.

    # podman run -ti -p 80:80 systemd

    systemd 239 running in system mode. (+PAM +AUDIT +SELINUX +IMA -APPARMOR +SMACK +SYSVINIT +UTMP +LIBCRYPTSETUP +GCRYPT +GNUTLS +ACL +XZ +LZ4 +SECCOMP +BLKID +ELFUTILS +KMOD +IDN2 -IDN +PCRE2 default-hierarchy=hybrid)

    Detected virtualization container-other.

    Detected architecture x86-64.


    Welcome to Fedora 29 (Container Image)!


    Set hostname to <1b51b684bc99>.

    Failed to install release agent, ignoring: Read-only file system

    File /usr/lib/systemd/system/systemd-journald.service:26 configures an IP firewall (IPAddressDeny=any), but the local system does not support BPF/cgroup based firewalling.

    Proceeding WITHOUT firewalling in effect! (This warning is only shown for the first loaded unit using IP firewalling.)

    [  OK ] Listening on initctl Compatibility Named Pipe.

    [  OK ] Listening on Journal Socket (/dev/log).

    [  OK ] Started Forward Password Requests to Wall Directory Watch.

    [  OK ] Started Dispatch Password Requests to Console Directory Watch.

    [  OK ] Reached target Slices.

    …

    [  OK ] Started The Apache HTTP Server.

And the service is up and running.

    $ curl localhost

    <html xmlns="http://www.w3.org/1999/xhtml" xml:lang="en" lang="en">

    …

    </html>

Note: Don't try this with Docker you still need to jump through hoops to
get a container like this running in the daemon. (You need additional
fields and packages, to make this work seamlessly in Docker, or run in a
\--privileged container. [My previous
article](https://developers.redhat.com/blog/2016/09/13/running-systemd-in-a-non-privileged-container/)
explains this better.)

[Other cool features about Podman and
systemd]{#other_cool_features_about_podman_and_systemd
.rhd-c-has-toc-target}

## Other cool features about Podman and systemd {#other_cool_features_about_podman_and_systemd-h2}

### Podman in systemd unit files works better than Docker

When launching containers at boot, you can simply put Podman commands
into a systemd unit file, and systemd will launch and monitor the
service. Podman is a standard fork and exec model. That means the
container processes are children of the Podman process, so systemd has
an easy time monitoring the processes.

Docker is a client service model and putting the Docker CLI into a unit
file is possible. However, as the Docker client connects to the Docker
daemon, the Docker client becomes just another process handling stdin
and stdout. Systemd has no idea of this relationship between the Docker
client and the container that is running under the Docker daemon and
can\'t monitor the service in this model.

### Systemd socket activation

Podman works correctly when the socket is activated. Because Podman is a
fork/exec model, it can pass the connected socket down to its children
container processes. Docker cannot do this because of the client/server
model.

Podman [varlink](https://varlink.org/), a service that Podman uses for
remote clients to interact with containers, is actually socket
activated. The
[cockpit-podman](https://github.com/cockpit-project/cockpit-podman)
package, written in Node.js, is part of the cockpit project and allows
people to interact with Podman containers via a web interface. The web
daemon running cockpit-podman sends messages to a varlink socket that
systemd is listening on. Systemd then activates the Podman program to
receive the messages and start managing containers. Systemd socket
activation allows us to have no long-running daemon and still be able to
handle a remote API.

We are developing another client for Podman, called *podman-remote*,
which implements the same Podman CLI but calls into varlink to launch
containers. Podman-remote can work over SSH sessions, allowing us to
securely interact with containers on different machines. We eventually
plan on using podman-remote to support MacOS and Windows users as well
as Linux users. This will allow developers on a Mac or Windows box to
launch a Linux VM with Podman varlink running and have the feeling that
containers are running on their local machine.

### SD_NOTIFY

Systemd has the ability to hold up secondary services from starting that
rely on a containerized service starting. Podman can pass down the
SD_NOTIFY Socket to the containerized service, so it can notify systemd
when it is ready to begin servicing requests. Docker again cannot do
this, because of the client/server model.

[Future Work]{#future_work .rhd-c-has-toc-target}

## Future Work {#future_work-h2}

We have plans to add a `podman generate systemd CONTAINERID`, which
would generate a systemd unit file for managing the specified container.
This should work in either root or rootless mode for non-privileged
containers. I have even seen a PR to create a systemd-nspawn
OCI-compliant runtime.

[Conclusion]{#conclusion .rhd-c-has-toc-target}

## Conclusion {#conclusion-h2}

Running systemd in a container is a reasonable thing to do. Finally, we
have a container runtime in Podman that is not hostile to running
systemd fully but easily enables the workload.

*Last updated: February 11, 2024*

