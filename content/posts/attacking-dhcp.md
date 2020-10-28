+++
title = "Attacking DHCP"
date = "2020-10-27T21:11:19+02:00"
tags = ["dhcp", "offensive"]
description = "How to attack the DHCP protocol from inside a network."
+++

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
* DHCP Request : the client send a broadcast frame to announce from which server he want to use the configuration from.
* DHCP Ack : the chosen DHCP server assigns the IP and configuration parameters and acknowledges.
* DHCP Nack : the DHCP server rejects the client's request.
* DHCP Decline : the client rejects the offered IP address.
* DHCP Release : the client send back his assigned IP address beafore the lease expires.

Note that the response from the server (the DHCP Offer frame) contains not only the client IP, but other importants parameters as netmask, default gateway, and DNS.

For more informations about the DHCP, check the [Wikipedia page](https://en.wikipedia.org/wiki/Dynamic_Host_Configuration_Protocol).

## DHCP starvation attack

This first attack consists of exhausting the DHCP server's IP addresses pool with a huge number of requests.

The attacker sends many DHCP requests with differents MAC addresses, which result in using all the available IP addresses. All the new machines taht will try to connect to the network will not have any IP.

Then, the attacker can configure his working machine to be the new DHCP server to serve the new machines.

In a DHCP lease, informations about the default gateway and DNS are transmitted. The attacker can propose a lease to newcomers saying that he is the default gateway, which allow Man In The Middle attacks : every packets sent by hosts will go through the attacker machine.

There is a famous framework for level 2 attacks called `yersinia` that allow us to launch DHCP starvation attacks :

```
# yersinia dhcp -attack 1 -interface eth0
```

After specifying the protocol with the DHCP argument, we indicate the attack mode. `-attack 1` corresponds to 'DoOS attack sending discover packets' (see [this section](#the-dhcp-protocol)). The flag `-interface` allow us to specify which interface to use during the attack.

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

where `-attack 2` means 'nonDoS attack creating DHCP rogue server'. This attack mode does not need to use DoS, as it's implementation is probably faster than standard DHCP used in home/office routers.

## How to protect

Being offensive is nice, but it's interesting to see the _blue side_ of the Force. I'll talk about Cisco equipment features.

There is 2 principal ways to avoid those attacks : **DHCP snooping** and **IP source guard**.