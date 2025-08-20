# nifi-crdb-installation

### Everything described below can be configured and deployed from cloud-init, please find instructions to setup the environment on the [wiki page](https://github.com/longjatdepaul/nifi-crdb-installation/wiki)
  
<hr/>

#### This page provides instructions on setting up a basic NiFi cluster that can be used to demo data integrations with CRDB

<hr/>

## The Servers

If you don't have a hosted or on-premise cloud solution you can spinup a sample NiFi cluster on your desktop using VMware, VirtualBox or UTM.  For macOS / Apple Silicon you can download the UTM dmg from [here](https://mac.getutm.app/) and install the package.

With UTM I created three Ubuntu 64-bit VMs with the following configuration:
- **Memory**: 4GB
- **Virtual Hard Disk**: VDI
- **Disk Size**: 100GB Dynamically Allocated
- **Processor**: 2 CPUs
- **Network**: Bridged Adapter

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

You can run a small demo with these repositories on the same disk that NiFi is installed on, but for a proper POC I reccommend attaching separate disks using a single primary partition with one of the following allocations.  For a production installation we would have different recommendations.  We only need to attach and partition the drives, the script will mount them to the appropriate location.

For our local UTM cluster we attached a separate 50GB disk to each VM and partitioned it into five separate storage areas as described below.

| Disk | Mount | Size |
| ------------- | ------------- | ------------- |
| /dev/sdb5 | cont-repo1  | 10GB |
| /dev/sdb6 | cont-repo2  | 10GB |
| /dev/sdb7 | cont-repo3  | 10GB |
| /dev/sdb8 | prov-repo1  | 10GB |
| /dev/sdb9 | prov-repo2  | 10GB |

```
$ sudo parted -l
$ sudo wipefs -a /dev/sdb
$ sudo parted /dev/sdb
(parted) mklabel msdos
(parted) unit s
(parted) print free
(parted) mkpart extended 0% 100%
(parted) mkpart logical ext4 0% 20%
(parted) mkpart logical ext4 20% 40%
(parted) mkpart logical ext4 40% 60%
(parted) mkpart logical ext4 60% 80%
(parted) mkpart logical ext4 80% 100%
(parted) print
(parted) quit
```

For our GCP cluster we attached five separate disks to each server and used each disk as a single purpose storage device as described below

| Disk | Mount | Size |
| ------------- | ------------- | ------------- |
| /dev/sdb | cont-repo1  | 200GB |
| /dev/sdc | cont-repo2  | 200GB |
| /dev/sdd | cont-repo3  | 200GB |
| /dev/sde | prov-repo1  | 75GB |
| /dev/sdf | prov-repo2  | 75GB |

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
6. NiFi (ports 8080, 9998, 9999, 6342 and 4557 if insecure OR 9443, 10443, 11443, 6342 and 4557 if secure)
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
usage: ../nifi-crdb-installation.sh -h|? [Show Help = false]
                                    -i [Is Isolated = false]
                                    -d [CRDB Version = 21.2.2]
                                    -c [Certificate Location?]
                                    -p [Postgres Version = 42.2.19]
                                    -k [Kafka Version = 2.13-3.0.0]
                                    -u [Kafka User = kafka]
                                    -w [Kafka Password = kafkapassword]
                                    -l [Kafka Log Dir = /home/kafka/logs]
                                    -z [Zookeeper Data Directory = /home/kafka/zookeeper]
                                    -N [NiFi Version = 1.15.2]
                                    -U [NiFi User = nifi]
                                    -W [NiFi Password = nifipassword]
                                    -I [Installation Folder = /home/nifi/]
                                    -P [Sensitive Prop Key = default value]
                                    -F [Flowfile Repository = /flowfile_repository]
                                    -D [Database Repository = /database_repository]
                                    -C [Content Repository?]
                                    -O [Provenance Repository?]
                                    -M [Memory = 1g]
                                    -L [Log Directory = /home/nifi/logs]
                                    -S [Is Secure = false]
                                    node-<id>:<hostname>=<ip.address> [node-<id>:...]
                                    contrepo-<id>:<mount>=<filesystem> [contrepo-<id>:...]
                                    provrepo-<id>:<mount>=<filesystem> [provrepo-<id>:...]

This script is designed to install dependencies, configure and start a clustered NiFi environment that can be used to POC data
flows with CRDB

SWITCH PARAMETERS:
-h|? Show Help:                   if provided then prints this menu
-i   Is Isolated:                 if provided then will only execute the script on this node, otherwise replicates to other
                                  nodes, defaults to false so that replication is enabled
-d   CRDB Version:                specifies the database version of cockroach that should be used for connectivity, defaults
                                  to 25.3.0
-c   Certificate Location:        either the remote HTTP or local folder location of the client certificate used for secure
                                  CRDB connections, if not specified then ignores this step
-p   Postgres Version:            specifies the driver version of Postgres that should be used for connectivity, defaults to
                                  42.7.7
-k   Kafka Version:               specifies the software version of Kafka that should be used for streaming data, defaults to
                                  2.13-3.9.1
-u   Kafka User:                  specifies the account that will be used to install and run Kafka as a service, defaults to
                                  kafka
-w   Kafka Password:              specifies the password used to login as the kafka user, defaults kafkapassword
-l   Kafka Log Directory:         specifies the root disk location where kafka log files will be written to, defaults to
                                  /home/kafka/logs
-z   Zookeeper Data Directory:    specifies the root disk location where zookeeper data files will be written to, defaults to
                                  /home/kafka/zookeeper
-N   NiFi Version:                specifies the version of NiFi that should be installed, defaults to 2.0.0
-U   NiFi User:                   specifies the account that will be used to install and run NiFi as a service, defaults nifi
-W   NiFi Password:               specifies the password used to login as the nifi user, defaults nifipassword
-I   Installation Folder:         sepcifies where the NiFi binaries will be installed for the NIFI_HOME enviornment variable,
                                  defaults to /home/nifi/
-P   Sensitive Prop Key:          specifies a unique value used to derive a key for generating cipher text on sensitive
                                  properties, defaults to a hard-coded value
-F   Flowfile Repository:         specifies the root disk location where flowfiles will be persistently stored, defaults to
                                  /flowfile_repository
-D   Database Repository:         specifies the root disk location where database files will be persistently stored, defaults
                                  to /database_repository
-C   Content Repository:          specifies the root disk location where content data will be persistently stored, if not
                                  specified then rely on separate mount points
-O   Provenance Repository:       specifies the root disk location where data provenance will be persistently stored, if not
                                  specified then rely on separate mount points
-M   Memory:                      specifies the heap size to allocate for nifi core processes, defaults to 1g but should be much
                                  larger for anything other than testing the install
-L   Log Directory:               specifies the root disk location where log files will be written to, defaults to /home/nifi/logs
-S   Secure:                      use this flag if you have certificates to enable TLS and user authentication, defaults false

ADDITIONAL PARAMETERS:
node:        for each node in the cluster provide the hostname and ip address of the node as node-id:hostname=ip.address, i.e.
                 node-1:nifi-pkg-1=192.168.86.27 node-2:nifi-pkg-2=192.168.86.35 node-3:nifi-pkg-3=192.168.86.38
contrepo:    for each device allocated to store content, provide the filesystem and mount as contrepo-id:mount=filesystem, i.e.
                 contrepo-contS1R1:cont-repo1=/dev/sdb5 contrepo-contS1R2:cont-repo2=/dev/sdb6 contrepo-contS1R3:cont-repo3=/dev/sdb7
provrepo:    for each device allocated to store data provenance, provide the filesystem and mount as provrepo-id:mount=filesystem, i.e.
                 provrepo-provS1R1:prov-repo1=/dev/sdb8 provrepo-provS1R2:/prov-repo2=/dev/sdb9
```
The default values should work fine, however, you will need to provide the list of nodes that are allocated for the cluster, the location of your CRDB certificate and the mount points that you want created for your NiFi repositories.  If your cert is not available over an http endpoint you can manually copy it into a local directory on each server.  Also, assuming a GCP N2 General-purpose 32 vCPU and 64 GB machine, you'll want to change the memory allocation to 32g.  After executing the script you'll want to check that services are up and running.  If you do not have SSH enabled you'll need to execute the script on the other nodes in the cluster using the -i flag to isolate the installation steps on a single server.
```
./nifi-crdb-installation.sh -c "https://url or directory/location/of/cert" \
                            -M 32g \
                            node-1:nifi-pkg-1=192.168.86.46 \
                            node-2:nifi-pkg-2=192.168.86.44 \
                            node-3:nifi-pkg-3=192.168.86.43 \
                            contrepo-contS1R1:cont-repo1=/dev/sdb5 \
                            contrepo-contS1R2:cont-repo2=/dev/sdb6 \
                            contrepo-contS1R3:cont-repo3=/dev/sdb7 \
                            provrepo-provS1R1:prov-repo1=/dev/sdb8 \
                            provrepo-provS1R2:prov-repo2=/dev/sdb9 \
                            2>&1 | tee nifi-crdb-installation.out

$ systemctl status zookeeper
$ systemctl status kafka
$ systemctl status nifi
$ tail -100f /home/nifi/logs/nifi-app.log
```
Once the nodes are attached to the cluster you can log into the UI console from either of the servers, http://ip.addr.of.machine:8080 for an insecure cluster and https://ip.addr.of.machine:9443 for a secure cluster.
