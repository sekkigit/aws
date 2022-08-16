#!/bin/bash -e
# Bastion Bootstrapping
# NOTE: This requires GNU getopt. On Mac OS X and FreeBSD you must install GNU getopt and mod the checkos function so that it's supported

source /root/.bashrc

# Configuration
PROGRAM='Linux Bastion'

##################################### Functions Definitions

function setup_environment_variables() {
    REGION=$(curl -sq http://169.254.169.254/latest/meta-data/placement/availability-zone/)
      #ex: us-east-1a => us-east-1
    REGION=${REGION: :-1}

    ETH0_MAC=$(/sbin/ip link show dev eth0 | /bin/egrep -o -i 'link/ether\ ([0-9a-z]{2}:){5}[0-9a-z]{2}' | /bin/sed -e 's,link/ether\ ,,g')

    _userdata_file="/var/lib/cloud/instance/user-data.txt"

    INSTANCE_ID=$(curl -s http://169.254.169.254/latest/meta-data/instance-id)
    EIP_LIST=$(grep EIP_LIST ${_userdata_file} | sed -e 's/EIP_LIST=//g' -e 's/\"//g')

    LOCAL_IP_ADDRESS=$(curl -sq 169.254.169.254/latest/meta-data/network/interfaces/macs/${ETH0_MAC}/local-ipv4s/)

    CWG=$(grep CLOUDWATCHGROUP ${_userdata_file} | sed 's/CLOUDWATCHGROUP=//g')

    # LOGGING CONFIGURATION
    BASTION_MNT="/var/log/bastion"
    BASTION_LOG="bastion.log"
    echo "Setting up bastion session log in ${BASTION_MNT}/${BASTION_LOG}"
    mkdir -p ${BASTION_MNT}
    BASTION_LOGFILE="${BASTION_MNT}/${BASTION_LOG}"
    BASTION_LOGFILE_SHADOW="${BASTION_MNT}/.${BASTION_LOG}"
    touch ${BASTION_LOGFILE}
    if ! [ -L "$BASTION_LOGFILE_SHADOW" ]; then
      ln ${BASTION_LOGFILE} ${BASTION_LOGFILE_SHADOW}
    fi
    mkdir -p /usr/bin/bastion
    touch /tmp/messages
    chmod 770 /tmp/messages

    export REGION ETH0_MAC EIP_LIST CWG BASTION_MNT BASTION_LOG BASTION_LOGFILE BASTION_LOGFILE_SHADOW \
          LOCAL_IP_ADDRESS INSTANCE_ID
}

function harden_ssh_security () {
    # Allow ec2-user only to access this folder and its content
    #chmod -R 770 /var/log/bastion
    #setfacl -Rdm other:0 /var/log/bastion

    # Make OpenSSH execute a custom script on logins
    echo -e "\nForceCommand /usr/bin/bastion/shell" >> /etc/ssh/sshd_config



cat <<'EOF' >> /usr/bin/bastion/shell
bastion_mnt="/var/log/bastion"
bastion_log="bastion.log"
# Check that the SSH client did not supply a command. Only SSH to instance should be allowed.
export Allow_SSH="ssh"
export Allow_SCP="scp"
if [[ -z $SSH_ORIGINAL_COMMAND ]] || [[ $SSH_ORIGINAL_COMMAND =~ ^$Allow_SSH ]] || [[ $SSH_ORIGINAL_COMMAND =~ ^$Allow_SCP ]]; then
#Allow ssh to instance and log connection
    if [[ -z "$SSH_ORIGINAL_COMMAND" ]]; then
        /bin/bash
        exit 0
    else
        $SSH_ORIGINAL_COMMAND
    fi
log_shadow_file_location="${bastion_mnt}/.${bastion_log}"
log_file=`echo "$log_shadow_file_location"`
DATE_TIME_WHOAMI="`whoami`:`date "+%Y-%m-%d %H:%M:%S"`"
LOG_ORIGINAL_COMMAND=`echo "$DATE_TIME_WHOAMI:$SSH_ORIGINAL_COMMAND"`
echo "$LOG_ORIGINAL_COMMAND" >> "${bastion_mnt}/${bastion_log}"
log_dir="/var/log/bastion/"

else
# The "script" program could be circumvented with some commands
# (e.g. bash, nc). Therefore, I intentionally prevent users
# from supplying commands.

echo "This bastion supports interactive sessions only. Do not supply a command"
exit 1
fi
EOF

    # Make the custom script executable
    chmod a+x /usr/bin/bastion/shell

}

function request_eip() {

    # Is the already-assigned Public IP an elastic IP?
    _query_assigned_public_ip

    set +e
    _determine_eip_assc_status ${PUBLIC_IP_ADDRESS}
    set -e

    if [[ ${_eip_associated} -eq 0 ]]; then
      echo "The Public IP address associated with eth0 (${PUBLIC_IP_ADDRESS}) is already an Elastic IP. Not proceeding further."
      exit 1
    fi

    EIP_ARRAY=(${EIP_LIST//,/ })
    _eip_assigned_count=0

    for eip in "${EIP_ARRAY[@]}"; do

      if [[ "${eip}" == "Null" ]]; then
        echo "Detected a NULL Value, moving on."
        continue
      fi

      # Determine if the EIP has already been assigned.
      set +e
      _determine_eip_assc_status ${eip}
      set -e
      if [[ ${_eip_associated} -eq 0 ]]; then
        echo "Elastic IP [${eip}] already has an association. Moving on."
        let _eip_assigned_count+=1
        if [[ "${_eip_assigned_count}" -eq "${#EIP_ARRAY[@]}" ]]; then
          echo "All of the stack EIPs have been assigned (${_eip_assigned_count}/${#EIP_ARRAY[@]}). I can't assign anything else. Exiting."
          exit 1
        fi
        continue
      fi

      _determine_eip_allocation ${eip}

      # Attempt to assign EIP to the ENI.
      set +e
      aws ec2 associate-address --instance-id ${INSTANCE_ID} --allocation-id  ${eip_allocation} --region ${REGION}

      rc=$?
      set -e

      if [[ ${rc} -ne 0 ]]; then

        let _eip_assigned_count+=1
        continue
      else
        echo "The newly-assigned EIP is ${eip}. It is mapped under EIP Allocation ${eip_allocation}"
        break
      fi
    done
    echo "${FUNCNAME[0]} Ended"
}

function _query_assigned_public_ip() {
  # Note: ETH0 Only.
  # - Does not distinguish between EIP and Standard IP. Need to cross-ref later.
  echo "Querying the assigned public IP"
  PUBLIC_IP_ADDRESS=$(curl -sq 169.254.169.254/latest/meta-data/public-ipv4/${ETH0_MAC}/public-ipv4s/)
}

function _determine_eip_assc_status(){
  # Is the provided EIP associated?
  # Also determines if an IP is an EIP.
  # 0 => true
  # 1 => false
  echo "Determining EIP Association Status for [${1}]"
  set +e
  aws ec2 describe-addresses --public-ips ${1} --output text --region ${REGION} 2>/dev/null  | grep -o -i eipassoc -q
  rc=$?
  set -e
  if [[ ${rc} -eq 1 ]]; then
    _eip_associated=1
  else
    _eip_associated=0
  fi

}

function _determine_eip_allocation(){
  echo "Determining EIP Allocation for [${1}]"
  resource_id_length=$(aws ec2 describe-addresses --public-ips ${1} --output text --region ${REGION} | head -n 1 | awk {'print $2'} | sed 's/.*eipalloc-//')
  if [[ "${#resource_id_length}" -eq 17 ]]; then
      eip_allocation=$(aws ec2 describe-addresses --public-ips ${1} --output text --region ${REGION}| egrep 'eipalloc-([a-z0-9]{17})' -o)
  else
      eip_allocation=$(aws ec2 describe-addresses --public-ips ${1} --output text --region ${REGION}| egrep 'eipalloc-([a-z0-9]{8})' -o)
  fi
}
##################################### End Function Definitions
# Assuming it is, setup environment variables.
setup_environment_variables

## set an initial value
SSH_BANNER="LINUX BASTION"

harden_ssh_security
request_eip

echo "Bootstrap complete."
