
iptables -t nat -F
iptables -F
iptables -t nat -X REDSOCKS
iptables -t nat -N REDSOCKS
# don't mess with proxy traffic
iptables -t nat -A REDSOCKS -m owner --gid-owner squid -j RETURN
iptables -t nat -A REDSOCKS -p tcp -j REDIRECT --to-ports 12345


iptables -t nat -A OUTPUT -p tcp -d 192.168.122.121 -j REDSOCKS
