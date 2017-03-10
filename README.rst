This playbook sets up an `Atomic Registry`_ on a CentOS 7 system. I intend to
use this to manage the deployment at registry.ceph.com.

Getting started
===============

To run the playbook:

1. Set up ``~/.vault_pass.txt``

2. Set up your FQDN in ``vars`` dir, eg ``vars/registry.ceph.com.yml``, with
   ``github_client_id`` and ``github_client_secret``. Encrypt this::

    ansible-vault --vault-password-file=~/.vault_pass.txt encrypt vars/registry.ceph.com.yml

3. Run ``make dev`` to run ``ansible-playbook`` with the proper arguments for
   your dev environment, or simply ``make`` for production.


Development
===========

I use these steps to set up a dev VM environment before changing things in
production.

1. Start with the basic CentOS 7 cloud image.

2. Remove cloud-init (so it does not mess with the hostname)::

    rpm -e cloud-init

3. Set the VM's FQDN and IP in /etc/hosts::

    hostnamectl set-hostname kdreyer-registry.ceph.redhat.com

    ifconfig | awk '/inet /{print substr($2,1)}' | head -1

4. Ensure SELinux is set to enforcing (``sestatus``)::

    sed -i 's/SELINUX=disabled/SELINUX=enforcing/g' /etc/selinux/config

5. Update to the very latest packages. In particular firewalld has had some
   bugs. (See https://access.redhat.com/discussions/1455033 and
   https://github.com/t-woerner/firewalld/issues/195)

6. Reboot

7. Ensure Ansible recognizes the hostname properly::

    ansible -i inventory -m setup kdreyer-registry | grep ansible_fqdn

If this is not working, you may have to add the IP address to /etc/hosts. For
example::

    158.69.79.139 registry.ceph.com

(At this point it would be a good idea to snapshot your VM before proceeding
further, to save time in case you want to wipe it and start over.)

Now you can run ``ansible-playbook``. See "Getting Started" section above.

Things not yet in Ansible
=========================

To make oauth signin work for the registry console interface (cockpit), I
needed to update the cockpit-oauth-client settings in OpenShift, adding the
non-port-9090 interface.

1. Shell into the master container::

    docker exec -it atomic-registry-master bash

2. Show the current settings for the cockpit oauth::

    oc get oauthclient cockpit-oauth-client -o yaml

This shows the ``redirectURIs`` was still using the old :9090 address.

3. Edit the file to remove the port number::

    oc edit oauthclient cockpit-oauth-client -o yaml

At this point, GitHub oauth should succeed.

Pruning images
==============

Pruning is an OpenShift administrator operation, so it uses the ``oadm`` tool.

The oadm tool gets its configuration from the $KUBECONFIG environment variable.
With the atomic-registry-master container, this is
``/etc/atomic-registry/master/admin.kubeconfig``.

Pruning is not allowed / not easily supported by the system:admin account yet:
https://github.com/openshift/origin/issues/7564, so I added my personal account
to the list of administrators. In prod we should probably do this for a jenkins
system account.

On the server::

    sudo docker exec -it atomic-registry-master bash

List all users (see my GitHub account in the list)::

    oc get user

Give "ktdreyer" full admin rights to run "prune images"::

    oadm policy add-cluster-role-to-user cluster-admin ktdreyer

... at this point my workstation's ktdreyer token expired and I had to log in
again with ``oc login``. Once I did that, I could prune all images with 
``oadm prune images``. On my workstation::

    oc login --token asdffdsaasdffdsaasdffdsaasdffdsaasdffdsaasd kdreyer-registry.ceph.redhat.com
    oadm prune images --keep-younger-than=1m


Learning More
=============

The `Atomic Registry`_ documentation is very helpful. It walks through setting
up a standalone registry that runs on three ports:

* Port 8443, Kubernetes master service
* Port 5000, Docker registry service
* Port 9090, Registry "Console" UI (Cockpit)

Following the basic instructions will lead to a VM with the service running on
all three ports. I've fronted this with a reverse-proxy so that all three
services easily use the same Lets Encrypt HTTPS certificate. It also means
users don't have to remember obscure port numbers (everything is proxied
through port 443).


Troubleshooting
===============

"Apache is returning HTTP 503 service unavailable"
--------------------------------------------------

The reverse proxy cannot contact one of the web services. Ensure they are
running::

    systemctl status atomic-registry\*

You should see ``atomic-registry``, ``atomic-registry-master``,
``atomic-registry-console`` there. Use ``systemctl status -l <servicename>``
and ``journalctl -xe`` to see more information in the logs.


"I need to get a console for the containerized services"
--------------------------------------------------------

Use ``docker exec -it`` to open a terminal in the container's context::

    docker exec -it atomic-registry-master bash

From here you can ``ping``, ``ps``, etc.

"I can't connect to the internet from within the container"
-----------------------------------------------------------

Ensure firewalld shows eth0 as part of the "external" zone::

    firewall-cmd --list-all --zone=external

"What's the HTTP registry token?"
---------------------------------

Use ``oc get``::

    docker exec atomic-registry-master oc get secret registry-token-79mqk --template '{{ .data.token }}'

Check out the Atomic Registry's ``setup.sh`` script for more information.

.. _Atomic Registry: http://docs.projectatomic.io/registry/latest/registry_quickstart/administrators/
