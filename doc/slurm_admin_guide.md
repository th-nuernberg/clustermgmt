# Slurm Admin Guide

- [Slurm Admin Guide](#slurm-admin-guide)
  * [Variables](#variables)
    + [Vault Secrets](#vault-secrets)
    + [File to be modified](#file-to-be-modified)
    + [Files to be added](#files-to-be-added)
  * [Playbooks](#playbooks)
    + [Setup Environment Modules and Anaconda](#setup-environment-modules-and-anaconda)
    + [Slurm Configuration Update](#slurm-configuration-update)
  * [Role Variables](#role-variables)
  * [Example Playbook](#example-playbook)
  * [Dependencies](#dependencies)
    + [MUNGE](#munge)
    + [MariaDB](#mariadb)
    + [Lua Developer Resources](#lua-developer-resources)
    + [NVIDIA Management Library (NVML) development files](#nvidia-management-library--nvml--development-files)
    + [Enroot and Pyxis](#enroot-and-pyxis)
    + [OpenMPI](#openmpi)
    + [OpenPMIx](#openpmix)
  * [Manual Steps](#manual-steps)
    + [Setup Slurm Accounting](#setup-slurm-accounting)
    + [OCI Bundles](#oci-bundles)
    + [LDAP Schema](#ldap-schema)
  * [Slurm Accounting](#slurm-accounting)
    + [QOS Parameters](#qos-parameters)
    + [Setup Multi-Instance GPU (MIG)](#setup-multi-instance-gpu--mig-)
      - [MIG Discovery for Slurm](#mig-discovery-for-slurm)
  * [Slurm Node Configuration](#slurm-node-configuration)
  * [Troubleshooting](#troubleshooting)
    + [Invalid Argument Error](#invalid-argument-error)
    + [I/O error writing script/environment to file](#IO-error-writing-scriptenvironment-to-file)
  * [Slurm Example Commands](#slurm-example-commands)
  * [Containers](#containers)
    + [Pyxis and Enroot](#pyxis-and-enroot)
    + [OCI Container Bundles](#oci-container-bundles)
    + [Adjust Container Bundle Config](#adjust-container-bundle-config)
    + [OCI Runtime Config in Slurm](#oci-runtime-config-in-slurm)
    + [Setup](#setup)
  * [LDAP](#ldap)
    + [Pitfalls](#pitfalls)
    + [Helpful SLURM commands](#helpful-slurm-commands)
    + [LDAP Resources](#ldap-resources)
  * [Status E-Mails via Postfix](#status-e-mails-via-postfix)
    + [Problems with this Approach](#problems-with-this-approach)
  * [Status E-Mails via Slurm-Mail](#status-e-mails-via-slurm-mail)
    + [Using kiz-slurm@th-nuernberg.de as Sender](#using-kiz-slurm-th-nuernbergde-as-sender)
    + [Make E-Mail Layout nicer](#make-e-mail-layout-nicer)
    + [Fix Logrotate](#fix-logrotate)
  * [Resources](#resources)


This document describes pretty much everything related to the administration of the Slurm Workload Manager. 
## Variables
### Vault Secrets
The Standard Vault Password is `password` **CHANGE IT** with `ansible-vault rekey` and save it.
In the Vault you can find the secrets for ldap, mariadb and mysql
### File to be modified
- inventory
- group_vars/main.yml
- roles/slurm/defaults/main.yml
  - Everything under slurmNodes & slurm_partitions
  - slurm_cluster_name
- setup_common.yml
  - vars/mpi_nodes
  - Set the other Vars according to your needs( e.g. if you have a ldap serve you don't need to install it)
    - Same for slurmctld.yml and slurmd.yml

### Files to be added
- roles/slurm/files/munge.key
  - generate it with `create-munge-key`
- roles/ldap/files/cert.crt
  - copy it from the ldap server
  - 
## Playbooks

The `slurmd.yml` Playbook installs only worker nodes, while `slurmctld.yml` installs the control daemon (slurmctld) and the database daemon (slurmdbd).   

You can run the playbooks via:

```
ansible-playbook -i inventory --ask-become-pass --ask-pass --ask-vault-pass slurm[ctld|d].yml --tags install
```

Note that you might need to run with `--connection=local` if you run the `slurmctld.yml` playbook from *augustiner* and you plan to install the control daemon on the same host. 

The Ansible Vault password can be found in the mladm password store. 

You can append `--check` to the above command to do dry run. 

### Setup Environment Modules and Anaconda

Make sure you install Modules on the execution nodes **AND** on the Cluster head. 
Having Modules on the Cluster head is necessary, because Slurm does not source `/etc/profile.d` (this is what usually enables Modules system-wide) automatically but it will transfer the environment variables that are currently set on the node from which the command is executed. 
Having Modules in the PATH of the head node was the easiest way to make it available on the execution node as well without ressorting to sorcery like Prolog scripts. 

### Slurm Configuration Update

If you want to update the `slurm.conf` file on all nodes, you can do this as follows:

```bash
ansible-playbook -i inventory --ask-become-pass --ask-pass slurm_redistribute_config.yml --tags reconfigure
```

**Note:** Some parameters in `slurm.conf` require a full restart (i.e. restarting  slurmctld), not just `scontrol reconfigure`. 


## Role Variables

Some variables in the playbooks are optional. 
If nothing is set, the role will use the variables set in the **defaults file** named main.yml located in a folder named defaults. 
Example: The some variables for the role anaconda are set [here](../ansible/roles/anaconda/defaults/main.yml)

For the various roles a slurm node can play, you can either set group names, or add values to a list called `slurm_roles`:

- group slurmservers or `slurm_roles: ['controller']`
- group slurmexechosts or `slurm_roles: ['exec']`
- group slurmdbdservers or `slurm_roles: ['dbd']`
- group containerhosts or `slurm_roles: ['container']`

You can use `slurm_user` (a hash) and `slurm_create_user` (a bool) to pre-create a Slurm user (so that uids match).  

Set `slurm_from_source: yes` and `slurm_version: 'version-string'` if you want to build Slurm from source. 
Otherwise Ansible will pull the latest stable version from the package manager. 
Note that the packaged version is usually **several major versions behind** and does not offer some of the more recent features such as native OCI support.  

## Example Playbook

A simple playbook, which would install all four roles (controller, execution host, database host, container host) looks as follows:

```yaml
- name: Install everything
  hosts: all
  vars:
    slurm_roles: ['controller', 'exec', 'dbd', 'container']
  roles:
    - slurm
```

## Dependencies
Slurm has quite a few dependencies. 
Some of them are installed in the first step of the `tasks/compile.yml` task (provided you plan on compiling Slurm from source). 
Others come with separate Ansible tasks (e.g. `tasks/munge.yml`). 
The most important dependencies are briefly explained below. 

### MUNGE
[MUNGE](https://dun.github.io/munge/) is an authentication service for creating and validating credentials. 
It allows a process to authenticate the UID and GID of another local or remote process within a group of hosts having common users and groups.

When MUNGE is used for authentication in Slurm, you need to make sure that all nodes in the cluster have the same `munge.key`. 
Additionally, the MUNGE daemon, `munged` must be started before you start the Slurm daemons. 

Check `tasks/munge.yml` to see how it is installed. 

### MariaDB
MariaDB is used to collect accounting information for every Slurm job. 
The database is usually not accessed directly. 
The Slurm database daemon `slurmdbd` acts as an intermediary between the user and the database instead. 
Therefore, only `slurmdbd` requires permission to read/write the database
Note that `slurmctld` will cache data if `slurmdbd` not responding. 
Slurm's `sacctmgr` tool is used to view and modify the Slurm database

MariaDB is installed with `tasks/mariadb.yml`. 

You can place the following config values into `/etc/mysql/mariadb.cnf`:

```bash
[mysqld]
innodb_buffer_pool_size=24000M
innodb_log_file_size=64M
innodb_lock_wait_timeout=900
```

`innodb_buffer_pool_size` ensures that there is enough memory even for larger databases and `slurmdbd` won't complain on startup. 

### Lua Developer Resources 
The `liblua5.3-dev` package, which is installed in the `tasks/compile.yml` task, contains developer resources for the Lua language. 
We use Lua to write job submit plugins for Slurm. 

Job submit plugins are a way to customize Slurm's job submission behavior (see for example `templates/job_submit.lua.j2`). 
Job submit plugins must implement the two functions `job_submit` and `job_modify`. 
Consult the job submit plugin [docs](https://slurm.schedmd.com/job_submit_plugins.html) for more information. 

### NVIDIA Management Library (NVML) development files
The NVIDIA Management Library (NVML) development files package, which is installed in the `tasks/compile.yml` task, offers a monitoring and management API for NVIDIA GPUs. 
It provides a direct access to the queries and commands exposed via `nvidia-smi`. 

The package is required for the automatic detection of available GPUs via `Autodetect=nvml` in `gres.conf`. 
Hence, you'll have to install the package on GPU nodes, which use automatic GPU detection or automatic sanity checking via NVML.  

See [this mailing list](https://lists.schedmd.com/pipermail/slurm-users/2020-February/004838.html) and the [documentation](https://slurm.schedmd.com/gres.html#GPU_Management) for more information in GPU Management. 

### Enroot and Pyxis
The preferred way to use containers in Slurm is to run them through Pyxis and Enroot. 
Enroot and Pyxis are installed via the Ansible tasks `tasks/enroot.yml` and `tasks/pyxis.yml`. 

See the [Pyxis and Enroot](#pyxis-and-enroot) section for more information. 

**Note:**

Make sure that `libnvidia-container` (https://github.com/NVIDIA/libnvidia-container) is installed on the compute nodes. 

Otherwise you will get the following error, when containers are started with GPU:

```bash
slurmstepd: error: pyxis: printing enroot log file:
slurmstepd: error: pyxis:     [ERROR] Command not found: nvidia-container-cli, see https://github.com/NVIDIA/libnvidia-container
slurmstepd: error: pyxis:     [ERROR] /etc/enroot/hooks.d/98-nvidia.sh exited with return code 1
```

### OpenMPI

[Open MPI](https://www.open-mpi.org/) is an implementation of the Message Passing Interface (MPI), a communication protocol for distributed parallel computing. 

The general installation procedure looks as follows (this is what the `openmpi.yml` playbook does):

```bash
wget https://download.open-mpi.org/release/open-mpi/v4.1/openmpi-4.1.3.tar.gz
tar -xvzf openmpi-4.1.3.tar.gz
./configure --with-cuda --with-slurm --with-pmix=/opt/pmix
make -j 16 all install
```

OpenMPI is an optional dependency. 
That's why it can be found in a separate Ansible playbook. 
However, it probably makes sense to install since it is quite powerful. 

**Note:** OpenMPI must be installed **AFTER** Slurm is installed and properly configured. 

**Troubleshooting:**

- Check the `config.log` file whether Slurm and PMIx was properly detected. 

### OpenPMIx
[OpenPMIx](https://openpmix.github.io/) is the reference implementation of the Process Management Interface Exascale (PMIx) standard. 

It provides a way for Slurm and OpenMPI to communicate. 

The installation of OpenPMIx is required, if you configure Slurm with the `--with-pmix` flag. 

The general installation procedure looks as follows (this is what `pmix.yml` does):

```bash
wget https://github.com/openpmix/openpmix/releases/download/v3.2.3/pmix-3.2.3.tar.gz
tar -xvzf pmix-3.2.3.tar.gz
cd pmix-3.2.3
apt-get install libevent-dev
apt install libhwloc-dev
./configure --prefix=/opt/pmix --with-munge=/usr
make all install
```

You should configure the build with Munge support (`--with-munge=/usr`) to work properly with Slurm. 

Note that version `4.x` of OpenPMIx is currently not recognized automatically by Slurm and therefore doesn't work out of the box. 
That's why we use version `3.x` here. 

## Manual Steps
Unfortunately there are still a few manual steps involved to get Slurm up and running. 

### Setup Slurm Accounting
The easiest way to setup Slurm Accounting is to load a previously exported config and then sync LDAP and Slurm users via the `slurm_ldap_sync.yml` Playbook
Check the [Slurm Accounting section](#slurm-accounting) for more details on how to setup Slurm Accounting from scratch. 

### OCI Bundles
If you want to provide OCI Bundles to Slurm users, you can check [this documentation](https://slurm.schedmd.com/containers.html) to see how Docker images can be converted into OCI format. 

The scripts for automatic bundle copying and configuration can be found in `../conftemplates/slurm/oci`. 
These scripts should be copied to `/nfs/oci/tools`. 

### LDAP Schema
You need to create a custom LDAP schema containing an ObjectClass and AttributeTypes for Slurm. 
You'll have to add the `slurmRole` ObjectClass to each user in your LDAP who is supposed to have access to Slurm. 
You can do this with your favorite LDAP Admin Tool like JXPlorer or Apache Directory Studio as well as via the commandline. 
Optionally you can set the attributes `slurmDefaultQos` and `slurmQos` for each user individually
See the [LDAP section](#ldap) for more details on how to do all of this. 

## Slurm Accounting

Check if cluster is present:
```bash
sacctmgr list cluster

# If not present then add
sacctmgr add cluster thn-hpc
```

```bash
sacctmgr add account thn Description="THN root account" Organization=thn
sacctmgr add account cs parent=thn Description="Computer Science faculty accounts" Organization=thn
sacctmgr add account staff parent=cs Description="Computer Science faculty staff accounts" Organization=thn
sacctmgr add account student parent=cs Description="Computer Science faculty student accounts" Organization=thn
sacctmgr add user bayerlse Account=staff
sacctmgr add user riedhammerko Account=staff
sacctmgr add user bockletto Account=staff
sacctmgr add user wagnerdo Account=staff


# Add QOSs
sacctmgr add qos interactive
sacctmgr add qos basic
sacctmgr add qos advanced
sacctmgr add qos ultimate
sacctmgr add qos bigmem
sacctmgr add qos gpubasic
sacctmgr add qos gpuultimate
sacctmgr modify qos interactive set MaxJobsPerUser=2 MaxWallDurationPerJob=360:00 MaxTRESPerUser=cpu=4,mem=16384,gres/gpu=1
sacctmgr modify qos basic set MaxJobsPerUser=10 MaxWallDurationPerJob=720:00 MaxTRESPerUser=cpu=16,mem=32768,gres/gpu=1
sacctmgr modify qos advanced set MaxJobsPerUser=20 MaxWallDurationPerJob=1440:00 MaxTRESPerUser=cpu=24,mem=49152,gres/gpu=1
sacctmgr modify qos ultimate set MaxJobsPerUser=50 MaxWallDurationPerJob=2880:00 MaxTRESPerUser=cpu=32,mem=65536,gres/gpu=1
sacctmgr modify qos bigmem set MaxJobsPerUser=10 MaxWallDurationPerJob=720:00 MaxTRESPerUser=cpu=16,mem=131072
sacctmgr modify qos gpubasic set MaxJobsPerUser=10 MaxWallDurationPerJob=5760:00 MaxTRESPerUser=cpu=8,mem=16384,gres/gpu=1
sacctmgr modify qos gpuultimate set MaxJobsPerUser=10 MaxWallDurationPerJob=2880:00 MaxTRESPerUser=cpu=16,mem=32768,gres/gpu=3

# Enable QOS for accounts
sacctmgr modify account student where cluster=thn-hpc set QOS=basic Fairshare=20
sacctmgr modify account staff where cluster=thn-hpc set QOS=advanced Fairshare=80

# Add QOS to user
sacctmgr modify user wagnerdo set qos+=basic

# Asign admin level of user
sacctmgr modify user wagnerdo set adminlevel=admin

# Print associations
sacctmgr list associations cluster=thn-hpc format=Account,Cluster,User,Fairshare tree withd

# Print QOS
sacctmgr show qos format=name,priority,MaxJobsPerUser,MaxWallDurationPerJob,MaxTRESPerUser
# Output should look like this:
#           Name   Priority       MaxJobsPU     MaxWall                      MaxTRESPU
# --------------- ---------- --------------- ----------- ------------------------------
#         normal          0
#    interactive          0               2    06:00:00       cpu=4,gres/gpu=1,mem=16G
#          basic          0              10    12:00:00      cpu=16,gres/gpu=1,mem=32G
#       advanced          0              20  1-00:00:00      cpu=24,gres/gpu=1,mem=48G
#       ultimate          0              50  2-00:00:00      cpu=32,gres/gpu=1,mem=64G
#         bigmem          0              10    12:00:00                cpu=16,mem=128G
#    gpuultimate          0              10  2-00:00:00      cpu=16,gres/gpu=3,mem=32G
#       gpubasic          0              10  4-00:00:00       cpu=8,gres/gpu=1,mem=16G

```

To create a file of associations you can run:
```bash
sacctmgr dump clustername file=file.cfg
```

To load a previously created file you can run:
```bash
sacctmgr load file=file.cfg
```

### QOS Parameters
- MaxJobsPerUser: Maximum number of jobs each user is allowed to run at one time.
- MaxTRESPerUser: Maximum number of TRES each user is able to use.
- MaxWallDurationPerJob: Maximum wall clock time each job is able to use (NOTE: This setting shows up in the sacctmgr output as MaxWall).
- Fairshare= Integer value used for determining priority. Essentially this is the amount of claim this association and its children have to the above system.

### Setup Multi-Instance GPU (MIG)

Before we can tell Slurm about MIG enabled GPUs, we need to setup MIG via `nvidia-smi`:

```bash
# Enable MIG for all devices
nvidia-smi -mig 1
# List GPU instance profiles
nvidia-smi mig -lgip
# Create GPU instances (-cgi) and compute instances (-C)
nvidia-smi mig -cgi 4g.40gb -C
nvidia-smi mig -cgi 3g.40gb -C

# Use the following command to check if everything worked correctly
nvidia-smi
```

**Note:** After restarts, the MIG creation might not work for the first time. In this case, resetting the GPUs via `nvidia-smi --gpu-reset` and doing all of the above steps again might help. You might also want to restart `slurmd` via `service slurmd restart` so it re-reads the GRES configs. 


See https://docs.nvidia.com/datacenter/tesla/mig-user-guide/ for other options. 


#### MIG Discovery for Slurm

The Ansible role for Slurm currently only sets `AutoDetect=nvml` in `gres.conf`. 
It wouldn't make much sense to let Ansible configure MIG on a Node, since CUDA is installed and configured manually anyway. 

The easiest way to make Slurm recognize MIG enabled GPUs ist to use the following tool and then configure the `slurmd` accordingly: 

https://gitlab.com/nvidia/hpc/slurm-mig-discovery

The MIG Discovery tool creates a `gres.conf` file and a `cgroup_allowed_devices_file.conf` file. 
Copy those files and add the discovered MIG devices to `slurm.conf`

For example like this:

```
NodeName=ml2 Boards=1  CoreSpecCount=16  CoresPerSocket=64  CPUs=128  Gres=gpu:3g.40gb:8,gpu:4g.40gb:8  MemSpecLimit=32768  NodeAddr=ip  RealMemory=2052084  SocketsPerBoard=2  State=UNKNOWN  ThreadsPerCore=1
```

In this example, the GPU profiles `3g.40gb` and `gpu:4g.40gb` were configured and discovered. 
The first part (e.g. `3g`) marks the number of compute slices and the second part (`40gb`) marks the amount of memory available for this GPU instance. 

Note that the MIG Discovery tool expects MIG instances to be already configured via `nvidia-smi`. 

## Slurm Node Configuration

Executing the command `slurmd -C` on each compute node will print its physical configuration (sockets, cores, real memory size, etc.), which can be used in constructing the *slurm.conf* file.

## Troubleshooting

When the nodes are initialized in state down (`sinfo -a`) or when they suddenly go into `DRAIN` state, try with this after initiating the daemons:
```bash
scontrol update nodename=ml0 state=idle
# You can also set it to down and then putting it back up again
scontrol update nodename=ml0 state=down reason="reason for putting node down"
scontrol update nodename=ml0 state=idle
```

To show node information:
```bash
scontrol show node ml0
```

When the service config was changed, you should run `systemctl daemon-reload`. 

Make sure the `slurm` user has the same GID and UID across all nodes. 
You'll need to check `etc/group` and `/etc/passwd` for this. 

Make sure the Munge key in `/etc/munge/munge.key` is the same across all nodes. 
You can check by running `sha1sum munge.key`. 
Make sure `munge.key` is owned by user `munge` and is in group `munge` with 400 permissions. 

When jobs are stuck in the running state and only exit after the time limit is exceeded, it might be helpful to check `CoreSpecCount` and `MemSpecLimit` in the Node configuration. 
Those values determine how much resources are set aside to handle system overhead. 
Especially Kaldi's Slurm integration produces signifcant system overhead and can easily get stuck when not enough resources are allocated via `CoreSpecCount` and `MemSpecLimit`. 
For more information on core specialization see the [docs](https://slurm.schedmd.com/core_spec.html). 

Check the `/etc/hosts` file if you get errors on the nodes like this:

```
sinfo: error: get_addr_info: getaddrinfo() failed: Name or service not known
sinfo: error: slurm_set_addr: Unable to resolve "augustiner"
sinfo: error: Unable to establish control machine address
slurm_load_partitions: No error
```

This means a compute node is unable to reach the controller. 
This might be a DNS issue. 
One possible fix is to add the line `controllerIP controllerHostname` to your `/etc/hosts` file. 

### Invalid Argument Error

When you see an error like `[2022-08-05T17:04:47.741] error: _slurm_rpc_node_registration node=ml0: Invalid argument`, it is likely that values in the node configuration (RAM, CPUs etc) are higher than the actual values obtainable via `slurmd -C`. 

For example, this could happen, when a DIMM breaks in the node and suddenly you have less memory at your disposal. 

**FIX:**

Compare the values in `slurm.conf` with those generated by `slurmd -C` and adjust `slurm.conf` accordingly. 


### I/O error writing script/environment to file

When you see an error like this: `sbatch: error: Batch job submission failed: I/O error writing script/environment to file`, this is either because the filesystem on the control host is corrupted (this would be bad :/) or because the *slurm-mailer* wrote too many tiny files and **exhausted all available inodes**. 

You can quickly check whether inodes are still available on the control host via `df -i`. 
If you want to see which directory contains many files (i.e. consums a lot of inodes), you can do it like this:

```shell
{ find / -xdev -printf '%h\n' | sort | uniq -c | sort -k 1 -n; } 2>/dev/null
```

This command looks for files in all directories under `/` and sorts them in ascending order. 

When it's actually the slurm-mailer who is causing the problem, you can remove the files via: 

```shell
cd /var/log/slurm-mail
find . -name "*.gz.1" -print0 | xargs -0 rm
find . -name "*.gz" -print0 | xargs -0 rm
```

Note that regular `rm *.gz` probably won't work due to the large number of files in the directory. 




## Slurm Example Commands

These are just a few example commands that can be used for testing, whether Slurm is running. 

Get an interactive shell for 10 minutes:
```
srun -n 1 --time 10:00 --pty bash
```

Start three tasks on the same node:
```
srun -n3 -l /bin/hostname
```

## Containers
We offer two ways to run containers in Slurm:
1. Enroot and Pyxis (preferred)
2. OCI Container Bundles (less preferred)

### Pyxis and Enroot
The preferred way to use containers in Slurm is via Enroot and the Pyxis plugin.

[Enroot](https://github.com/NVIDIA/enroot) is a tool that adapts conventional containers to the requirements for HPC clusters 
The primary advantage of Enroot is that well-known container image formats such as Docker can be easily imported. 

[Pyxis](https://github.com/NVIDIA/pyxis) is a [SPANK plugin](https://slurm.schedmd.com/spank.html) for Slurm, that adds a few command line arguments to `srun` and `sbatch`, which enable execution and management of Enroot containers. 

The installation of Enroot and Pyxis is handled in the Ansible tasks `pyxis.yml` and `enroot.yml`. 


### OCI Container Bundles
Those are the basic steps for setting up an OCI runtime for Slurm. 
For more information see the [documentation](https://slurm.schedmd.com/containers.html). 

Docker is probably the easiest way to create new container bundles that are to be executed with Slurm:
```
docker pull alpine
docker create --name alpine alpine
mkdir -p /tmp/image/rootfs/
docker export alpine | tar -C /tmp/image/rootfs/ -xf -
docker rm alpine
```
According to [this documentation](https://github.com/opencontainers/runc/blob/master/README.md#rootless-containers), you can configure and run a rootless container bundle as follows:
```bash
cd /tmp/image
# The --rootless parameter instructs runc spec to generate a configuration for a rootless container, which will allow you to run the container as a non-root user.
# This command creates a config.json file containing the bundle specs.
runc spec --rootless

### For Testing without Slurm:
# The --root parameter tells runc where to store the container state. It must be writable by the user.
runc --root /tmp/container-state run mycontainerid
```

### Adjust Container Bundle Config
If you want to be able to mount folders on the host into the container, you'll need to adjust the `mounts` part in the bundle `config.json`. 
An example is provided below:
```json
    "mounts": [
            {
                    "destination": "/home",
                    "type": "none",
                    "source": "/tmp/image/mnt",
                    "options": ["rbind","rw"]
            },
```
The example binds the `/home` directory in the container to a folder called `/tmp/image/mnt` on the host. 
More information on the OCI mount configuration can be found [here](https://github.com/opencontainers/runtime-spec/blob/main/config.md#mounts). 

### OCI Runtime Config in Slurm
The Slurm configuration file for containers is `oci.conf`. 
The following `oci.conf` parameters are defined to control the behavior of the `--container` argument of `salloc`, `srun`, and `sbatch`. 

```
RunTimeQuery="runc --rootless=true --root=/tmp/ state %n.%u.%j.%s.%t"
# RunTimeCreate="runc --rootless=true --root=/tmp/ create %n.%u.%j.%s.%t -b %b"
# RunTimeStart="runc --rootless=true --root=/tmp/ start %n.%u.%j.%s.%t"
RunTimeKill="runc --rootless=true --root=/tmp/ kill -a %n.%u.%j.%s.%t"
RunTimeDelete="runc --rootless=true --root=/tmp/ delete --force %n.%u.%j.%s.%t"
RunTimeRun="runc --rootless=true --root=/tmp/ run %n.%u.%j.%s.%t -b %b"
```

Note that Slurm will **not** transfer the OCI container bundle to the execution nodes. The bundle must already exist on the requested path on the execution node.

### Setup
The host kernel must be configured to allow user land containers:
```
sudo sysctl -w kernel.unprivileged_userns_clone=1
```

## LDAP
We manage some Slurm attributes such as the QOS associated with a user on the LDAP server. 
For this we create an *auxiliary* ObjectClass, i.e., an ObjectClass that can be added to each user. 
The ObjectClass unlocks access to several AttributeTypes that can be used to manage SLURM-specific things like QOS. 

**Step 1:** Convert schema file into ldif format

First, we have to prepare a temporary directory and a dummy config for `slaptest`. 
The schema file `../var/slurm/slurm.schema` should be copied to `/etc/ldap/schema/`. 
This is the default place where all the currently installed LDAP schemas are expected on a Unix system. 

```bash
mkdir -p /tmp/slurm
cd /tmp/slurm
touch ldap.conf
echo "include /etc/ldap/schema/slurm.schema" > ldap.conf
slaptest -f ldap.conf -F .
```

`slurm.schema` looks something like this:

```bash
$ cat /etc/ldap/schema/slurm.schema
#
# OpenLDAP schema file for SLURM users
# Save as /etc/openldap/schema/slurm.schema and restart slapd.
# SYNTAX 1.3.6.1.4.1.1466.115.121.1.44 means it's a printable string
#
attributeType (83.76.85.82.77.1.1
  NAME 'slurmDefaultQos'
  EQUALITY caseIgnoreMatch
  SYNTAX 1.3.6.1.4.1.1466.115.121.1.44
  DESC 'Default Quality of Service (QOS) for a SLURM user'
  SINGLE-VALUE
  USAGE userApplications )

attributeType ( 83.76.85.82.77.1.2
  NAME 'slurmQos'
  EQUALITY caseIgnoreMatch
  SYNTAX 1.3.6.1.4.1.1466.115.121.1.44
  DESC 'QOS attributed to a SLURM user'
  USAGE userApplications )

objectClass ( 83.76.85.82.77.2.1 NAME 'slurmRole' SUP top
    AUXILIARY
    DESC 'SLURM user entries'
    MAY ( slurmDefaultQos $ slurmQos ))
```

The schema defines an auxiliary object class and two attribute types for SLURM. 

**Step 2:** Modify the generated ldif file `'cn={0}slurm.ldif'`

The ldif file generated by `slaptest` can be found in `/tmp/slurm/cn=config/cn=schema/`. 
When everything worked correctly, the file looks as follows:

```bash
# AUTO-GENERATED FILE - DO NOT EDIT!! Use ldapmodify.
# CRC32 39ffcd23
dn: cn={0}slurm
objectClass: olcSchemaConfig
cn: {0}slurm
olcAttributeTypes: {0}( 83.76.85.82.77.1.1 NAME 'slurmDefaultQos' DESC 'Defa
 ult Quality of Service (QOS) for a SLURM user' EQUALITY caseIgnoreMatch SYN
 TAX 1.3.6.1.4.1.1466.115.121.1.44 SINGLE-VALUE )
olcAttributeTypes: {1}( 83.76.85.82.77.1.2 NAME 'slurmQos' DESC 'QOS attribu
 ted to a SLURM user' EQUALITY caseIgnoreMatch SYNTAX 1.3.6.1.4.1.1466.115.1
 21.1.44 )
olcObjectClasses: {0}( 83.76.85.82.77.2.1 NAME 'slurmRole' DESC 'SLURM user
 entries' SUP top AUXILIARY MAY ( slurmDefaultQos $ slurmQos ) )
structuralObjectClass: olcSchemaConfig
entryUUID: 82141ae2-e79e-103b-920a-e11465f136ca
creatorsName: cn=config
createTimestamp: 20211202093227Z
entryCSN: 20211202093227.412786Z#000000#000#000000
modifiersName: cn=config
modifyTimestamp: 20211202093227Z
```

Despite what it says on the top of `'cn={0}slurm.ldif'`, you still need to modify it.  
Remove everything from the file, besides: 

- `dn: cn={0}slurm`
- `objectClass: olcSchemaConfig`
- `cn: {0}slurm`
- all `olcAttributeTypes`
- all `olcObjectClasses`

Finally, the keys for `dn` and `cn` need some correction:

- Remove the `{0}` from `cn: {0}slurm`
- `dn: cn={0}slurm` needs the correct path, which is `dn: cn=slurm,cn=schema,cn=config`

After the modifications, `'cn={0}slurm.ldif'` should look as something like this:

```bash
# AUTO-GENERATED FILE - DO NOT EDIT!! Use ldapmodify.
# CRC32 d6d0dbf3
dn: cn=slurm,cn=schema,cn=config
objectClass: olcSchemaConfig
cn: slurm
olcAttributeTypes: {0}( 83.76.85.82.77.1.1 NAME 'slurmDefaultQos' DESC 'Defa
 ult Quality of Service (QOS) for a SLURM user' EQUALITY caseIgnoreMatch SYN
 TAX 1.3.6.1.4.1.1466.115.121.1.44 SINGLE-VALUE )
olcAttributeTypes: {1}( 83.76.85.82.77.1.2 NAME 'slurmQos' DESC 'QOS attribu
 ted to a SLURM user' EQUALITY caseIgnoreMatch SYNTAX 1.3.6.1.4.1.1466.115.1
 21.1.44 )
olcObjectClasses: {0}( 83.76.85.82.77.2.1 NAME 'slurmRole' DESC 'SLURM user
 entries' SUP top AUXILIARY MAY ( slurmDefaultQos $ slurmQos ) )
```

**Step 3:** Add the ldif file to the LDAP server
```bash
# If you want to add it for the first time 
sudo ldapadd -Y EXTERNAL -H ldapi:/// -W -f './cn=config/cn=schema/cn={0}slurm.ldif'
# If you want to modify it
sudo ldapmodify -Y EXTERNAL -H ldapi:/// -W -f './cn=config/cn=schema/cn={0}slurm.ldif'
```

**Step 4:** Check if your schema has been added properly

```bash
sudo ldapsearch -Q -LLL -Y EXTERNAL -H ldapi:/// -b cn=config slurm
# You should see an output like:
dn: cn={6}slurm,cn=schema,cn=config
``` 


### Pitfalls
In general, you can do all this in a much simpler way by creating a `slurm.ldif` file like this and add it via ldapmodify:
```bash
# Add AttributeTypes and Objectclass to manage SLURM-specific attributes
dn: cn=schema,cn=config
changetype: modify
add: olcAttributeTypes
olcAttributeTypes: (83.76.85.82.77.1.1
  NAME 'slurmDefaultQos'
  EQUALITY caseIgnoreMatch
  SYNTAX 1.3.6.1.4.1.1466.115.121.1.44
  DESC 'Default Quality of Service (QOS) for a SLURM user'
  SINGLE-VALUE
  USAGE userApplications )
olcAttributeTypes: ( 83.76.85.82.77.1.2
  NAME 'slurmQos'
  EQUALITY caseIgnoreMatch
  SYNTAX 1.3.6.1.4.1.1466.115.121.1.44
  DESC 'QOS attributed to a SLURM user'
  USAGE userApplications )
-
add: olcObjectClasses
olcObjectClasses: ( 83.76.85.82.77.2.1 NAME 'slurmRole' SUP top
    AUXILIARY
    DESC 'SLURM user entries'
    MAY ( slurmDefaultQos $ slurmQos ))
```
The command to add this would be `sudo ldapmodify -Y EXTERNAL -H ldapi:/// -f slurm.ldif`. 
However **these changes won't be permanent**! 
As soon as you restart `slapd`, they are gone!

### Helpful SLURM commands
- Get reason why a node got drained (i.e. running jobs keep running but no new ones will be scheduled): `scontrol show node <nodename>`
- Change drained state `scontrol update nodename=<nodename> state=resume`

### LDAP Resources
Unfortunately, there are not very many helpful resources online and many of them are quite outdated and don't take the more recent `cn=conf` system for schema modification into account. 
Nevertheless, here are some resources that are not completely useless:
- https://www.gurkengewuerz.de/openldap-neue-schema-hinzufuegen/?cookie-state-change=1638436473037
- https://serverfault.com/questions/349446/unable-to-modify-schema-in-openldap-using-run-time-configuration-cn-config

## Status E-Mails via Postfix

Slurm can send status e-mails at various stages of a job's lifetime. 
This requires a requires a functioning mail server.

Follow these steps to setup a **send-only postfix server**: 

```bash
# Check that your ip maps to a hostname in /etc/hosts like this:
127.0.0.1 augustiner.informatik.fh-nuernberg.de augustiner

# Install postfix
apt-get update -y
apt-get install postfix
# run dpkg-reconfigure postfix if the installation interface doesnt show up

# Check that postfix is available
systemctl status postfix
```

Configure postfix according to the config below.

```bash
# /etc/postfix/main.cf
# See /usr/share/postfix/main.cf.dist for a commented, more complete version

smtpd_banner = $myhostname ESMTP $mail_name (Ubuntu)
biff = no

# appending .domain is the MUA's job.
append_dot_mydomain = no

# Uncomment the next line to generate "delayed mail" warnings
#delay_warning_time = 4h

readme_directory = no

# See http://www.postfix.org/COMPATIBILITY_README.html -- default to 2 on
# fresh installs.
compatibility_level = 2

# TLS parameters
smtpd_tls_cert_file=/etc/ssl/certs/ssl-cert-snakeoil.pem
smtpd_tls_key_file=/etc/ssl/private/ssl-cert-snakeoil.key
smtpd_tls_security_level=may

smtp_tls_CApath=/etc/ssl/certs
smtp_tls_security_level=may
smtp_tls_session_cache_database = btree:${data_directory}/smtp_scache

smtpd_relay_restrictions = permit_mynetworks permit_sasl_authenticated defer_unauth_destination
myhostname = augustiner.informatik.fh-nuernberg.de
alias_maps = hash:/etc/aliases
alias_database = hash:/etc/aliases
mydestination = augustiner.informatik.fh-nuernberg.de, augustiner, localhost.localdomain, localhost
relayhost =
mynetworks = 127.0.0.0/8 [::ffff:127.0.0.0]/104 [::1]/128
mailbox_size_limit = 51200000
recipient_delimiter = +
# inet_interfaces = all
# Make send-nly server
inet_interfaces = loopback-only
inet_protocols = all
myorigin = /etc/mailname

# Only allow specific users to send mail
authorized_submit_users = slurm, wagnerdo
# if you can't deliver it in an hour - it can't be delivered
maximal_queue_lifetime = 1h
maximal_backoff_time = 15m
minimal_backoff_time = 5m
queue_run_delay = 5m
```

Final steps:
```bash
systemctl restart postfix
# verify postfix server
echo "This is the body of the email" | mail -s "This is the subject" user@yourdomain.com
```

### Problems with this Approach
- Mails to *gmail* are blocked because we lack an 550-5.7.25 PTR record for the server
- Mails to *yahoo* are blocked after a while with the reason `temporarily deferred due to unexpected volume or user complaints - 4.16.55.1`. This is probably also due to the missing PTR record. 
- Mails to `th-nuernberg.de` are not sent because the connection to the mail gateway reaches a timeout


## Status E-Mails via Slurm-Mail
The [`slurm-mail`](https://github.com/neilmunday/slurm-mail) tool provides nicer and more verbose status mails. 
To setup `slurm-mail`, follow the installation instructions in the [project's Readme](https://github.com/neilmunday/slurm-mail). 

Don't forget to set the `MailProg` variable in `slurm.conf` to `MailProg=/opt/slurm-mail/bin/slurm-spool-mail.py`.  

Also make sure that `/opt/slurm-mail` is owned by `slurm:slurm` and that `/opt/slurm-mail/conf.d/slurm-mail.conf` has `640` permissions. 

### Using kiz-slurm@th-nuernberg.de as Sender

The following example shows how you can configure `slurm-mail` with the kiz-slurm@th-nuernberg.de mail account. 

```bash
# /opt/slurm-mail/conf.d/slurm-mail.conf
[slurm-send-mail]
# slurm-send-mail.py settings
logFile = /var/log/slurm-mail/slurm-send-mail.log
verbose = false
arrayMaxNotifications = 0
emailFromUserAddress = kiz-slurm@th-nuernberg.de
emailFromName = Slurm Admin
emailSubject = Job $CLUSTER.$JOB_ID: $STATE
validateEmail = false
datetimeFormat = %d/%m/%Y %H:%M:%S
sacctExe = /usr/local/bin/sacct
scontrolExe = /usr/local/bin/scontrol
smtpServer = my.ohmportal.de
smtpPort = 465
smtpUseTls = no
smtpUseSsl = yes
smtpUserName = kizslurm
smtpPassword = CHECK THE PASSWORD IN THE PASSWORDSTORE
tailExe = /usr/bin/tail
includeOutputLines = 10
```

### Make E-Mail Layout nicer

You can make the tables a bit nicer by adding the following style class to `/opt/slurm-mail/conf.d/style.css`:

```css
.styled-table {
        border-collapse: collapse;
        margin: 25px 0;
        font-size: 0.9em;
        min-width: 400px;
        box-shadow: 0 0 10px rgba(0, 0, 0, 0.15);
}

.styled-table th,
.styled-table td {
        padding: 12px 15px;
}

.styled-table tbody tr {
border-bottom: thin solid #dddddd;
}

.styled-table tbody tr:nth-of-type(even) {
        background-color: #f3f3f3;
```

Don't forget to include the `styled-table` class to the table in `/opt/slurm-mail/conf.d/templates/job-table.tpl` (`<table class="styled-table">`). 

### Fix Logrotate

The file `/etc/logrotate.d/slurm-mail` needs to look like this:

```shell
/var/log/slurm-mail/*.log
{
    missingok
    weekly
    compress
    rotate 5
}
```

## Resources

- https://github.com/galaxyproject/ansible-slurm
- https://github.com/CSCfi/ansible-role-slurm
- https://github.com/SANBI-SA/ansible-role-slurm
- https://gist.github.com/DaisukeMiyamoto/d1dac9483ff0971d5d9f34000311d312
- Very extensive doc for Ubuntu 18 with GPU: https://github.com/nateGeorge/slurm_gpu_ubuntu#prepare-db-for-slurm
- Ansible Roles of the NVIDIA HPC Cluster: https://github.com/NVIDIA/deepops/tree/20.08/roles/slurm

