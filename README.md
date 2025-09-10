# nifi-crdb-installation

### Everything described below can be configured and deployed from cloud-init, please find instructions to setup the environment on the [wiki page](https://github.com/longjatdepaul/nifi-crdb-installation/wiki)
  
<hr/>

#### This page provides instructions on setting up a basic NiFi cluster that can be used to demo data integrations with CRDB

## NOTES:
- for NiFi connections into CRDB the postgres driver will be installed on the nodes at /opt/drivers/postgres/postgresql-jdbc.jar

<hr/>

## The Servers

If you don't have a hosted or on-premise cloud solution you can spinup a sample NiFi cluster on your desktop using VMware, VirtualBox or UTM.  For macOS / Apple Silicon I used Multipass with Terraform, which can be installed with
```
# Terraform
brew tap hashicorp/tap
brew install hashicorp/tap/terraform
terraform -version

# Multipass
brew install --cask multipass
multipass version
```

For local development I created three Ubuntu 64-bit VMs with the following configuration:
- **Memory**: 4GB
- **Image**: 24.04
- **Disk Size**: 300GB Dynamically Allocated
- **Processor**: 2 CPUs
- **Network**: Private NAT Network Adapter

For GCP we used three N2 General-purpose 32 vCPU and 64 GB machines.

With SSH enabled you can execute the installation script on a single server and install the components across the cluster.  Otherwise you need to run the script on eacn machine.  You can follow the commands below to enable SSH on each server.
```
$ sudo apt install openssh-client
$ sudo apt install openssh-server
$ sudo sshd -t -f /etc/ssh/sshd_config
$ sudo systemctl restart sshd.service
$ ssh-keygen -t rsa
$ service sshd status
$ sudo ufw allow ssh
$ sudo ufw enable
$ sudo ufw status
```
And then from the installation server you'll want to copy your ssh id to the other nodes in the cluser.
```
$ ssh-copy-id your_username@other_node_1
$ ssh-copy-id your_username@other_node_2
$ ...
```
The script will invoke many SSH commands to configure the cluster which will require many password entries for sudo authorization on each node.  Before running the script you may want to make an additional change to disable password authorization when using SSH public key authentication.  This change should be reversed after the cluser is installed and running.  Simply add the line below to the /etc/sudoers file replacing your_username with the account name you are using to install the NiFi cluster.
```
$ sudo visudo /etc/sudoers
your_username ALL=(ALL) NOPASSWD: ALL
```

<hr/>

## The Disks

NiFi requires separate file locations for their content and provenance repositories.  You can configure these on the same disk where NiFi is installed but it is recommended to place the repositories on separate drives.

You can run a small demo with these repositories on the same disk that NiFi is installed on, but for a proper POC I reccommend attaching separate disks using a single primary partition with one of the following allocations.  For a production installation we would have different recommendations.  We need to attach and partition the drives, then mount them to the appropriate location.

For our local Multipass cluster we attached a single 300GB disk to each VM and simulated the mounts with 6×50G loop files.

| Disk | Mount | Size |
| ------------- | ------------- | ------------- |
| /var/lib/nifi-disks/flowfile-repo.img | /mnt/flowfile-repo | 20GB |
| /var/lib/nifi-disks/cont-repo1.img | /mnt/cont-repo1 | 50GB |
| /var/lib/nifi-disks/cont-repo2.img | /mnt/cont-repo2 | 50GB |
| /var/lib/nifi-disks/cont-repo3.img | /mnt/cont-repo3 | 50GB |
| /var/lib/nifi-disks/prov-repo1.img | /mnt/prov-repo1 | 50GB |
| /var/lib/nifi-disks/prov-repo2.img | /mnt/prov-repo2 | 50GB |


For our GCP cluster we attached six separate disks to each server and used each disk as a single purpose storage device described below

| Disk | Mount | Size |
| ------------- | ------------- | ------------- |
| /dev/sdb | /mnt/flowfile-repo  | 25GB |
| /dev/sdc | /mnt/cont-repo1  | 200GB |
| /dev/sdd | /mnt/cont-repo2  | 200GB |
| /dev/sde | /mnt/cont-repo3  | 200GB |
| /dev/sdf | /mnt/prov-repo1  | 75GB |
| /dev/sdg | /mnt/prov-repo2  | 75GB |

```
$ sudo parted -l
$ sudo wipefs -a /dev/sdb
$ sudo parted /dev/sdb
(parted) mklabel msdos
(parted) unit s
(parted) print free
(parted) mkpart primary 0% 100%
(parted) print
(parted) quit
$ sudo mkfs.ext4 -L flowfile-repo /dev/sdb1
$ sudo mkdir -p /mnt/flowfile-repo
$ sudo blkid /dev/sdb1
# update /etc/fstab
$ sudo mount /dev/sdb1 /mnt/flowfile-repo
$ findmnt /mnt/flowfile-repo
...repeat for each drive
```
     
<hr/>

## The Firewall

In order to run the NiFi / CRDB demo several components will be installed that require specific ports to be opened for communication between nodes in the cluster.  The list of components that will be installed is listed below.

1. Cockroach Binaries and Certificate (no firewall dependencies)
2. Postgres Driver (no firewall dependencies)
3. Java Version 11 (no firewall dependencies)
4. Kafka (port 9092)
5. Zookeeper (ports 2181, 2888 and 3888)
6. NiFi (ports if insecure: 8080, 9998, 9999, 6342 and 4557 - OR - ports if secure: 9443, 10443, 11443, 6342 and 4557)
7. NiFi Toolkit (no firewall dependencies)

These components will use the following ports for client and peer-to-peer network communications.  The only ports that need to be opened for communication outside the cluster are for the NiFi UI http/https endpoints.

| Component | Port | Purpose |
| ------------- | ------------- | ------------- |
| Kafka | 9092  | can be used to demo the ingestion of streaming data into CRDB |
| Zookeeper | 2181 | client connectivity for cluster configuration and management |
|| 2888:3888 | peer to peer communication to broadcast config updates |
| NiFi | 8080:9443 | http(s) web communication endpoints for external connectivity |
|| 9998:10443 | remote input socket port communication |
|| 9997:11443 | cluster node protocol port communication |
|| 6342 | cluster node load balancing port communication |
|| 4557 | internal distributed map cache server communication |

<hr/>

## The Script

If you have SSH enabled between the nodes of your cluster you can execute the script on a single server and it will install, configure and spinup the services on the other nodes.

```
usage: ./scripts/nifi-install.sh [options] node-<id>:<hostname> [node-<id>:<hostname> ...]

Phase 1 (new-cluster, idempotent):
  1) Check SSH to each node (by hostname) and ensure our pubkey is present
  2) apt-get update && full-upgrade (Debian/Ubuntu only)
  3) Install & configure UFW: deny incoming, allow outgoing, allow SSH
  4) Allow intra-cluster traffic between nodes and enable UFW

Options:
  -i <user>              installer account on nodes (default: ubuntu)
  -r registry=<hostname> optional registry host (excluded from peer rules)
  -S                     use secure NiFi ports (TLS) for cluster comms
  -x                     dry-run (print actions, no changes)
  --ssh-timeout <secs>   SSH reachability timeout (default: 8)
  -q                     quiet mode
  --trace                enable trace for detailed log reporting

  for all installations you'll need to provide a 16+ character key for sensitive properties
  $ export SENSITIVE_KEY='******'

  for secure installations you'll also need to provide passwords for the key and trust stores
  $ export KEYSTORE_PASSWD='******'
  $ export TRUSTSTORE_PASSWD='******'

  --insecure-downloads   defaults to false
  --curl-cacert          defaults to 

  --java-version         defaults to 21
  --pgjdbc-version       defaults to 42.7.7
  --zk-version           defaults to 3.9.4
  --kafka-version        defaults to 3.9.1
  --scala-version        defaults to 2.13
  
  --nifi-version         defaults to 2.5.0
  --nifi-toolkit-version defaults to 2.5.0
  --nifi-user            defaults to nifi

  --flowfile-dir PATH    flowfile repo mount, e.g. /mnt/disk1 (single), defaults to /flowfile_repository
  --database-dir PATH    database repo mount, e.g. /mnt/disk2 (single), defaults to /database_repository
  --content-dir PATH     repeatable; content repo mount(s), e.g. /mnt/disk3 /mnt/disk3
  --provenance-dir PATH  repeatable; provenance repo mount(s), e.g. /mnt/disk5 /mnt/disk6

  --nifi-heap             defaults to 3g
  --nifi-log-dir          defaults to /var/log/nifi
  --log-max-size          defaults to 256MB
  --log-max-history       defaults to 14

  if using git with https://... you'll need to export GIT_TOKEN='******' with a fine-grained PAT with repo read/write
  if using git with ssh remote you'll need to unset GIT_TOKEN and allow ssh credentials to authenticate

  --gh-url                no default, if you have a repo then either https://… or git@github.com:…
  --gh-username           no default, use for HTTPS connection but leave blank for if SSH
  --gh-usertext           no default, git identity stored for the nifi user
  --gh-email              no default, git identity stored for the nifi user
  --gh-branch             defaults to registry
  --gh-directory          defaults to nifi-flows
  --gh-remote-name        defaults to origin

Advanced:
  OP=<op> ./scripts/nifi-install.sh ...         set operation via env (default: new-cluster)
                         planned ops: add-node, join-cluster, remove-node,
                         replace-node, rotate-certs, upgrade, migrate

Notes:
  • Arguments accept legacy form node-1:host=anything — value is ignored; only hostnames are used.
  • No IPs required as inputs; UFW resolves peers to IPs on each node during rule creation.
  • Debian/Ubuntu only (uses apt-get with DEBIAN_FRONTEND=noninteractive).
```
The default values should work fine, however, you will need to provide the list of nodes that are allocated for the cluster, the location of your CRDB certificate and the mount points that you want created for your NiFi repositories.  If your cert is not available over an http endpoint you can manually copy it into a local directory on each server.  Also, assuming a GCP N2 General-purpose 32 vCPU and 64 GB machine, you'll want to change the memory allocation to 32g.  After executing the script you'll want to check that services are up and running.
```
export SENSITIVE_KEY=tHiSiSnTaSaFeKeY
export KEYSTORE_PASSWD=changeit
export TRUSTSTORE_PASSWD=changeit
export GIT_TOKEN='******'
./scripts/nifi-install.sh -S -r registry=nifi-registry \
                          --nifi-heap 32g \
                          --insecure-downloads \
                          --gh-url https://github.com/<gh_username>/<gh_repo>.git \
                          --gh-username <gh_username> \
                          --gh-usertext <gh_account_name> \
                          --gh-email <gh_account_email> \
                          --flowfile-dir /mnt/flowfile-repo \
                          --content-dir /mnt/cont-repo1 \
                          --content-dir /mnt/cont-repo2 \
                          --content-dir /mnt/cont-repo3 \
                          --provenance-dir /mnt/prov-repo1 \
                          --provenance-dir /mnt/prov-repo2 \
                          node-1:nifi-node-01 \
                          node-2:nifi-node-02 \
                          node-3:nifi-node-03 \
                          node-4:nifi-registry

# then you should be able to ssh into the nodes and confirm services are running
ssh ubuntu@nifi-node-01
systemctl status zookeeper kafka nifi
tail -100f /var/log/nifi/nifi-app.log

ssh ubuntu@nifi-registry
systemctl status nifi-registry
tail -100f /opt/nifi-registry/logs/nifi-registry-app.log
```
Once the nodes are attached to the cluster you can log into the UI console from either of the servers, http://host.addr.of.machine:8080 for an insecure cluster and https://host.addr.of.machine:9443 for a secure cluster.
