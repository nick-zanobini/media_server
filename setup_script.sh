
cd "$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
sudo apt-get update
# install packages
sudo apt-get install unzip wget git apt-transport-https ca-certificates curl software-properties-common
# remove any old versions of docker
sudo apt-get remove docker docker-engine docker.io
# add Docker’s official GPG key
curl -fsSL https://download.docker.com/linux/ubuntu/gpg | sudo apt-key add -
# setup docker repository
sudo add-apt-repository "deb [arch=amd64] https://download.docker.com/linux/ubuntu $(lsb_release -cs) stable"
# update apt package index
sudo apt-get update
# install docker ce
sudo apt-get install docker-ce
# download docker compose
sudo curl -L https://github.com/docker/compose/releases/download/1.21.2/docker-compose-$(uname -s)-$(uname -m) -o /usr/local/bin/docker-compose
# apply executable permissions to the binary:
sudo chmod +x /usr/local/bin/docker-compose
# add docker group
sudo groupadd docker
# add user to docker group
sudo usermod -aG docker $USER
# setup docker to run on startup
sudo systemctl enable docker
# setup folder structure
sudo mkdir -p /opt/media_server/{delugevpn/openvpn,dockermon,duckdns,duplicati,grafana,homeassistant,influxdb,letsencrypt/{www,nginx/site-confs},mqtt/{config,data,log},ombi,plex,portainer,radarr,sonarr,tautulli}
# make directory for openvpn files
sudo mkdir /tmp/openvpn
# download openvpn files
sudo wget https://www.privateinternetaccess.com/openvpn/openvpn.zip -P /tmp/openvpn
# unzip openvpn files
sudo unzip -o /tmp/openvpn/openvpn.zip -d /tmp/openvpn/
# copy over ovpn file for the netherlands
sudo cp /tmp/openvpn/Netherlands.ovpn /opt/media_server/delugevpn/openvpn/
# copy the PIA certs and key files
sudo cp /tmp/openvpn/*.crt /opt/media_server/delugevpn/openvpn/
sudo cp /tmp/openvpn/*.pem /opt/media_server/delugevpn/openvpn/
# clean up openvpn files
sudo rm -rf /tmp/openvpn
# own /opt/media_server folder
sudo chown -R $USER:$GROUP /opt/media_server
# create a network for docker containers
docker network create proxy
# setup nginx with default locations
sudo mv default /opt/media_server/letsencrypt/nginx/site-confs/
# setup Organizr
git clone https://github.com/causefx/Organizr /opt/media_server/letsencrypt/www/Organizr
# setup mosquitto
sudo mv mosquitto.conf /opt/media_server/mqtt/mosquitto.conf
# setup influxdb
docker run --rm influxdb influxd config > /opt/media_server/influxdb/influxdb.conf

# Start Building .env file

# Get local Username
localuname=`id -u -n`
# Get PUID
PUID=`id -u $localuname`
# Get GUID
PGID=`id -g $localuname`
# Get Hostname
thishost=`hostname`
# Get IP Address
locip=`hostname -I | awk '{print $1}'`
# Get Time Zone
time_zone=`cat /etc/timezone`

# An accurate way to calculate the local network
# via @kspillane
# Grab the subnet mask from ifconfig
subnet_mask=$(ifconfig | grep $locip | awk -F ':' {'print $4'})
# Use bitwise & with ip and mask to calculate network address
IFSold=$IFS
IFS=. read -r i1 i2 i3 i4 <<< $locip
IFS=. read -r m1 m2 m3 m4 <<< $subnet_mask
IFS=$IFSold
lannet=$(printf "%d.%d.%d.%d\n" "$((i1 & m1))" "$((i2 & m2))" "$((i3 & m3))" "$((i4 & m4))")

# Converts subnet mask into CIDR notation
# Thanks to https://stackoverflow.com/questions/20762575/explanation-of-convertor-of-cidr-to-netmask-in-linux-shell-netmask2cdir-and-cdir
# Define the function first, takes subnet as positional parameters
function mask2cdr()
{
   # Assumes there's no "255." after a non-255 byte in the mask
   local x=${1##*255.}
   set -- 0^^^128^192^224^240^248^252^254^ $(( (${#1} - ${#x})*2 )) ${x%%.*}
   x=${1%%$3*}
   cidr_bits=$(( $2 + (${#x}/4) ))
}
mask2cdr $subnet_mask # Call the function to convert to CIDR
lannet=$(echo "$lannet/$cidr_bits") # Combine lannet and cidr

# Get Private Internet Access Info
read -p "What is your PIA Username?: " piauname
read -s -p "What is your PIA Password? (Will not be echoed): " piapass
printf "\n\n"

# Get DuckDNS Info
read -p "What is your DuckDNS Username?: " duckdnsuname
read -p "What is your DuckDNS Domain?: " duckdnsdomain
read -p "What are your DuckDNS Sub-Domains? (Leave empty if none): " duckdnssubdomains
read -p "What is your DuckDNS Token?: " duckdnstoken


# Get info needed for PLEX Official image
read -p "If you have PLEXPASS what is your Claim Token from https://www.plex.tv/claim/ (Optional): " pmstoken

# Select and Move the PIA VPN files
# Create a menu selection
echo "The following PIA Servers are avialable that support port-forwarding (for DelugeVPN); Please select one:"
PS3="Use a number to select a Server File or 'c' to cancel: "
# List the ovpn files
select filename in /opt/media_server/delugevpn/openvpn/*.ovpn
do
    # leave the loop if the user says 'c'
    if [[ "$REPLY" == c ]]; then break; fi
    # complain if no file was selected, and loop to ask again
    if [[ "$filename" == "" ]]
    then
        echo "'$REPLY' is not a valid number"
        continue
    fi
    # now we can use the selected file
    echo "$filename selected"
    cp $filename delugevpn/config/openvpn/ > /dev/null 2>&1
    vpnremote=`cat $filename | grep "remote" | cut -d ' ' -f2  | head -1`
    # it'll ask for another unless we leave the loop
    break
done


# Create the .env file
echo "Creating the .env file with the values we have gathered"
printf "\\n"
cat << EOF > .env
###  ------------------------------------------------
###        Media Server Configuration Settings
###  ------------------------------------------------
###  The values configured here are applied during
###  $ docker-compose up
###  -----------------------------------------------
###  DOCKER-COMPOSE ENVIRONMENT VARIABLES BEGIN HERE
###  -----------------------------------------------
###
EOF

echo "TZ=$time_zone" >> .env
echo "PUID=$PUID" >> .env
echo "PGID=$PGID" >> .env
echo "HOSTNAME=$thishost" >> .env
echo "IP_ADDRESS=$locip" >> .env

printf "\n" >> .env

echo "VPN_ENABLED=yes" >> .env
echo "VPN_USER=$piauname" >> .env
echo "VPN_PASS=$piapass" >> .env
echo "VPN_PROV=PIA" >> .env
echo "VPN_REMOTE=$vpnremote" >> .env
echo "VPN_PROTOCOL=udp" >> .env
echo "STRICT_PORT_FORWARD=yes" >> .env
echo "ENABLE_PRIVOXY=yes" >> .env
echo "LAN_NETWORK=$lannet" >> .env
echo "VPN_PORT=1198" >> .env
echo "NAME_SERVERS=209.222.18.222,37.235.1.174,8.8.8.8,209.222.18.218,37.235.1.177,8.8.4.4" >> .env
echo "DEBUG=false" >> .env
echo "UMASK=000" >> .env

printf "\n" >> .env

echo "PMSTOKEN=$pmstoken" >> .env

printf "\n" >> .env

echo "EMAIL=$duckdnsuname" >> .env
echo "URL=$duckdnsdomain" >> .env
echo "SUBDOMAINS=$duckdnssubdomains" >> .env
echo "VALIDATION=http" >> .env
echo "DUCKDNSTOKEN=$duckdnstoken" >> .env

echo ".env file creation complete"
printf "\\n\\n"

su - $USER
