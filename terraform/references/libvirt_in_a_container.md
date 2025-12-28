# libvirt and qemu Inside a Podman Container

Creating and starting a VM from inside a container is really nice if for example you want to automatically test if you OS installs correctly inside a CI.

This example container image uses `systemd` inside `podman` to make this possible. It's based on the following tutorial in the file: `how_to_run_systemd_in_a_container.md`

Sadly this only works for `podman` and not for `docker` since `podman` auto-mounts all required paths if you set the container `CMD` to `/sbin/init`.

For this create the following two files:
```bash
.
├── Dockerfile
└── root-autologin.service
```

## Dockerfile

```dockerfile
FROM debian:latest

# Install dependencies
RUN apt update -y && \
    apt install -y libvirt-clients qemu-system-x86 libvirt-daemon libvirt-daemon-system

# Enable the required services
RUN systemctl enable libvirtd.service && \
    systemctl enable virtlockd.service && \
    systemctl enable libvirtd.socket

# Change qemu to run as root
RUN printf 'user = "root"\ngroup = "root"\nremember_owner = 0\n' | tee -a /etc/libvirt/qemu.conf 

# Enable automatic login as root once systemd is started
COPY root-autologin.service /etc/systemd/system/root-autologin.service
RUN systemctl enable root-autologin.service

# Start systemd
CMD [ "/sbin/init" ]

USER root
```

## root-autologin.service

```systemd
[Unit]
Description=Automatic Root Login

[Service]
ExecStart=/bin/bash
Restart=no
StandardInput=tty
StandardOutput=tty
TTYPath=/dev/console
TTYReset=yes
TTYVHangup=yes
User=root
WorkingDirectory=/root

[Install]
WantedBy=multi-user.target
```

To build the image:

```bash
podman build . -t libvirt_test:latest
```

Then run the container via:

```bash
podman run -it --rm -v /dev/kvm:/dev/kvm localhost/libvirt_test:latest
```

This will boot you directly into a `systemd` enabled/booted podman container. There you can now directly run commands via bash.

Now you are able to happily use quemu inside a container. Enjoy 🎉!

To kill the container again:
```bash
$ podman ps
CONTAINER ID  IMAGE                          COMMAND     CREATED             STATUS             PORTS       NAMES
99085aaa264b  localhost/libvirt_test:latest  /sbin/init  About a minute ago  Up About a minute              distracted_liskov
$ podman kill 99085aaa264b
99085aaa264b
```

Or use `podman kill -a` to kill all.
