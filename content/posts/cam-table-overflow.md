+++
title = "CAM Table Overflow"
date = "2020-11-19T13:43:19+01:00"
tags = ["lvl2", "offensive", "defensive"]
description = "How to turn a switch into a hub."
+++

This short article will introduce the CAM Table Overflow attack, which can be used to turn a switch into a hub.

## CAM Table functionning

In a switch, a CAM table holds informations as which MAC addresses are on which physical port, or informations concerning VLAN configuration. When a switch receives a level 2 frame, it inspects in the CAM table the destination MAC address. If a corresponding entry exists, it will forward the frame to the associated port. On the other hand, if the entry doesn't exists, it will transmit the frame on all the ports (it floods the ports), behaving as a hub. Then, if a response is catched, the entry will be added to the table.

It is important to note that CAM tables have a limited size, which depends on the switch model. On Cisco stuff, this can ve accessed via the command `show mac address-table count`:

```
Cisco2960# show mac address-table count

Mac Entries for Vlan 10:
--------------------
Dynamic Address Count : 7
Static Address Count : 0
Total Mac Addresses : 7

...
Total Mac Address Space Available : 8164
```

## Executing the attack

There is a dedicated tool for this kind of attacks called `macof`. It can be installed  by installing the `dsniff` package.

Let's check its manpage:

```
$ man macof

NAME
       macof - flood a switched LAN with random MAC addresses

SYNOPSIS
       macof [-i interface] [-s src] [-d dst] [-e tha] [-x sport] [-y dport] [-n
       times]

DESCRIPTION
       macof floods the local network  with  random  MAC  addresses  (causing  some
       switches  to fail open in repeating mode, facilitating sniffing). A straight
       C  port  of  the  original  Perl  Net::RawIP  macof  program  by  Ian  Vitek
       <ian.vitek@infosec.se>.

OPTIONS
       -i interface
              Specify the interface to send on.

       -s src Specify source IP address.

       -d dst Specify destination IP address.

       -e tha Specify target hardware address.

       -x sport
              Specify TCP source port.

       -y dport
              Specify TCP destination port.

       -n times
              Specify the number of packets to send.

       Values for any options left unspecified will be generated randomly.
```

As you can see, it is relatively easy to use. But how does it work ?

MAC Address Flooding, also known as CAM Table Overflow, consists in filling the switch CAM table with invalid MAC addresses. By doing this, the switch will no longer be able to register new entries in its table, which will lead to a traffic duplication on all the ports: it will behave as a hub.

The attacker will then receive all the VLAN traffic without having to enable classic flow redirection parameters. Note that after a certain duration (which can be set with `aging time`), the entries are removed from the table, making the switch working normally again.

The minimal `macof` command looks like:

```
# macof -i eth0
```

## How to protect from MAC Address Flooding

To prevent these attacks, it is possible to enable the "port security" functionality on Cisco equipments. This functionality allow the sysadmin to specify:

* a specific MAC address on a given port;

* a maximum MAC addresses that can be associated to a given port.

When an invalid MAC address is detected, the switch can either block this address, or disable the port.

Configuration example on a Cisco 2690 switch:

```
(config)# interface FastEthernet1/0/3

(config-if)# switchport port-security   # enable the port security functionality

(config-if)# switchport port-security maximum 2   # maximum 2 MAC addresses can be learned on this interface

(config-if)# switchport port-security violation shutdown   # this port will get the "error" state if case of port-security activation

(config)# errdisable recovery cause psecure-violation 

(config)# errdisable recovery interval 30   # if the port is in "error" state for more than 30sec, it will return to the normal state again
```

In this example, we are setting the port-security mode to shutdown, but there is other options:

* protect: drop packets coming from an invalid MAC address until the unknown MAC addresses number goes under a fixed limit;

* restrict: same as the protect mode, but it increments a counter (security vioation counter);

* shutdown: set the port in error state (error disabled state) and send a SNMP trap.