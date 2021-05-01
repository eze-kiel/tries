+++
title = "Attacking DHCP"
date = "2020-10-27T21:11:19+02:00"
tags = ["defensive", "dhcp", "lvl2", "offensive"]
description = "How to attack the DHCP protocol from inside a network."
+++

## Table of Contents
- [The DHCP protocol](#the-dhcp-protocol)
- [DHCP starvation attack](#dhcp-starvation-attack)
- [DHCP rogue server attack](#dhcp-rogue-server-attack)
- [How to protect](#how-to-protect)

This article will introduce 2 different kinds of DHCP attacks : **DHCP starvation attack** and **DHCP rogue server attack**. But first, some reminders.

## The DHCP protocol

**Dynamic Host Configuration Protocol** allow computers to automatically receive IP addresses and network configuration from a DHCP server.

Here is a typical IP address obtention :
```
DHCP Client                   DHCP Server
    +
    +------------------------------>
             DHCP Discover
                                   +
    <------------------------------+
             DHCP Offer
    +
    +------------------------------>
             DHCP Request
                                   +
    <------------------------------+
       DHCP Ack (or Decline, Nack)
    +
    +------------------------------>
             DHCP Release

```
We can see 7 different kinds of frames :

* DHCP Discover : this frame is broadcasted to all the network, in order to find the DHCP server.
* DHCP Offer : the server responds to a DHCP discover in unicast. This frame contains network configuration (IP address pool, gateway address...).
* DHCP Request : the client sends a broadcast frame to announce from which server he want to use the configuration from.
* DHCP Ack : the chosen DHCP server assigns the IP and configuration parameters and acknowledges.
* DHCP Nack : the DHCP server rejects the client's request.
* DHCP Decline : the client rejects the offered IP address.
* DHCP Release : the client sends back his assigned IP address beafore the lease expires.

Note that the response from the server (the DHCP Offer frame) contains not only the client IP, but other importants parameters as netmask, default gateway, and DNS.

For more informations about DHCP, check the [Wikipedia page](https://en.wikipedia.org/wiki/Dynamic_Host_Configuration_Protocol).

## DHCP starvation attack

This first attack consists of exhausting the DHCP server's IP addresses pool with a huge number of requests.

The attacker sends many DHCP requests with differents MAC addresses, which result in using all the available IP addresses. All the new machines that will try to connect to the network will not have any IP.

Then, the attacker can configure his working machine to be the new DHCP server to serve the new machines.

In a DHCP lease, informations about the default gateway and DNS are transmitted. The attacker can propose a lease to newcomers saying that he is the default gateway, which allow Man In The Middle attacks : every packets sent by hosts will go through the attacker machine.

There is a famous framework for level 2 attacks called `yersinia` that allow us to launch DHCP starvation attacks :

```
# yersinia dhcp -attack 1 -interface eth0
```

After specifying the protocol with the DHCP argument, we indicate the attack mode. `-attack 1` corresponds to 'DoS attack sending discover packets' (see [this section](#the-dhcp-protocol)). The flag `-interface` allow us to specify which interface to use during the attack.

Once the attack is launched, we can check the MAC address available space on the switch:

```
Cisco2960# show mac address-table count
...
Total Mac Address Space Available : 0
```

It works ! Now, you can create your own DHCP rogue server :)

To stop the attack, just kill the process :

```
# killall yersinia
```

## DHCP rogue server attack

The goal of this attack is to introduce in the network a rogue DHCP server that will responds to clients requests.

In order to succeed, you have to respond faster to DHCP Discover requests than the initial DHCP server. This can be done by multiple ways :

* By lauching a DoS attack to the current DHCP server : this will result in a longer time to respond, which give you an advantage.

* By re-implementing DHCP on the attacker machine : DHCP servers usually do other things (DNS, gateway...). Basically, they take more time to respond than a simple DHCP server. Moreover, they have to look into their cache to see if an IP address has already been attributed, etc... So by implementing a DHCP server that will directly respond to a DHCP Discovery request with a hard-coded IP address, it is possible to be faster.

In reality, you have to be faster twice : to reply to the DHCP Discovery and to send the DHCP Ack to validate the offer.

As seen before, `yersinia` allows us to do this attack :

```
# yersinia dhcp -attack 2 -interface eth0
```

where `-attack 2` means 'nonDoS attack creating DHCP rogue server'. This attack mode does not need to use DoS, as its implementation is probably faster than standard DHCP used in home/office routers.

## How to protect

Being offensive is nice, but it's interesting to see the _blue side_ of the Force. I'll talk about Cisco equipment features.

There is 2 principal ways to avoid those attacks on Cisco equipments : **DHCP snooping** and **IP source guard**.

* DHCP snooping allows to filter suspicious DHCP requests, and building what is called a 'DHCP binding table'. This table contains the DHCP attributions, as MAC addresses, IP addresses, lease duration, VLAN number and corresponding interface.

The sysadmin can specify on the switch trusted interfaces on which DHCP offers and DHCP {Ack,NAck} can be received. Those interfaces are designated as **trusted**, and others as **untrusted**.

Each interface that link a client to the switch must be set to untrusted, which only permit DHCP Discover/Request packets to enter; others are dropped.

Ports on which a DHCP server is connected must be set as trusted in order for the switch to accept DHCP Offers and DHCP {Ack,NAck} packets.

The DCHP binding table holds information about untrusted ports, and is fed by dynamic entries learnt via DHCP. On an important network, it is recommended to outsource this table : locally, it is stored in flash memory. For each new entry, its content have to be erased and wrote again. It can also generate heavy CPU loads, and is case of shutdown, all the tables are lost.

It is possible to configure automatic outsourcing as following :

```
(config)# ip dhcp snooping database ftp://192.168.42.69/binding-table.dhcp
(config)# ip dhcp snooping database write-delay 300
```

In the example we use FTP, but HTTP, RCP and TFTP are allowed too. `write-delay` is the duration between every copy when the table changes.

* IP source guard allow us to protect from IP usurpation obtained by DHCP. In this kind of attack, the attacker changes his IP and/or his MAC address in order to access a remote machine (IP spoofing) or to avoid ACL set by the sysadmin.

IP source guard uses the DHCP binding table. At the beginning all the IP traffic is dropped, except DHCP packets. Once a client has received a valid IP from the server, a VLAN ACL is set on the corresponding port. All the traffic emitted with another IP∕MAC on this port will be dropped.

To configure IP source guard on a Cisco swicth, you can enter :

```
(config)# interface FastEthernet1/0/3   # or whatever interface you want
(config-if)# ip verify source port security
```