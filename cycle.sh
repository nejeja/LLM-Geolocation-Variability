# you set the list of nodes that you have defined in the case map; nastavíš seznam uzlů, co máš definované v case mapě
NODES=(vpn-eu-1 vpn-us-1 vpn-br-1 vpn-cn-1 vpn-ir-1 vpn-ru-1)

# and then a loop;a pak smyčku
for n in "${NODES[@]}"; do
  echo "=== Switching to $n ==="
  ./vpn_switch.sh "$n"
  sleep 10   # 10 second pause between switching;pauza 10 sekund mezi přepnutími
done
