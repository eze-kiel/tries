+++
title = "Attacking DHCP"
date = "2020-10-27T21:11:19+02:00"
tags = ["dhcp"]
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

The attacker sends many DHCP requests with differents MAC addresses, which result in
