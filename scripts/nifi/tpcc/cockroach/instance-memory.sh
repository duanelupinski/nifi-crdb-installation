#!/bin/bash

database_address=$1
terraform_path=$2
provider=$3
key_name=$4
key_user=$5
if [[ ! -z ${key_name} && ! ${key_name} == /* ]]; then
    key_name=${terraform_path}/${key_name}
fi
if [[ -z ${key_user} ]]; then
    key_user="debian"
fi

command="$(cat <<-EOF
	mem=\$(echo "scale=4; \$(echo \$(lsmem | egrep '^Total online memory') | cut -f2 -d':' | cut -f2 -d' ' | tr -d -c [.0-9])" | bc -l)
	unit=\$(echo \$(lsmem | egrep '^Total online memory') | cut -f2 -d':' | cut -f2 -d' ' | tr -d [.0-9])

	if (( \$(echo "\${mem} < 4" | bc -l) )); then
		mem=\$(echo "scale=0; \${mem} * 1024" | bc)
		case \${unit} in
		G)
			unit=M
			;;
		M)
			unit=K
			;;
		esac
	fi
	mem=\$(echo \${mem} | cut -f1 -d'.')
	if (( \${mem} % 4 )); then
		mem=\$(( (\${mem} + 4) / 4 * 4 ))
	fi
	mem=\$(echo "x=l(\${mem})/l(2); scale=0; 2^((x+0.5)/1)" | bc -l;)

	echo \$mem \$unit
EOF
)"

if [[ ${provider} == 'vbox' || -z ${key_name} ]]; then
	ssh -q -tt -o StrictHostKeyChecking=no ${key_user}@${database_address} "${command}"
else
	ssh -q -i ${key_name} -tt -o StrictHostKeyChecking=no ${key_user}@${database_address} "${command}"
fi
